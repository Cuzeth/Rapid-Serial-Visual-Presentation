import Foundation
import SwiftData

/// A persisted document in the user's library.
///
/// Words are stored as a newline-delimited blob in external storage
/// (`wordsBlob`) to keep the SQLite database lean. The legacy `words`
/// array is retained only for migration from older versions.
@Model
final class Document {
    @Attribute(.unique) var id: UUID
    var title: String
    var fileName: String
    var dateAdded: Date
    var lastReadDate: Date?
    /// Security-scoped bookmark for re-accessing the original file.
    var bookmarkData: Data
    /// Legacy word storage — empty for new documents. See ``compactWordStorageIfNeeded()``.
    var words: [String]
    /// Newline-delimited word data stored externally to avoid bloating the database.
    @Attribute(.externalStorage) var wordsBlob: Data?
    var chapters: [Chapter]
    var currentWordIndex: Int
    var wordsPerMinute: Int

    /// Stored separately so the list view can display word count
    /// without deserializing the entire words array.
    var wordCount: Int

    /// In-memory cache of the decoded words array, invalidated on compaction.
    @Transient private var cachedWords: [String]?

    /// The document's words, resolved from `wordsBlob` (preferred) or the legacy `words` array.
    /// Results are cached in memory for the lifetime of the model object.
    var readingWords: [String] {
        if let cachedWords {
            return cachedWords
        }

        let resolvedWords: [String]
        if let wordsBlob, !wordsBlob.isEmpty {
            resolvedWords = WordStorage.decode(wordsBlob)
        } else {
            resolvedWords = words
        }

        cachedWords = resolvedWords
        return resolvedWords
    }

    /// Migrates words from the legacy `words` array to the `wordsBlob` external storage format.
    /// No-op if `wordsBlob` already exists or the legacy array is empty.
    func compactWordStorageIfNeeded() {
        guard wordsBlob == nil, !words.isEmpty else { return }
        let legacyCount = words.count
        wordsBlob = WordStorage.encode(words)
        words.removeAll(keepingCapacity: false)
        wordCount = legacyCount
        cachedWords = nil
    }

    /// Reading progress as a value from 0.0 to 1.0.
    var progress: Double {
        guard wordCount > 1 else { return currentWordIndex > 0 ? 1 : 0 }
        return Double(currentWordIndex) / Double(wordCount - 1)
    }

    init(
        title: String,
        fileName: String,
        bookmarkData: Data,
        words: [String],
        chapters: [Chapter] = [],
        currentWordIndex: Int = 0,
        wordsPerMinute: Int = 300
    ) {
        self.id = UUID()
        self.title = title
        self.fileName = fileName
        self.bookmarkData = bookmarkData
        self.wordsBlob = WordStorage.encode(words)
        self.words = []
        self.chapters = chapters
        self.wordCount = words.count
        self.currentWordIndex = currentWordIndex
        self.wordsPerMinute = wordsPerMinute
        self.dateAdded = Date()
        self.cachedWords = words
    }
}
