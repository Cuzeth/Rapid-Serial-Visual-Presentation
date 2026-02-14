import Foundation
internal import UniformTypeIdentifiers

enum DocumentSourceType: Equatable {
    case pdf
    case epub
    case unknown
}

enum DocumentImportPipeline {
    nonisolated static let supportedContentTypes: [UTType] = [.pdf, .epub]

    nonisolated static func resolveSourceType(for url: URL, detectedContentType: UTType? = nil) -> DocumentSourceType {
        if let detectedContentType {
            if detectedContentType.conforms(to: .pdf) { return .pdf }
            if detectedContentType.conforms(to: .epub) { return .epub }
        }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        default:
            return .unknown
        }
    }

    nonisolated static func extractWords(from url: URL, detectedContentType: UTType? = nil) throws -> [String] {
        switch resolveSourceType(for: url, detectedContentType: detectedContentType) {
        case .pdf:
            return PDFTextExtractor.extractWords(from: url)
        case .epub:
            return try EPUBTextExtractor.extractWords(from: url)
        case .unknown:
            throw DocumentImportError.unsupportedFileType
        }
    }
}
