import Foundation
import UniformTypeIdentifiers
import os
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Finds the text in what was shared to the extension.
///
/// In order of preference: what `ArticleExtractor.js` found on a page
/// Safari shared, the page a shared link points to (read by
/// ``WebPageReader``), then plain text. A link usually arrives with a
/// caption or the page title as text, so the page comes first, and the text
/// is the fallback when the page can't be read.
enum SharedContentLoader {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.abdeen.strobe.share",
        category: "SharedContentLoader"
    )

    /// Larger text files are books, better imported in the app.
    private static let maxTextFileBytes = 16 << 20

    static func item(from extensionItems: [NSExtensionItem]) async -> SharedItem? {
        let providers = extensionItems.flatMap { $0.attachments ?? [] }

        for provider in providers {
            if let results = await pageResults(from: provider),
               let item = SharedItem(pageResults: results) {
                return item
            }
        }

        var text = await sharedText(from: providers)
        if text == nil {
            text = extensionItems.lazy
                .compactMap { $0.attributedContentText?.string }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        var link = await webURL(from: providers)
        if link == nil, let text {
            link = SharedItem.webURL(from: text)
        }

        if let link {
            do {
                if let item = SharedItem(pageResults: try await WebPageReader().read(link)) {
                    return item
                }
            } catch {
                logger.error("Couldn't read the shared page: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Text that was only the link has nothing more to offer.
        guard let text, SharedItem.webURL(from: text) == nil else { return nil }
        return SharedItem(text: text, sourceURL: link)
    }

    /// The dictionary `ArticleExtractor.js` returned, when Safari ran it.
    private static func pageResults(from provider: NSItemProvider) async -> [String: Any]? {
        let type = UTType.propertyList.identifier
        guard provider.hasItemConformingToTypeIdentifier(type),
              let item = try? await provider.loadItem(forTypeIdentifier: type) as? [String: Any] else { return nil }
        return item[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
    }

    private static func webURL(from providers: [NSItemProvider]) async -> URL? {
        let type = UTType.url.identifier
        for provider in providers where provider.hasItemConformingToTypeIdentifier(type) {
            guard let item = try? await provider.loadItem(forTypeIdentifier: type) else { continue }
            let string = (item as? URL)?.absoluteString ?? (item as? Data).map { String(decoding: $0, as: UTF8.self) }
            if let url = string.flatMap(SharedItem.webURL(from:)) { return url }
        }
        return nil
    }

    /// Shared plain or rich text, or the contents of a shared text file.
    private static func sharedText(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
               let text = string(from: item) {
                return text
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier),
               let data = try? await provider.loadItem(forTypeIdentifier: UTType.rtf.identifier) as? Data,
               let attributed = try? NSAttributedString(
                   data: data,
                   options: [.documentType: NSAttributedString.DocumentType.rtf],
                   documentAttributes: nil
               ) {
                return attributed.string
            }
        }
        return nil
    }

    /// The text in a loaded plain-text item, which apps send as a string,
    /// attributed string, raw data, or a file.
    private static func string(from item: any NSSecureCoding) -> String? {
        switch item {
        case let string as String:
            return string
        case let attributed as NSAttributedString:
            return attributed.string
        case let data as Data:
            return String(decoding: data, as: UTF8.self)
        case let url as URL where url.isFileURL:
            return textFile(at: url)
        default:
            return nil
        }
    }

    private static func textFile(at url: URL) -> String? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maxTextFileBytes, let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
