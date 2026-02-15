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
    let title: String?
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

    /// Returns the document's metadata title if available, otherwise cleans up the filename.
    nonisolated static func resolveTitle(metadataTitle: String?, fileName: String) -> String {
        if let metadataTitle, !metadataTitle.isEmpty {
            return metadataTitle
        }
        return cleanFileName(fileName)
    }

    /// Turns `_OCEanpdf_Labor_from_blah.pdf` into `OCEanpdf Labor From Blah`.
    nonisolated private static func cleanFileName(_ fileName: String) -> String {
        // Strip extension
        var name = fileName
        if let dotRange = name.range(of: ".", options: .backwards) {
            let ext = String(name[dotRange.upperBound...]).lowercased()
            if ["pdf", "epub"].contains(ext) {
                name = String(name[..<dotRange.lowerBound])
            }
        }

        // Replace underscores, hyphens, and dots used as separators with spaces
        var cleaned = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")

        // Collapse multiple spaces and trim
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return fileName }

        // Title-case each word (capitalize first letter, keep the rest)
        return cleaned.split(separator: " ").map { word in
            guard let first = word.first else { return String(word) }
            return String(first).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    nonisolated static func extractWordsAndChapters(
        from url: URL,
        detectedContentType: UTType? = nil,
        cleaningLevel: TextCleaningLevel = .standard
    ) throws -> ImportResult {
        let type = resolveSourceType(for: url, detectedContentType: detectedContentType)
        switch type {
        case .pdf:
            let result = PDFTextExtractor.extractWordsAndChapters(from: url, cleaningLevel: cleaningLevel)
            return ImportResult(words: result.words, chapters: result.chapters, sourceType: .pdf, title: result.title)
        case .epub:
            let result = try EPUBTextExtractor.extractWordsAndChapters(from: url, cleaningLevel: cleaningLevel)
            return ImportResult(words: result.words, chapters: result.chapters, sourceType: .epub, title: result.title)
        case .unknown:
            throw DocumentImportError.unsupportedFileType
        }
    }
}
