import Testing
import Foundation
@testable import Strobe

struct PassageChunksTests {

    /// `count` words with a sentence ending on each index in `sentenceEnds`:
    /// that word ends in a period and the word after it is capitalized.
    private func filler(_ count: Int, sentenceEndsAt sentenceEnds: Set<Int> = []) -> [String] {
        (0..<count).map { index in
            if sentenceEnds.contains(index) { return "end." }
            if sentenceEnds.contains(index - 1) { return "Then" }
            return "word"
        }
    }

    // MARK: - Empty and short documents

    @Test func emptyDocumentHasNoChunks() {
        let chunks = PassageChunks(words: [])
        #expect(chunks.count == 0)
        #expect(chunks.index(containing: 0) == 0)
        #expect(chunks.index(containing: 42) == 0)
        #expect(chunks.range(at: 0).isEmpty)
    }

    @Test func shortDocumentIsOneChunk() {
        #expect(PassageChunks(words: filler(1)).starts == [0])
        #expect(PassageChunks(words: filler(150), targetSize: 200).range(at: 0) == 0..<150)
        #expect(PassageChunks(words: filler(300), targetSize: 200).range(at: 0) == 0..<300)
    }

    // MARK: - Text without sentence ends

    @Test func textWithoutSentenceEndsBreaksAtTheTarget() {
        let chunks = PassageChunks(words: filler(1000), targetSize: 200)
        #expect(chunks.starts == [0, 200, 400, 600, 800])
        #expect(chunks.range(at: 1) == 200..<400)
        #expect(chunks.range(at: 4) == 800..<1000)
    }

    @Test func shortTailJoinsTheLastChunk() {
        let chunks = PassageChunks(words: filler(1001), targetSize: 200)
        #expect(chunks.starts == [0, 200, 400, 600, 800])
        #expect(chunks.range(at: 4) == 800..<1001)
        #expect(PassageChunks(words: filler(950), targetSize: 200).range(at: 4) == 800..<950)
    }

    // MARK: - Sentence ends

    @Test func chunkEndsAfterTheNearestSentenceEnd() {
        let chunks = PassageChunks(words: filler(100, sentenceEndsAt: [17, 24]), targetSize: 20)
        // 18 words is closer to the target than 25; the chunk after finds no
        // sentence end within 10 words of its target and breaks at 20 words.
        #expect(Array(chunks.starts.prefix(3)) == [0, 18, 38])
    }

    @Test func equallyNearSentenceEndsPickTheShorterChunk() {
        let chunks = PassageChunks(words: filler(100, sentenceEndsAt: [18, 20]), targetSize: 20)
        #expect(chunks.starts[1] == 19)
    }

    @Test func sentenceEndsFarFromTheTargetAreIgnored() {
        let chunks = PassageChunks(words: filler(100, sentenceEndsAt: [5, 40]), targetSize: 20)
        #expect(chunks.starts[1] == 20)
    }

    @Test func abbreviationIsNotASentenceEnd() {
        var words = filler(100, sentenceEndsAt: [22])
        words[19] = "Mr."
        words[20] = "Smith"
        let chunks = PassageChunks(words: words, targetSize: 20)
        #expect(chunks.starts[1] == 23)
    }

    @Test func closingQuoteAfterASentenceEndCounts() {
        var words = filler(100)
        words[19] = "sea.\u{201D}"                  // sea.”
        words[20] = "The"
        let chunks = PassageChunks(words: words, targetSize: 20)
        #expect(chunks.starts[1] == 20)
    }

