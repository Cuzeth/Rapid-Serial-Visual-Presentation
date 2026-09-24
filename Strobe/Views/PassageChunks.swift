import Foundation

/// Where the passage view splits a document into the chunks it renders
/// lazily. Every chunk starts on a new line, so chunks end only where a line
/// break reads naturally: around a chapter heading, or after a sentence.
///
/// Stored words keep no paragraph breaks, so between headings a chunk ends
/// after the sentence end (by ``SentenceBreak``) closest to ``targetSize``
/// words in, looking up to half that far either way. Text with no sentence
/// end in that stretch breaks at exactly ``targetSize`` words. A final
/// stretch of up to one and a half times the target stays one chunk rather
/// than leaving a short tail.
nonisolated struct PassageChunks: Equatable {
    /// The chunk length to aim for.
    static let targetSize = 200

    /// The first word of each chunk, ascending. Empty for an empty document.
    let starts: [Int]
    let wordCount: Int

    /// - Parameters:
    ///   - words: The document's words.
    ///   - blockStarts: Words that must start a chunk, such as a chapter
    ///     heading's first word and the first word after it. Indices outside
    ///     the document, and repeats, are ignored.
    ///   - targetSize: The chunk length to aim for.
    init(words: [String], blockStarts: [Int] = [], targetSize: Int = PassageChunks.targetSize) {
        wordCount = words.count
        guard !words.isEmpty else {
            starts = []
            return
        }
        let target = max(1, targetSize)
        let longest = target + target / 2
        let blocks = Set(blockStarts.filter { $0 > 0 && $0 < words.count }).sorted()

        var starts: [Int] = []
        var blockStart = 0
        for blockEnd in blocks + [words.count] {
            var start = blockStart
            starts.append(start)
            while blockEnd - start > longest {
                start = Self.nextStart(after: start, target: target, in: words)
                starts.append(start)
            }
            blockStart = blockEnd
        }
        self.starts = starts
    }

    var count: Int { starts.count }

    /// The words in chunk `index`. Empty for an index outside the document.
    func range(at index: Int) -> Range<Int> {
        guard starts.indices.contains(index) else {
            return index < 0 ? 0..<0 : wordCount..<wordCount
        }
        let end = index + 1 < starts.count ? starts[index + 1] : wordCount
        return starts[index]..<end
    }

    /// The chunk holding `wordIndex`, clamped to the first and last chunks.
    /// 0 for an empty document.
    func index(containing wordIndex: Int) -> Int {
        var low = 0
        var high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= wordIndex {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(0, low - 1)
    }

    /// The first word of the chunk after the one starting at `start`: just
    /// past the sentence end nearest `target` words in, the shorter chunk on
    /// a tie. The caller guarantees more than one and a half times `target`
    /// words remain, so every candidate has a word after it.
    private static func nextStart(after start: Int, target: Int, in words: [String]) -> Int {
        for distance in 0...(target / 2) {
            let shorter = start + target - distance
            if SentenceBreak.endsSentence(at: shorter - 1, in: words) {
                return shorter
            }
            let longer = start + target + distance
            if distance > 0, SentenceBreak.endsSentence(at: longer - 1, in: words) {
                return longer
            }
        }
        return start + target
    }
}
