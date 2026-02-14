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
    var chapters: [Chapter]
    var currentWordIndex: Int
    var wordsPerMinute: Int

    /// Stored separately so the list view can display word count
    /// without deserializing the entire words array.
    var wordCount: Int

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
        self.words = words
        self.chapters = chapters
        self.wordCount = words.count
        self.currentWordIndex = currentWordIndex
        self.wordsPerMinute = wordsPerMinute
        self.dateAdded = Date()
    }
}
