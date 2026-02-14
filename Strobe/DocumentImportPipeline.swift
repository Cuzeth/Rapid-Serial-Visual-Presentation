import Foundation
internal import UniformTypeIdentifiers

enum DocumentSourceType: String, Equatable {
    case pdf
    case epub
    case unknown
}

struct ImportResult {
    let words: [String]
    let chapters: [Chapter]
    let sourceType: DocumentSourceType
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

    nonisolated static func extractWordsAndChapters(
        from url: URL,
        detectedContentType: UTType? = nil
    ) throws -> ImportResult {
        let type = resolveSourceType(for: url, detectedContentType: detectedContentType)
        switch type {
        case .pdf:
            let result = PDFTextExtractor.extractWordsAndChapters(from: url)
            return ImportResult(words: result.words, chapters: result.chapters, sourceType: .pdf)
        case .epub:
            let words = try EPUBTextExtractor.extractWords(from: url)
            return ImportResult(words: words, chapters: [], sourceType: .epub)
        case .unknown:
            throw DocumentImportError.unsupportedFileType
        }
    }
}
