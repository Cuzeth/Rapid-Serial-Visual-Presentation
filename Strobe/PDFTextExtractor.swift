import PDFKit

struct PDFExtractionResult {
    let words: [String]
    let chapters: [Chapter]
}

enum PDFTextExtractor {

    nonisolated static func extractWords(from url: URL) -> [String] {
        extractWordsAndChapters(from: url).words
    }

    nonisolated static func extractWordsAndChapters(from url: URL) -> PDFExtractionResult {
        guard let document = PDFDocument(url: url) else {
            return PDFExtractionResult(words: [], chapters: [])
        }

        var result: [String] = []
        result.reserveCapacity(document.pageCount * 250)

        var pageWordOffsets: [Int] = []
        pageWordOffsets.reserveCapacity(document.pageCount)

        var carry: String?
        for i in 0..<document.pageCount {
            autoreleasepool {
                pageWordOffsets.append(result.count)
                guard let page = document.page(at: i),
                      let text = page.string else { return }
                Tokenizer.appendTokenizedText(text, into: &result, carry: &carry)
            }
        }

        if let carry, !carry.isEmpty {
            result.append(carry)
        }

        let chapters = extractChapters(from: document, pageWordOffsets: pageWordOffsets)
        return PDFExtractionResult(words: result, chapters: chapters)
    }

    // MARK: - Chapter extraction

    nonisolated private static func extractChapters(
        from document: PDFDocument,
        pageWordOffsets: [Int]
    ) -> [Chapter] {
        guard let outlineRoot = document.outlineRoot else { return [] }

        var chapters: [Chapter] = []

        for i in 0..<outlineRoot.numberOfChildren {
            guard let child = outlineRoot.child(at: i) else { continue }
            guard let label = child.label, !label.isEmpty else { continue }
            guard let destination = child.destination,
                  let page = destination.page else { continue }
            let pageIndex = document.index(for: page)

            let wordIndex = pageIndex < pageWordOffsets.count
                ? pageWordOffsets[pageIndex]
                : 0
            chapters.append(Chapter(title: label, wordIndex: wordIndex))
        }

        chapters.sort { $0.wordIndex < $1.wordIndex }

        var seen = Set<Int>()
        chapters = chapters.filter { seen.insert($0.wordIndex).inserted }

        return chapters
    }
}
