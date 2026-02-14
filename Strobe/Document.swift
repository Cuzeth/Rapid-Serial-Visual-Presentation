import Foundation
import SwiftData

@Model
final class Document {
    @Attribute(.unique) var id: UUID
    var title: String
    var fileName: String
    var dateAdded: Date
    var lastReadDate: Date?
    var bookmarkData: Data
    var words: [String]
    @Attribute(.externalStorage) var wordsBlob: Data?
    var chapters: [Chapter]
    var currentWordIndex: Int
    var wordsPerMinute: Int

    /// Stored separately so the list view can display word count
    /// without deserializing the entire words array.
    var wordCount: Int

    @Transient private var cachedWords: [String]?

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

    func compactWordStorageIfNeeded() {
        guard wordsBlob == nil, !words.isEmpty else { return }
        let legacyCount = words.count
        wordsBlob = WordStorage.encode(words)
        words.removeAll(keepingCapacity: false)
        wordCount = legacyCount
        cachedWords = nil
    }

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
