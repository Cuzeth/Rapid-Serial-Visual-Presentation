import Foundation
import Testing
@testable import Strobe

/// Dashes that join two words without spaces are word boundaries; the dash
/// stays on the preceding word.
struct TokenizerDashTests {

    /// Streams chunks through `appendTokenizedText` and flushes the final carry.
    private func stream(_ chunks: [String], carry initial: String? = nil) -> [String] {
        var output: [String] = []
        var carry = initial
        for chunk in chunks {
            Tokenizer.appendTokenizedText(chunk, into: &output, carry: &carry)
        }
        if let carry, !carry.isEmpty {
            output.append(carry)
        }
        return output
    }

    // MARK: - Em dash and horizontal bar

    @Test func splitsEmDashJoinedWords() {
        #expect(Tokenizer.tokenize("fantastical elements—stone, oarsmen, etc")
                == ["fantastical", "elements—", "stone,", "oarsmen,", "etc"])
        #expect(Tokenizer.tokenize("stop—go") == ["stop—", "go"])
        #expect(Tokenizer.tokenize("a—b—c") == ["a—", "b—", "c"])
        #expect(Tokenizer.tokenize("the man—tall, thin—entered") == ["the", "man—", "tall,", "thin—", "entered"])
        #expect(Tokenizer.tokenize("Paris—London") == ["Paris—", "London"])
        #expect(Tokenizer.tokenize("1914—1918") == ["1914—", "1918"])
    }

    @Test func keepsPunctuationBeforeTheDashOnTheFirstWord() {
        #expect(Tokenizer.tokenize("what?—no") == ["what?—", "no"])
        #expect(Tokenizer.tokenize("word...—word") == ["word...—", "word"])
    }

    @Test func splitsEmDashBesideHyphenatedCompounds() {
        #expect(Tokenizer.tokenize("well-known—and wedge-shaped—thing")
                == ["well-known—", "and", "wedge-shaped—", "thing"])
    }

    @Test func splitsEmDashBetweenNonLatinWords() {
        #expect(Tokenizer.tokenize("привет—мир مرحبا—بالعالم") == ["привет—", "мир", "مرحبا—", "بالعالم"])
    }

    @Test func splitsAtHorizontalBar() {
        #expect(Tokenizer.tokenize("stop\u{2015}go") == ["stop\u{2015}", "go"])
        #expect(Tokenizer.tokenize("\u{2015}Hello there") == ["\u{2015}Hello", "there"])
    }

    // MARK: - ASCII hyphens

    @Test func splitsAtDoubleAndTripleHyphen() {
        #expect(Tokenizer.tokenize("word--word") == ["word--", "word"])
        #expect(Tokenizer.tokenize("word---word") == ["word---", "word"])
        #expect(Tokenizer.tokenize("elements--stone, oarsmen") == ["elements--", "stone,", "oarsmen"])
    }

    @Test func singleHyphenNeverSplits() {
        #expect(Tokenizer.tokenize("wedge-shaped") == ["wedge-shaped"])
        #expect(Tokenizer.tokenize("one-in-a-lifetime mother-in-law") == ["one-in-a-lifetime", "mother-in-law"])
        #expect(Tokenizer.tokenize("-5 10-20 555-1234") == ["-5", "10-20", "555-1234"])
    }

    @Test func trailingDoubleHyphenIsNotALineBreakHyphen() {
        #expect(Tokenizer.tokenize("wait-- he said") == ["wait--", "he", "said"])
        #expect(Tokenizer.tokenize("wait--\nhe said") == ["wait--", "he", "said"])
        #expect(Tokenizer.tokenize("infor-\nmation-- next") == ["information--", "next"])
    }

    @Test func leadingAndTrailingDoubleHyphenStayAttached() {
        #expect(Tokenizer.tokenize("--verbose flag") == ["--verbose", "flag"])
        #expect(Tokenizer.tokenize("i--; next") == ["i--;", "next"])
        #expect(Tokenizer.tokenize("word -- word") == ["word--", "word"])
    }

    // MARK: - En dash and elision dashes

    @Test func singleEnDashNeverSplits() {
        #expect(Tokenizer.tokenize("1990–1995") == ["1990–1995"])
        #expect(Tokenizer.tokenize("pp. 12–15") == ["pp.", "12–15"])
        #expect(Tokenizer.tokenize("Bose–Einstein London–Paris") == ["Bose–Einstein", "London–Paris"])
        #expect(Tokenizer.tokenize("word– next") == ["word–", "next"])
    }

    @Test func spacedOrDoubledEnDashSeparatesWords() {
        #expect(Tokenizer.tokenize("word – word") == ["word–", "word"])
        #expect(Tokenizer.tokenize("word––word") == ["word––", "word"])
    }

    @Test func twoEmDashElisionStaysWhole() {
        #expect(Tokenizer.tokenize("d\u{2E3A}d Mr. B\u{2E3A}") == ["d\u{2E3A}d", "Mr.", "B\u{2E3A}"])
    }

    // MARK: - Leading and trailing dashes

    @Test func leadingDashStaysOnItsWord() {
        #expect(Tokenizer.tokenize("—Hello there") == ["—Hello", "there"])
        #expect(Tokenizer.tokenize("—Hello—said John") == ["—Hello—", "said", "John"])
        #expect(Tokenizer.tokenize("\"—and then") == ["\"—and", "then"])
        #expect(Tokenizer.tokenize("word —word") == ["word", "—word"])
        #expect(Tokenizer.tokenize("said.\n—Hello") == ["said.", "—Hello"])
    }

    @Test func trailingDashStaysOnItsWord() {
        #expect(Tokenizer.tokenize("wait—") == ["wait—"])
        #expect(Tokenizer.tokenize("wait— what") == ["wait—", "what"])
        #expect(Tokenizer.tokenize("\"wait—\" she said") == ["\"wait—\"", "she", "said"])
        #expect(Tokenizer.tokenize("“wait—” she said") == ["“wait—”", "she", "said"])
        #expect(Tokenizer.tokenize("wait—, then") == ["wait—,", "then"])
        #expect(Tokenizer.tokenize("(—aside—)") == ["(—aside—)"])
    }

    // MARK: - Quotes and brackets around a dash

    @Test func narrationInterruptingDialogueSplitsAfterTheDash() {
        #expect(Tokenizer.tokenize("“When I was young”—he paused—“things changed.”")
                == ["“When", "I", "was", "young”—", "he", "paused—", "“things", "changed.”"])
        #expect(Tokenizer.tokenize("\"When I was young\"--he paused--\"things changed.\"")
                == ["\"When", "I", "was", "young\"--", "he", "paused--", "\"things", "changed.\""])
    }

    @Test func openingMarkAfterDashStartsTheNextWord() {
        #expect(Tokenizer.tokenize("said—\"Hello\"") == ["said—", "\"Hello\""])
        #expect(Tokenizer.tokenize("said—“Hello”") == ["said—", "“Hello”"])
        #expect(Tokenizer.tokenize("word—'tis word—’tis") == ["word—", "'tis", "word—", "’tis"])
    }

    @Test func closingMarkAfterDashStaysWithTheDash() {
        #expect(Tokenizer.tokenize("thought—”—she stopped") == ["thought—”—", "she", "stopped"])
        #expect(Tokenizer.tokenize("thought—\"—she stopped") == ["thought—\"—", "she", "stopped"])
        #expect(Tokenizer.tokenize("(wait—)—then") == ["(wait—)—", "then"])
    }

    // MARK: - Repeated and standalone dashes

    @Test func repeatedAndMixedDashRunsSplitOnce() {
        #expect(Tokenizer.tokenize("word——word") == ["word——", "word"])
        #expect(Tokenizer.tokenize("word—-word word-—word") == ["word—-", "word", "word-—", "word"])
    }

    @Test func dashRunEndingInHyphenIsNeverCarried() {
        #expect(Tokenizer.tokenize("word—- next") == ["word—-", "next"])
        #expect(Tokenizer.tokenize("thought—”-she b-”—)-abé") == ["thought—”-", "she", "b-”—)-", "abé"])
    }

    @Test func standaloneDashesStillAttachToPreviousWord() {
        #expect(Tokenizer.tokenize("word — word") == ["word—", "word"])
        #expect(Tokenizer.tokenize("end\n-----\nnext") == ["end-----", "next"])
        #expect(Tokenizer.tokenize("— Hello") == ["Hello"])
    }

    // MARK: - Line-break hyphen carry

    @Test func carriedFragmentMergesIntoFirstDashPiece() {
        #expect(Tokenizer.tokenize("infor-\nmation—stone") == ["information—", "stone"])
        #expect(Tokenizer.tokenize("one-in-a-\nlifetime—chance") == ["one-in-a-lifetime—", "chance"])
    }

    @Test func lastDashPieceCanStillCarry() {
        #expect(Tokenizer.tokenize("a—infor-\nmation") == ["a—", "information"])
        #expect(Tokenizer.tokenize("a—b-\nc") == ["a—", "bc"])
    }

    @Test func carriedFragmentDoesNotMergeAcrossLeadingDashOrCapital() {
        #expect(Tokenizer.tokenize("well-\n—known") == ["well-", "—known"])
        #expect(Tokenizer.tokenize("infor-\nStone—age") == ["infor-", "Stone—", "age"])
    }

    // MARK: - CJK and mixed script

    // How NLTokenizer segments the CJK runs is not what's under test here.

    @Test func cjkDashAttachesToPrecedingCJKWord() {
        let words = Tokenizer.tokenize("我们——他们")
        #expect(words.joined() == "我们——他们")
        #expect(words.contains(where: { $0.hasSuffix("——") }))
        #expect(!words.contains(where: { $0.hasPrefix("—") }))
    }

    @Test func dashBetweenLatinAndCJK() {
        let latinFirst = Tokenizer.tokenize("Swift—它很快")
        #expect(latinFirst.first == "Swift—")
        #expect(latinFirst.dropFirst().joined() == "它很快")

        let cjkFirst = Tokenizer.tokenize("重点—Swift rocks")
        #expect(cjkFirst.suffix(2) == ["—Swift", "rocks"])
        #expect(cjkFirst.dropLast(2).joined() == "重点")
    }

    @Test func dashesSplitOnBothSidesOfACJKRun() {
        let words = Tokenizer.tokenize("fast—stone中文word—end")
        #expect(words.prefix(2) == ["fast—", "stone"])
        #expect(words.suffix(2) == ["word—", "end"])
        #expect(words.joined() == "fast—stone中文word—end")
    }

    // MARK: - Streaming

    @Test func chunkBoundaryAtADashActsLikeWhitespace() {
        #expect(stream(["some elements—", "stone, etc"]) == ["some", "elements—", "stone,", "etc"])
        #expect(stream(["some elements", "—stone, etc"]) == ["some", "elements", "—stone,", "etc"])
        #expect(stream(["elements", "—", "stone"]) == ["elements—", "stone"])
        #expect(stream(["elements--", "stone"]) == ["elements--", "stone"])
    }

    @Test func carryCrossesChunksIntoDashedToken() {
        #expect(stream(["infor-", "mation—stone"]) == ["information—", "stone"])
        #expect(stream(["— word"], carry: "infor-") == ["infor-—", "word"])
    }

    @Test func perTokenStreamingMatchesWholeTextTokenization() {
        let text = """
        infor- mation and one-in-a- lifetime he llo 中文测试 & more. fantastical elements—stone, oarsmen--etc \
        “young”—he paused—“things” thought—”—she 1990–1995 wait— —Hello unmerged-
        """
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        #expect(stream(tokens) == Tokenizer.tokenize(text))
    }

    // MARK: - EPUB marker mapping

    @Test func epubMarkersMapToFirstPieceOfDashedToken() {
        let source = """
        <body><p id="a">infor-</p><p id="b">mation—stone, oars<span id="mid"/>men--etc and one-in-a-</p>
        <p id="c">lifetime—chance</p><p id="dashOnly">—</p><p id="lead">—Hello—said John</p>
        <p>trailing—</p><h2 id="e">Chapter—two</h2><p id="f">elements—<a id="after"/>stone</p></body>
        """
        let content = EPUBContent.parse(Data(source.utf8))
        var words: [String] = []
        var carry: String?
        let positions = content.appendWords(cleanedText: content.text, into: &words, carry: &carry)
        if let carry { words.append(carry) }

        func word(at anchor: String) -> String? {
            guard let offset = content.anchors[anchor], let index = positions[offset] else { return nil }
            return words[index]
        }

        #expect(words == Tokenizer.tokenize(content.text))
        #expect(word(at: "a") == "information—")
        #expect(word(at: "b") == "information—")
        #expect(word(at: "mid") == "oarsmen--")
        #expect(word(at: "c") == "one-in-a-lifetime—")
        #expect(word(at: "dashOnly") == "—Hello—")
        #expect(word(at: "lead") == "—Hello—")
        #expect(word(at: "e") == "Chapter—")
        #expect(word(at: "f") == "elements—")
        #expect(word(at: "after") == "elements—")
        #expect(content.headings.map(\.title) == ["Chapter—two"])
    }
}
