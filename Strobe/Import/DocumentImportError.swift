import Foundation

/// Errors that can occur during document import.
enum DocumentImportError: Error, Equatable, LocalizedError {
    case unsupportedFileType
    case epubExtractionFailed
    case epubDRMProtected
    case pdfLoadFailed
    case pdfPasswordProtected
    case noReadableText

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Unsupported file type. Import a PDF or EPUB file."
        case .epubExtractionFailed:
            return "Could not read this EPUB file. It may be corrupted or DRM-protected."
        case .epubDRMProtected:
            return "This EPUB is DRM-protected and can't be imported. Only DRM-free books are supported."
        case .pdfLoadFailed:
            return "Could not open this PDF file. It may be corrupted."
        case .pdfPasswordProtected:
            return "This PDF is password-protected. Remove the password and try again."
        case .noReadableText:
            return "Could not extract text from this document. It may be image-only."
        }
    }
}
