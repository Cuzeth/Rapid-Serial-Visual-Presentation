import PDFKit

enum PDFTextExtractor {

    static func extractWords(from url: URL) -> [String] {
        guard let document = PDFDocument(url: url) else { return [] }

        var fullText = ""
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i),
                  let text = page.string else { continue }
            fullText += text + " "
        }

        return tokenize(fullText)
    }

    static func tokenize(_ text: String) -> [String] {
        let raw = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var result: [String] = []
        var i = 0
        while i < raw.count {
            var word = raw[i]
            // Rejoin hyphenated line breaks (e.g. "infor-" + "mation" → "information")
            while word.hasSuffix("-") && i + 1 < raw.count {
                word = String(word.dropLast()) + raw[i + 1]
                i += 1
            }
            if !word.isEmpty {
                result.append(word)
            }
            i += 1
        }

        return result
    }
}
