import Foundation
import os

/// Text shared to Strobe from another app, waiting to be added to the
/// library.
nonisolated struct SharedItem: Codable, Identifiable, Equatable {
    nonisolated enum Source: String, Codable {
        /// The article text Strobe pulled from a web page. Cleaned on import
        /// like a text file, since it can carry page furniture.
        case webPage
        /// Text the person chose: a selection, or text shared from any app.
        /// Kept exactly as shared, like New Text.
        case text
    }

    var id = UUID()
    var source: Source
    /// The title the person confirmed; empty to use the default.
    var title: String
    var text: String
    /// The page the text came from, if any.
    var sourceURL: URL?
    var dateShared = Date()
}

// MARK: - Items from what was shared

nonisolated extension SharedItem {
    /// Keys of the dictionary `ArticleExtractor.js` returns.
    nonisolated enum PageKey {
        static let title = "title"
        static let text = "text"
        static let url = "url"
        static let isSelection = "isSelection"
    }

    /// The item for what `ArticleExtractor.js` found on a page: the
    /// person's selection if they made one, or else the page's article.
    /// Nil when it found no words.
    init?(pageResults results: [String: Any]) {
        guard let text = results[PageKey.text] as? String,
              ApproximateWordCount.of(text) > 0 else { return nil }
        let isSelection = results[PageKey.isSelection] as? Bool ?? false
        self.init(
            source: isSelection ? .text : .webPage,
            title: Self.collapsingWhitespace(results[PageKey.title] as? String ?? ""),
            text: text,
            sourceURL: (results[PageKey.url] as? String).flatMap(Self.webURL(from:))
        )
    }

    /// The item for text shared from any app, titled by its first line when
    /// that line reads as a heading. Nil when the text has no words.
    init?(text: String, sourceURL: URL? = nil) {
        guard ApproximateWordCount.of(text) > 0 else { return nil }
        self.init(
            source: .text,
            title: Self.suggestedTitle(forText: text),
            text: text,
            sourceURL: sourceURL
        )
    }

    /// The first line of `text` when it reads as a heading: short, followed
    /// by more text, and not ending the way a sentence or salutation does.
    /// Empty otherwise, so the library's default title applies.
    static func suggestedTitle(forText text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count > 1, let first = lines.first,
              first.count <= 80,
              ApproximateWordCount.of(first) <= 12,
              let last = first.last, !".,;:".contains(last) else { return "" }
        return collapsingWhitespace(first)
    }

    /// `string` as a web address, when an http or https URL is all it holds.
    static func webURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host()?.isEmpty == false else { return nil }
        return url
    }

    private static func collapsingWhitespace(_ string: String) -> String {
        string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// A folder in the App Group where the share extension leaves
/// ``SharedItem``s for the app to add to the library.
///
/// The extension writes one JSON file per item and posts
/// ``didChangeNotification``; the app imports and removes them when it
/// becomes active or hears the notification. The app never needs to be
/// running for a share to succeed.
nonisolated struct ShareInbox {
    let directory: URL

    /// The inbox in the App Group container, or nil when the build isn't
    /// entitled to the group.
    static var shared: ShareInbox? {
        SharedContainer.containerURL.map {
            ShareInbox(directory: $0.appendingPathComponent("ShareInbox", isDirectory: true))
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.abdeen.strobe",
        category: "ShareInbox"
    )
    private static let fileExtension = "json"

    /// Leaves an item for the app. The write is atomic, so the app never
    /// reads a partial file.
    func add(_ item: SharedItem) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(item)
        try data.write(to: fileURL(for: item.id), options: .atomic)
    }

    /// Every waiting item, oldest share first. Files that can't be read as
    /// an item are removed, so one bad file can't stall the inbox.
    func pendingItems() -> [SharedItem] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        let decoder = JSONDecoder()
        var items: [SharedItem] = []
        for file in files where file.pathExtension == Self.fileExtension {
            do {
                items.append(try decoder.decode(SharedItem.self, from: Data(contentsOf: file)))
            } catch {
                Self.logger.error("Discarding unreadable shared item \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: file)
            }
        }
        return items.sorted { $0.dateShared < $1.dateShared }
    }

    func remove(_ item: SharedItem) {
        try? FileManager.default.removeItem(at: fileURL(for: item.id))
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(Self.fileExtension)
    }

    // MARK: - Change notification

    /// A Darwin notification the extension posts after adding an item, so a
    /// running app imports it right away. Named under the App Group, as the
    /// macOS sandbox requires.
    static let didChangeNotification = SharedContainer.appGroupID + ".shareInboxDidChange"

    static func postDidChange() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(didChangeNotification as CFString),
            nil, nil, true
        )
    }

    // MARK: - Reading speed

    private static let readingSpeedKey = "shareInboxWordsPerMinute"

    /// Called by the app so the share sheet can estimate reading time at the
    /// person's default speed.
    static func publishReadingSpeed(_ wordsPerMinute: Int) {
        SharedContainer.defaults?.set(wordsPerMinute, forKey: readingSpeedKey)
    }

    /// The default speed the app last published, or nil before it has.
    static var publishedReadingSpeed: Int? {
        let speed = SharedContainer.defaults?.integer(forKey: readingSpeedKey) ?? 0
        return speed > 0 ? speed : nil
    }
}
