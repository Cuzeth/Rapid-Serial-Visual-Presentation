import Foundation

/// Errors that can occur during document import.
enum DocumentImportError: Error, Equatable, LocalizedError {
    case unsupportedFileType
    case epubExtractionFailed
    case noReadableText

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Unsupported file type. Import a PDF or EPUB file."
        case .epubExtractionFailed:
            return "Could not read this EPUB file. It may be corrupted or DRM-protected."
        case .noReadableText:
            return "Could not extract text from this document. It may be image-only."
        }
    }
}