    @Test func breaksBetweenSentencesInsteadOfMidSentence() throws {
        let words = Tokenizer.tokenize("""
            There is nothing surprising in this. If they but knew it, almost all men in their degree, \
            some time or other, cherish very nearly the same feelings towards the ocean with me. \
            There now is your insular city of the Manhattoes, belted round by wharves as Indian isles \
            by coral reefs—commerce surrounds it with her surf. Right and left, the streets take you \
            waterward. Its extreme downtown is the battery, where that noble mole is washed by waves, \
            and cooled by breezes, which a few hours previous were out of sight of land. Look at the \
            crowds of water-gazers there.
            """)
        // A fixed-size chunk ending on "ocean" would split its sentence.
        let ocean = try #require(words.firstIndex(of: "ocean"))
        let chunks = PassageChunks(words: words, targetSize: ocean + 1)
        #expect(chunks.count > 1)
        #expect(words[chunks.range(at: 0).upperBound - 1] == "me.")
        #expect(words[chunks.range(at: 1).lowerBound] == "There")
    }

    // MARK: - Block starts

    @Test func blockStartsAlwaysStartAChunk() {
        let chunks = PassageChunks(words: filler(60), blockStarts: [7, 9], targetSize: 20)
        #expect(chunks.starts == [0, 7, 9, 29, 49])
    }

    @Test func blockStartsOutsideTheDocumentOrRepeatedAreIgnored() {
        let chunks = PassageChunks(words: filler(40), blockStarts: [0, -3, 12, 12, 40, 99], targetSize: 20)
        #expect(chunks.starts == [0, 12])
    }

    @Test func chapterHeadingIsItsOwnChunk() throws {
        let words = Tokenizer.tokenize(
            "Loomings Call me Ishmael. Some years ago—never mind how long precisely—having little or no money in my purse."
        )
        let chapter = Chapter(title: "Loomings", wordIndex: 0)
        let bodyStart = try #require(ChapterHeading.readingStarts(for: [0: chapter], in: words)[0])
        let chunks = PassageChunks(words: words, blockStarts: [chapter.wordIndex, bodyStart])
        #expect(chunks.range(at: 0) == 0..<1)
        #expect(words[chunks.range(at: 1).lowerBound] == "Call")
    }

    // MARK: - Lookup

    @Test func indexFindsTheChunkHoldingAWord() {
        let chunks = PassageChunks(words: filler(100, sentenceEndsAt: [17]), targetSize: 20)
        #expect(chunks.index(containing: 0) == 0)
        #expect(chunks.index(containing: 17) == 0)
        #expect(chunks.index(containing: 18) == 1)
        #expect(chunks.index(containing: 37) == 1)
        #expect(chunks.index(containing: 38) == 2)
    }

    @Test func indexClampsWordsOutsideTheDocument() {
        let chunks = PassageChunks(words: filler(1000), targetSize: 200)
        #expect(chunks.index(containing: -5) == 0)
        #expect(chunks.index(containing: 5000) == 4)
    }

    @Test func chunkIndexOutsideTheDocumentHasAnEmptyRange() {
        let chunks = PassageChunks(words: filler(500), targetSize: 200)
        #expect(chunks.range(at: -1).isEmpty)
        #expect(chunks.range(at: chunks.count) == 500..<500)
        #expect(chunks.range(at: 10).isEmpty)
    }

    @Test func chunksCoverEveryWordOnceAndEndAtBreaks() {
        let sentenceEnds = Set(stride(from: 7, to: 500, by: 23))
        let words = filler(500, sentenceEndsAt: sentenceEnds)
        let blockStarts = [120, 123, 300]
        let chunks = PassageChunks(words: words, blockStarts: blockStarts, targetSize: 40)

        var next = 0
        for index in 0..<chunks.count {
            let range = chunks.range(at: index)
            #expect(range.lowerBound == next)
            #expect(!range.isEmpty)
            next = range.upperBound
            // Each chunk ends at a block start, the document's end, a sentence
            // end, or, with none near, exactly at the target length.
            let endsAtBlock = range.upperBound == words.count || blockStarts.contains(range.upperBound)
            let endsSentence = SentenceBreak.endsSentence(at: range.upperBound - 1, in: words)
            #expect(endsAtBlock || endsSentence || range.count == 40)
        }
        #expect(next == words.count)
        for word in words.indices {
            #expect(chunks.range(at: chunks.index(containing: word)).contains(word))
        }
    }
}
