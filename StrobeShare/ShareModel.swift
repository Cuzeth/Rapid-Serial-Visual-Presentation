import Foundation
import Observation

/// The share sheet's state: finding the text, then the item waiting for
/// the person to add it.
@Observable
final class ShareModel {
    enum Phase: Equatable {
        case loading
        case ready
        case nothingToRead
        case added
    }

    private(set) var phase = Phase.loading
    private(set) var item: SharedItem?
    /// The title the item will be added with, editable before adding.
    var title = ""
    private(set) var wordCount = 0
    /// Enough of the text to recognize it by.
    private(set) var excerpt = ""
    var addError: String?

    /// The app's default speed, for the reading-time estimate. Nil until the
    /// app has run once since installing.
    let wordsPerMinute = ShareInbox.publishedReadingSpeed
    private let inbox = ShareInbox.shared

    /// Closes the extension: true after adding, false when cancelled.
    @ObservationIgnored var onFinish: (_ added: Bool) -> Void = { _ in }

    /// How long the confirmation stays up before the sheet closes.
    private static let confirmationDuration: Duration = .milliseconds(900)
    nonisolated private static let excerptLength = 1_500

    /// Where the text came from, such as "nytimes.com".
    var sourceName: String? {
        guard let host = item?.sourceURL?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var canAdd: Bool {
        phase == .ready && inbox != nil
    }

    func load(_ extensionItems: [NSExtensionItem]) async {
        guard let item = await SharedContentLoader.item(from: extensionItems) else {
            phase = .nothingToRead
            return
        }
        let text = item.text
        (wordCount, excerpt) = await Task.detached(priority: .userInitiated) {
            (ApproximateWordCount.of(text), Self.excerpt(of: text))
        }.value
        self.item = item
        title = item.title
        phase = .ready
    }

    func add() {
        guard canAdd, var item, let inbox else { return }
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.dateShared = Date()
        do {
            try inbox.add(item)
        } catch {
            addError = error.localizedDescription
            return
        }
        ShareInbox.postDidChange()
        phase = .added
        Task {
            try? await Task.sleep(for: Self.confirmationDuration)
            onFinish(true)
        }
    }

    func cancel() {
        onFinish(false)
    }

    nonisolated private static func excerpt(of text: String) -> String {
        let start = text.drop(while: \.isWhitespace)
        let excerpt = start.prefix(excerptLength).trimmingCharacters(in: .whitespacesAndNewlines)
        return start.count > excerptLength ? excerpt + "\u{2026}" : excerpt
    }
}
