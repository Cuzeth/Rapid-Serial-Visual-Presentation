import Foundation

enum DocumentImportError: Error, Equatable, LocalizedError {
    case unsupportedFileType
    case epubParsingNotImplemented
    case noReadableText

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Unsupported file type. Import a PDF or EPUB file."
        case .epubParsingNotImplemented:
            return "EPUB import is not implemented yet. The parser pipeline is ready for it."
        case .noReadableText:
            return "Could not extract text from this document. It may be image-only."
        }
    }
}
