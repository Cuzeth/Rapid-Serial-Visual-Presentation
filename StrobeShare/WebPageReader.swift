import Foundation
import WebKit

/// Reads a page in an offscreen web view and runs `ArticleExtractor.js` on
/// it, for links shared from apps other than Safari.
///
/// The page loads first without its own scripts: that's faster, and it
/// skips the overlays and paywall scripts that hide article text. A page
/// that builds its text with script comes back nearly empty that way, so
/// it loads again with scripts on. Either way it loads without cookies,
/// images, media, or web fonts.
@MainActor
final class WebPageReader: NSObject {
    enum ReadError: Error {
        case missingScript
        case noResults
    }

    /// Past this, the page is read as far as it has loaded.
    private static let loadTimeout: Duration = .seconds(15)
    /// A script-free load with fewer words than this is tried again with scripts.
    private static let scriptFreeMinimumWords = 60

    private static let extractorScript: String? = Bundle.main
        .url(forResource: "ArticleExtractor", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    private var loadContinuation: CheckedContinuation<Void, Error>?

    /// The dictionary `ArticleExtractor.js` returns for the page at `url`.
    func read(_ url: URL) async throws -> [String: Any] {
        guard let script = Self.extractorScript else { throw ReadError.missingScript }

        let scriptFree: [String: Any]?
        do {
            scriptFree = try await read(url, script: script, allowingPageScripts: false)
        } catch let error as URLError {
            // The page can't be reached, and its scripts won't change that.
            throw error
        } catch {
            scriptFree = nil
        }
        if let scriptFree, Self.wordCount(of: scriptFree) >= Self.scriptFreeMinimumWords {
            return scriptFree
        }
        let scripted = try? await read(url, script: script, allowingPageScripts: true)
        let best = [scriptFree, scripted]
            .compactMap { $0 }
            .max { Self.wordCount(of: $0) < Self.wordCount(of: $1) }
        guard let best else { throw ReadError.noResults }
        return best
    }

    private func read(_ url: URL, script: String, allowingPageScripts: Bool) async throws -> [String: Any] {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = allowingPageScripts
        if let rules = await Self.blockingRules() {
            configuration.userContentController.add(rules)
        }
        // A tablet-sized viewport: wide enough for the article layout,
        // narrow enough to leave out most sidebars.
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 834, height: 1194), configuration: configuration)
        webView.navigationDelegate = self
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
        }

        let timeout = Task { [weak self] in
            try await Task.sleep(for: Self.loadTimeout)
            self?.finishLoading(.success(()))
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            webView.load(URLRequest(url: url))
        }

        // Runs apart from the page's own scripts, which can't interfere.
        let result = try await webView.callAsyncJavaScript(
            script + "\nreturn StrobeArticle.extract();",
            contentWorld: .defaultClient
        )
        guard let results = result as? [String: Any] else { throw ReadError.noResults }
        return results
    }

    private func finishLoading(_ result: Result<Void, Error>) {
        loadContinuation?.resume(with: result)
        loadContinuation = nil
    }

    private static func wordCount(of results: [String: Any]) -> Int {
        ApproximateWordCount.of(results[SharedItem.PageKey.text] as? String ?? "")
    }

    /// Blocks what the text doesn't need, so pages load faster and lighter.
    private static func blockingRules() async -> WKContentRuleList? {
        let rules = #"[{"trigger":{"url-filter":".*","resource-type":["image","media","font"]},"action":{"type":"block"}}]"#
        return try? await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "StrobeShareBlockedResources",
            encodedContentRuleList: rules
        )
    }
}

extension WebPageReader: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(with: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(with: error)
    }

    private func fail(with error: Error) {
        // A redirect cancels the navigation it replaces; the page is still loading.
        if (error as? URLError)?.code == .cancelled { return }
        finishLoading(.failure(error))
    }
}
