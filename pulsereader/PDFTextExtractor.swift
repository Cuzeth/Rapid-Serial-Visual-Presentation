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
            // but preserve compound words (e.g. "one-in-a-" + "lifetime" → "one-in-a-lifetime")
            while word.hasSuffix("-") && i + 1 < raw.count {
                let nextWord = raw[i + 1]
                guard let nextFirst = nextWord.first, nextFirst.isLowercase else { break }
                let stem = word.dropLast()
                if stem.contains("-") {
                    // Compound word split at line break — keep the hyphen
                    word = word + nextWord
                } else {
                    // Simple line-break hyphenation — drop the hyphen
                    word = String(stem) + nextWord
                }
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
