import PDFKit

struct PDFExtractionResult {
    let words: [String]
    let chapters: [Chapter]
    let title: String?
}

enum PDFTextExtractor {

    nonisolated static func extractWords(from url: URL) -> [String] {
        extractWordsAndChapters(from: url).words
    }

    nonisolated static func extractWordsAndChapters(
        from url: URL,
        cleaningLevel: TextCleaningLevel = .standard
    ) -> PDFExtractionResult {
        guard let document = PDFDocument(url: url) else {
            return PDFExtractionResult(words: [], chapters: [], title: nil)
        }

        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }

        // Phase 1: Collect raw text from each page
        var pageTexts: [String] = []
        pageTexts.reserveCapacity(document.pageCount)

        for i in 0..<document.pageCount {
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
        result.reserveCapacity(document.pageCount * 250)

        var pageWordOffsets: [Int] = []
        pageWordOffsets.reserveCapacity(document.pageCount)

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
