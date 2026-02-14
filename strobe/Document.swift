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
    var currentWordIndex: Int
    var wordsPerMinute: Int

    var wordCount: Int { words.count }

    var progress: Double {
        guard wordCount > 0 else { return 0 }
        return Double(currentWordIndex) / Double(wordCount)
    }

    init(
        title: String,
        fileName: String,
        bookmarkData: Data,
        words: [String],
        currentWordIndex: Int = 0,
        wordsPerMinute: Int = 300
    ) {
        self.id = UUID()
        self.title = title
        self.fileName = fileName
        self.bookmarkData = bookmarkData
        self.words = words
        self.currentWordIndex = currentWordIndex
        self.wordsPerMinute = wordsPerMinute
        self.dateAdded = Date()
    }
}
