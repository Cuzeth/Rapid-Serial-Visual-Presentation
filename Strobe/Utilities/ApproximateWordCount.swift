import Foundation

/// A quick word count for showing while text is typed or shared, before the
/// tokenizer runs: each CJK ideograph counts as a word, and other text
/// splits at whitespace.
nonisolated enum ApproximateWordCount {
    static func of(_ text: String) -> Int {
        var cjkCount = 0
        var latinBuffer = ""
        var latinWords = 0

        for scalar in text.unicodeScalars {
            let isCJK = CJKUtilities.isHanIdeograph(scalar)

            if isCJK {
                cjkCount += 1
                if !latinBuffer.isEmpty {
                    latinWords += latinBuffer.split(whereSeparator: \.isWhitespace).count
                    latinBuffer.removeAll(keepingCapacity: true)
                }
            } else {
                latinBuffer.unicodeScalars.append(scalar)
            }
        }

        if !latinBuffer.isEmpty {
            latinWords += latinBuffer.split(whereSeparator: \.isWhitespace).count
        }

        return cjkCount + latinWords
    }
}
