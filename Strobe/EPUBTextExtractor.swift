import Foundation

enum EPUBTextExtractor {
    nonisolated static func extractWords(from _: URL) throws -> [String] {
        throw DocumentImportError.epubParsingNotImplemented
    }
}
