import PDFKit
import os

/// The result of extracting text from a PDF file.
struct PDFExtractionResult {
    let words: [String]
    let chapters: [Chapter]
    let title: String?
}

/// Extracts tokenized words and chapter structure from PDF files using PDFKit.
///
/// The extraction pipeline: read pages → clean text (cross-page header/footer
/// detection + per-page boilerplate removal) → tokenize → extract chapters
/// from the PDF outline.
enum PDFTextExtractor {

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.abdeen.strobe",
        category: "PDFTextExtractor"
    )

    /// Upper bound on pages processed per import. Far beyond any real book —
    /// this exists so a crafted PDF declaring an enormous page count can't
    /// pin the import task's CPU and memory indefinitely.
    nonisolated static let maxProcessedPages = 20_000

    /// Extracts words and chapters from a PDF file.
    /// - Parameters:
    ///   - url: The file URL of the PDF document.
    ///   - cleaningLevel: How aggressively to remove boilerplate text.
    /// - Returns: Tokenized words, chapter list, and metadata title.
    ///   Throws ``DocumentImportError/pdfLoadFailed`` if the PDF cannot be opened.
    nonisolated static func extractWordsAndChapters(
        from url: URL,
        cleaningLevel: TextCleaningLevel = .standard
    ) throws -> PDFExtractionResult {
        guard let document = PDFDocument(url: url) else {
            throw DocumentImportError.pdfLoadFailed
        }

        // A locked document opens fine but yields no page text — without this
        // check it would fall through to the misleading "image-only" error.
        guard !document.isLocked else {
            throw DocumentImportError.pdfPasswordProtected
        }

        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }

        let pageCount = min(document.pageCount, maxProcessedPages)
        if document.pageCount > maxProcessedPages {
            logger.warning("PDF declares \(document.pageCount) pages; processing the first \(maxProcessedPages).")
        }

        // Phase 1: Collect raw text from each page
        var pageTexts: [String] = []
        pageTexts.reserveCapacity(pageCount)

        for i in 0..<pageCount {
            // Keep a cancelled import (user tapped Cancel) from grinding
            // through the rest of a large document.
            if i % 64 == 0 { try Task.checkCancellation() }
            autoreleasepool {
                if let page = document.page(at: i), let text = page.string {
                    pageTexts.append(text)
                } else {
                    pageTexts.append("")
                }
            }
        }

        // Phase 2: Clean text (cross-page analysis + per-page rules)
        let cleanedPages = TextCleaner.cleanPages(pageTexts, level: cleaningLevel)

        // Phase 3: Tokenize cleaned pages
        var result: [String] = []
        result.reserveCapacity(pageCount * 250)

        var pageWordOffsets: [Int] = []
        pageWordOffsets.reserveCapacity(pageCount)

        var carry: String?
        for text in cleanedPages {
            pageWordOffsets.append(result.count)
            Tokenizer.appendTokenizedText(text, into: &result, carry: &carry)
        }

        if let carry, !carry.isEmpty {
            result.append(carry)
        }

        let chapters = extractChapters(from: document, pageWordOffsets: pageWordOffsets)
        return PDFExtractionResult(words: result, chapters: chapters, title: title)
    }

    // MARK: - Chapter extraction

    /// Extracts chapters from the PDF outline (bookmarks), walking up to two
    /// levels deep to handle "Part > Chapter" nesting.
    nonisolated private static func extractChapters(
        from document: PDFDocument,
        pageWordOffsets: [Int]
    ) -> [Chapter] {
        guard let outlineRoot = document.outlineRoot else { return [] }

        var chapters: [Chapter] = []

        func addOutlineItem(_ item: PDFOutline) {
            guard let label = item.label, !label.isEmpty else { return }
            guard let destination = item.destination,
                  let page = destination.page else { return }
            let pageIndex = document.index(for: page)

            let wordIndex = pageIndex < pageWordOffsets.count
                ? pageWordOffsets[pageIndex]
                : 0
            chapters.append(Chapter(title: label, wordIndex: wordIndex))
        }

        // Walk up to two levels: handles both flat outlines and
        // "Part > Chapter" nesting common in non-fiction books.
        for i in 0..<outlineRoot.numberOfChildren {
            guard let child = outlineRoot.child(at: i) else { continue }
            addOutlineItem(child)

            // If this top-level item has children, include them too
            for j in 0..<child.numberOfChildren {
                guard let grandchild = child.child(at: j) else { continue }
                addOutlineItem(grandchild)
            }
        }

        chapters.sort { $0.wordIndex < $1.wordIndex }

        var seen = Set<Int>()
        chapters = chapters.filter { seen.insert($0.wordIndex).inserted }

        return chapters
    }
}
