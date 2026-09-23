import Foundation
import Testing
@testable import Strobe

/// A trailing-hyphen fragment followed by a joiner (`pre- and post-war`) is a
/// suspended compound, not a line-break hyphenation: the fragment keeps its
/// hyphen and stays its own word.
struct TokenizerSuspendedHyphenTests {

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

    // MARK: - Suspended hyphens

    @Test func keepsSuspendedHyphenBeforeJoiner() {
        #expect(Tokenizer.tokenize("pre- and post-war") == ["pre-", "and", "post-war"])
        #expect(Tokenizer.tokenize("two- or three-day") == ["two-", "or", "three-day"])
        #expect(Tokenizer.tokenize("first- and second-order") == ["first-", "and", "second-order"])
        #expect(Tokenizer.tokenize("mid- to late-1990s") == ["mid-", "to", "late-1990s"])
        #expect(Tokenizer.tokenize("neither pre- nor post-war") == ["neither", "pre-", "nor", "post-war"])
        #expect(Tokenizer.tokenize("pre- and/or post-operative") == ["pre-", "and/or", "post-operative"])
        #expect(Tokenizer.tokenize("19th- and 20th-century") == ["19th-", "and", "20th-century"])
    }

    @Test func keepsSuspendedHyphenWhenCompletionIsUnhyphenated() {
        #expect(Tokenizer.tokenize("pre- and postwar") == ["pre-", "and", "postwar"])
        #expect(Tokenizer.tokenize("over- or underfed") == ["over-", "or", "underfed"])
    }

    @Test func keepsSuspendedHyphenInSeries() {
        #expect(Tokenizer.tokenize("first-, second- and third-order")
                == ["first-,", "second-", "and", "third-order"])
        #expect(Tokenizer.tokenize("two- or three- or four-day")
                == ["two-", "or", "three-", "or", "four-day"])
    }

    @Test func keepsSuspendedHyphenAcrossLineBreak() {
        #expect(Tokenizer.tokenize("pre-\nand post-war") == ["pre-", "and", "post-war"])
        #expect(Tokenizer.tokenize("pre- and\npost-war") == ["pre-", "and", "post-war"])
    }

    @Test func keepsGermanSuspendedHyphen() {
        #expect(Tokenizer.tokenize("Ein- und Ausgang") == ["Ein-", "und", "Ausgang"])
        #expect(Tokenizer.tokenize("ein- oder zweimal") == ["ein-", "oder", "zweimal"])
    }

    @Test func keepsSuspendedHyphenAfterCompoundStem() {
        #expect(Tokenizer.tokenize("late-nineteenth- and early-twentieth-century")
                == ["late-nineteenth-", "and", "early-twentieth-century"])
    }

    @Test func uppercaseSuspendedHyphenStaysSplit() {
        #expect(Tokenizer.tokenize("PRE- AND POST-WAR") == ["PRE-", "AND", "POST-WAR"])
        #expect(Tokenizer.tokenize("Pre- And Post-War") == ["Pre-", "And", "Post-War"])
    }

    // MARK: - Streaming

    @Test func suspendedHyphenSurvivesTokenAtATimeStreaming() {
        #expect(stream(["pre-", "and", "post-war"]) == ["pre-", "and", "post-war"])
        #expect(stream(["mid-", "to", "late-1990s"]) == ["mid-", "to", "late-1990s"])
        #expect(stream(["and post-war"], carry: "pre-") == ["pre-", "and", "post-war"])
        #expect(stream(["pre-"]) == ["pre-"])
    }

    @Test func streamingMatchesWholeTextTokenization() {
        let text = "The pre- and post-war infor-\nmation on two- or three-day, one-in-a-\nlifetime trips."
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        #expect(stream(tokens) == Tokenizer.tokenize(text))
        #expect(Tokenizer.tokenize(text) == [
            "The", "pre-", "and", "post-war", "information", "on", "two-", "or",
            "three-day,", "one-in-a-lifetime", "trips."
        ])
    }

    @Test func epubMarkerMappingSkipsUnmergedSuspendedFragment() {
        let source = """
        <body><p id="a">pre-</p><p id="b">and post-war</p><p id="c">infor-</p><p id="d">mation</p></body>
        """
        let content = EPUBContent.parse(Data(source.utf8))
        var words: [String] = []
        var carry: String?
        let positions = content.appendWords(cleanedText: content.text, into: &words, carry: &carry)
        if let carry { words.append(carry) }
        #expect(words == ["pre-", "and", "post-war", "information"])
        #expect(words == Tokenizer.tokenize(content.text))
        #expect(words[positions[content.anchors["a"]!]!] == "pre-")
        #expect(words[positions[content.anchors["b"]!]!] == "and")
        #expect(words[positions[content.anchors["d"]!]!] == "information")
    }

    // MARK: - Line-break merging

    @Test func lineBreakHyphenationStillMerges() {
        #expect(Tokenizer.tokenize("infor-\nmation and recov-\nery") == ["information", "and", "recovery"])
        #expect(stream(["infor-", "mation"]) == ["information"])
    }

    @Test func wordsStartingWithJoinerLettersStillMerge() {
        #expect(Tokenizer.tokenize("re-\norder") == ["reorder"])
        #expect(Tokenizer.tokenize("al-\ntogether") == ["altogether"])
        #expect(Tokenizer.tokenize("ab-\nnormal") == ["abnormal"])
        #expect(Tokenizer.tokenize("Alex-\nander") == ["Alexander"])
        #expect(Tokenizer.tokenize("mis-\nunderstand") == ["misunderstand"])
    }

    @Test func joinerWithPunctuationStillMerges() {
        #expect(Tokenizer.tokenize("pota-\nto, toma-\nto.") == ["potato,", "tomato."])
        #expect(Tokenizer.tokenize("col-\nor; oper-\nand)") == ["color;", "operand)"])
    }

    @Test func compoundHyphenPreservationIsUnchanged() {
        #expect(Tokenizer.tokenize("one-in-a-\nlifetime") == ["one-in-a-lifetime"])
        #expect(Tokenizer.tokenize("once-in-a-life-\ntime") == ["once-in-a-lifetime"])
        #expect(Tokenizer.tokenize("day-to-\nday") == ["day-to-day"])
        #expect(Tokenizer.tokenize("state-of-the-\nart") == ["state-of-the-art"])
    }
}
