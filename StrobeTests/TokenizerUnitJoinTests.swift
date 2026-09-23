import Foundation
import NaturalLanguage
import Testing
@testable import Strobe

/// A year and its era designator, or a 12-hour clock time and its meridiem,
/// display as one word joined by a plain space.
struct TokenizerUnitJoinTests {

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

    // MARK: - Era after a year

    @Test func joinsYearAndEra() {
        #expect(Tokenizer.tokenize("built in 2000 BCE by") == ["built", "in", "2000 BCE", "by"])
        #expect(Tokenizer.tokenize("in 44 BC he") == ["in", "44 BC", "he"])
        #expect(Tokenizer.tokenize("until 476 CE when") == ["until", "476 CE", "when"])
        #expect(Tokenizer.tokenize("in 79 AD the") == ["in", "79 AD", "the"])
        #expect(Tokenizer.tokenize("in 1445 AH the") == ["in", "1445 AH", "the"])
        #expect(Tokenizer.tokenize("in 5 BC a") == ["in", "5 BC", "a"])
    }

    @Test func joinsGroupedAndPluralYears() {
        #expect(Tokenizer.tokenize("around 10,000 BCE people") == ["around", "10,000 BCE", "people"])
        #expect(Tokenizer.tokenize("around 10000 BCE people") == ["around", "10000 BCE", "people"])
        #expect(Tokenizer.tokenize("about 250,000 BCE") == ["about", "250,000 BCE"])
        #expect(Tokenizer.tokenize("in the 400s BCE the") == ["in", "the", "400s BCE", "the"])
    }

    @Test func joinsDottedEras() {
        #expect(Tokenizer.tokenize("in 44 B.C. he") == ["in", "44 B.C.", "he"])
        #expect(Tokenizer.tokenize("in 2000 B.C.E. they") == ["in", "2000 B.C.E.", "they"])
        #expect(Tokenizer.tokenize("in 79 A.D. the") == ["in", "79 A.D.", "the"])
        #expect(Tokenizer.tokenize("in 476 C.E. the") == ["in", "476 C.E.", "the"])
        #expect(Tokenizer.tokenize("in 622 A.H. the") == ["in", "622 A.H.", "the"])
        #expect(Tokenizer.tokenize("in 44 B.C., he") == ["in", "44 B.C.,", "he"])
    }

    /// Small caps often reach the text in lowercase. `ad`, `ah`, and `ce` are
    /// words and `bc` is shorthand for "because", so of the undotted forms
    /// only `bce` joins in lowercase.
    @Test func joinsLowercaseErasThatAreNotWords() {
        #expect(Tokenizer.tokenize("in 2000 bce they") == ["in", "2000 bce", "they"])
        #expect(Tokenizer.tokenize("in 44 b.c. he") == ["in", "44 b.c.", "he"])
        #expect(Tokenizer.tokenize("in 79 a.d. and 3 c.e.") == ["in", "79 a.d.", "and", "3 c.e."])
        #expect(Tokenizer.tokenize("Apple's 1984 ad was") == ["Apple's", "1984", "ad", "was"])
        #expect(Tokenizer.tokenize("the 30 ad slots") == ["the", "30", "ad", "slots"])
        #expect(Tokenizer.tokenize("en 2000 ce fut") == ["en", "2000", "ce", "fut"])
        #expect(Tokenizer.tokenize("rated it 4 bc the ending") == ["rated", "it", "4", "bc", "the", "ending"])
        #expect(Tokenizer.tokenize("in 2000 Bce and 79 Ad") == ["in", "2000", "Bce", "and", "79", "Ad"])
    }

    // MARK: - Punctuation around a unit

    @Test func unitKeepsSurroundingPunctuation() {
        #expect(Tokenizer.tokenize("in 2000 BCE, the") == ["in", "2000 BCE,", "the"])
        #expect(Tokenizer.tokenize("died in 44 BC. Then") == ["died", "in", "44 BC.", "Then"])
        #expect(Tokenizer.tokenize("(2000 BCE) was") == ["(2000 BCE)", "was"])
        #expect(Tokenizer.tokenize("“in 2000 BCE”") == ["“in", "2000 BCE”"])
        #expect(Tokenizer.tokenize("«2000 BCE» and [2000 BCE]") == ["«2000 BCE»", "and", "[2000 BCE]"])
        #expect(Tokenizer.tokenize("was it 44 BC? or 45 BC; who") == ["was", "it", "44 BC?", "or", "45 BC;", "who"])
        #expect(Tokenizer.tokenize("~2000 BCE") == ["~2000 BCE"])
        #expect(Tokenizer.tokenize("2000 BCE , then") == ["2000 BCE,", "then"])
    }

    @Test func circaStaysItsOwnWord() {
        #expect(Tokenizer.tokenize("(c. 2000 BCE), and") == ["(c.", "2000 BCE),", "and"])
        #expect(Tokenizer.tokenize("c.2000 BCE") == ["c.2000", "BCE"])
    }

    /// Punctuation after the first half ends a clause or sentence; the
    /// designator after it belongs to what follows.
    @Test func nothingJoinsAcrossPunctuationAfterTheFirstHalf() {
        #expect(Tokenizer.tokenize("It ended in 2000. BC Hydro said so.")
                == ["It", "ended", "in", "2000.", "BC", "Hydro", "said", "so."])
        #expect(Tokenizer.tokenize("In 2000, AD spending rose") == ["In", "2000,", "AD", "spending", "rose"])
        #expect(Tokenizer.tokenize("(in 2000) BC Hydro") == ["(in", "2000)", "BC", "Hydro"])
        #expect(Tokenizer.tokenize("in “2000” BCE") == ["in", "“2000”", "BCE"])
        #expect(Tokenizer.tokenize("2000 (BCE) and 2000 [BC]") == ["2000", "(BCE)", "and", "2000", "[BC]"])
        #expect(Tokenizer.tokenize("at 10: PM") == ["at", "10:", "PM"])
    }

    /// A currency or number sign makes the numeral an amount, and `%` makes
    /// it a share.
    @Test func amountsAndPercentagesStayApart() {
        #expect(Tokenizer.tokenize("a $2000 BC Hydro rebate") == ["a", "$2000", "BC", "Hydro", "rebate"])
        #expect(Tokenizer.tokenize("£5 PM and #2000 BCE") == ["£5", "PM", "and", "#2000", "BCE"])
        #expect(Tokenizer.tokenize("AD 50% higher") == ["AD", "50%", "higher"])
    }

    // MARK: - Ranges

    @Test func joinsYearRangeAndEra() {
        #expect(Tokenizer.tokenize("from 2000–1500 BCE the") == ["from", "2000–1500 BCE", "the"])
        #expect(Tokenizer.tokenize("from 2000-1500 BCE the") == ["from", "2000-1500 BCE", "the"])
        #expect(Tokenizer.tokenize("(12,000–10,000 BCE)") == ["(12,000–10,000 BCE)"])
        #expect(Tokenizer.tokenize("1–2–3 BC") == ["1–2–3", "BC"])
    }

    @Test func enDashBetweenTwoUnitsSeparatesThem() {
        #expect(Tokenizer.tokenize("(27 BCE–14 CE)") == ["(27 BCE–", "14 CE)"])
        #expect(Tokenizer.tokenize("27 BC–AD 14") == ["27 BC–", "AD 14"])
        #expect(Tokenizer.tokenize("27 B.C.–A.D. 14") == ["27 B.C.–", "A.D. 14"])
        #expect(Tokenizer.tokenize("27 BCE – 14 CE") == ["27 BCE–", "14 CE"])
        #expect(Tokenizer.tokenize("27 BCE—14 CE") == ["27 BCE—", "14 CE"])
        #expect(Tokenizer.tokenize("9 AM–5 PM") == ["9 AM–", "5 PM"])
        #expect(Tokenizer.tokenize("2000 BCE–style pottery") == ["2000", "BCE–style", "pottery"])
    }

    /// A hyphen after a designator belongs to a name: `AH-64` is a helicopter.
    @Test func hyphenAfterADesignatorKeepsTheTokenWhole() {
        #expect(Tokenizer.tokenize("In 1984 AH-64 Apaches") == ["In", "1984", "AH-64", "Apaches"])
        #expect(Tokenizer.tokenize("27 BCE-14 CE") == ["27", "BCE-14", "CE"])
        #expect(Tokenizer.tokenize("in 2000 BC-era") == ["in", "2000", "BC-era"])
    }

    // MARK: - Era before a year

    @Test func joinsLeadingEraAndYear() {
        #expect(Tokenizer.tokenize("in AD 79 Vesuvius") == ["in", "AD 79", "Vesuvius"])
        #expect(Tokenizer.tokenize("in A.D. 79 Vesuvius") == ["in", "A.D. 79", "Vesuvius"])
        #expect(Tokenizer.tokenize("in AH 1445 the") == ["in", "AH 1445", "the"])
        #expect(Tokenizer.tokenize("(AD 79), when AD 79. Then") == ["(AD 79),", "when", "AD 79.", "Then"])
        #expect(Tokenizer.tokenize("reigned AD 14–37 in") == ["reigned", "AD 14–37", "in"])
    }

    @Test func onlyAnnoDesignatorsLead() {
        #expect(Tokenizer.tokenize("CE 79 marks") == ["CE", "79", "marks"])
        #expect(Tokenizer.tokenize("BC 44 was") == ["BC", "44", "was"])
        #expect(Tokenizer.tokenize("an ad 30 seconds long") == ["an", "ad", "30", "seconds", "long"])
        #expect(Tokenizer.tokenize("AD, 79 people") == ["AD,", "79", "people"])
        #expect(Tokenizer.tokenize("AD agency") == ["AD", "agency"])
    }

    @Test func unitsNeverChain() {
        #expect(Tokenizer.tokenize("in 2000 AD 79 people") == ["in", "2000 AD", "79", "people"])
        #expect(Tokenizer.tokenize("2000 BCE BCE") == ["2000 BCE", "BCE"])
        #expect(Tokenizer.tokenize("44 BC AD 14") == ["44 BC", "AD 14"])
        #expect(Tokenizer.tokenize("44 BC 44 BC") == ["44 BC", "44 BC"])
    }

    // MARK: - Clock times

    @Test func joinsClockTimeAndMeridiem() {
        #expect(Tokenizer.tokenize("at 10 AM we") == ["at", "10 AM", "we"])
        #expect(Tokenizer.tokenize("at 5 p.m. we") == ["at", "5 p.m.", "we"])
        #expect(Tokenizer.tokenize("at 10:30 PM we") == ["at", "10:30 PM", "we"])
        #expect(Tokenizer.tokenize("at 9.05 p.m. sharp") == ["at", "9.05 p.m.", "sharp"])
        #expect(Tokenizer.tokenize("at 12 A.M. and 12 P.M.") == ["at", "12 A.M.", "and", "12 P.M."])
        #expect(Tokenizer.tokenize("at 09:00 AM we") == ["at", "09:00 AM", "we"])
        #expect(Tokenizer.tokenize("(10:30 PM), then") == ["(10:30 PM),", "then"])
        #expect(Tokenizer.tokenize("up at 5:30 A.M., put") == ["up", "at", "5:30 A.M.,", "put"])
    }

    /// `am` is a word (`I am`, German `am`), so undotted lowercase meridiems
    /// don't join, and `pm` stays apart with it.
    @Test func undottedLowercaseMeridiemsStayApart() {
        #expect(Tokenizer.tokenize("from 9 am to 5 pm daily") == ["from", "9", "am", "to", "5", "pm", "daily"])
        #expect(Tokenizer.tokenize("die 5 am häufigsten") == ["die", "5", "am", "häufigsten"])
        #expect(Tokenizer.tokenize("um 8 am Abend") == ["um", "8", "am", "Abend"])
        #expect(Tokenizer.tokenize("I am 12 and I am here") == ["I", "am", "12", "and", "I", "am", "here"])
    }

    /// `PM` after a year is a prime minister, not a time.
    @Test func meridiemNeedsATwelveHourClockTime() {
        #expect(Tokenizer.tokenize("In 2010 PM Cameron said") == ["In", "2010", "PM", "Cameron", "said"])
        #expect(Tokenizer.tokenize("at 13 PM and 0 AM") == ["at", "13", "PM", "and", "0", "AM"])
        #expect(Tokenizer.tokenize("at 10:75 PM and 10:3 PM") == ["at", "10:75", "PM", "and", "10:3", "PM"])
        #expect(Tokenizer.tokenize("at 10:30:15 PM we") == ["at", "10:30:15", "PM", "we"])
        #expect(Tokenizer.tokenize("at 10 Am and 5 pM") == ["at", "10", "Am", "and", "5", "pM"])
        #expect(Tokenizer.tokenize("on 1010 AM radio") == ["on", "1010", "AM", "radio"])
        #expect(Tokenizer.tokenize("in 10:30 BC we") == ["in", "10:30", "BC", "we"])
    }

    // MARK: - Not units

    @Test func onlyBareNumeralsOpenAUnit() {
        #expect(Tokenizer.tokenize("Vitamin B12 BC labs") == ["Vitamin", "B12", "BC", "labs"])
        #expect(Tokenizer.tokenize("5th BCE and 1st AD") == ["5th", "BCE", "and", "1st", "AD"])
        #expect(Tokenizer.tokenize("about 3.5 BC") == ["about", "3.5", "BC"])
        #expect(Tokenizer.tokenize("1,00 BC and 1,,000 BC") == ["1,00", "BC", "and", "1,,000", "BC"])
        #expect(Tokenizer.tokenize("2000/1999 BC") == ["2000/1999", "BC"])
        #expect(Tokenizer.tokenize("2000¹ BCE and 2000 BCE¹") == ["2000¹", "BCE", "and", "2000", "BCE¹"])
        #expect(Tokenizer.tokenize("٢٠٠٠ BCE") == ["٢٠٠٠", "BCE"])
    }

    @Test func otherAcronymsWordsAndLabelsStayApart() {
        #expect(Tokenizer.tokenize("In 2010 BP spilled") == ["In", "2010", "BP", "spilled"])
        #expect(Tokenizer.tokenize("In 1999 NATO and 12 UN") == ["In", "1999", "NATO", "and", "12", "UN"])
        #expect(Tokenizer.tokenize("44 BCs and 2000 BCE-era") == ["44", "BCs", "and", "2000", "BCE-era"])
        #expect(Tokenizer.tokenize("44 BC's end") == ["44", "BC's", "end"])
        #expect(Tokenizer.tokenize("44 B. C.") == ["44", "B.", "C."])
        #expect(Tokenizer.tokenize("the 5th century BCE") == ["the", "5th", "century", "BCE"])
        #expect(Tokenizer.tokenize("5 km 20 °C No. 5 p. 12 Fig. 3 Chapter 1")
                == ["5", "km", "20", "°C", "No.", "5", "p.", "12", "Fig.", "3", "Chapter", "1"])
    }

    /// Six digits at most: longer numbers are counts, not dates.
    @Test func longNumbersStayApart() {
        #expect(Tokenizer.tokenize("999,999 BC") == ["999,999 BC"])
        #expect(Tokenizer.tokenize("1,000,000 BC") == ["1,000,000", "BC"])
        #expect(Tokenizer.tokenize("1234567 BCE") == ["1234567", "BCE"])
        #expect(Tokenizer.tokenize("99999999999999999999999 PM") == ["99999999999999999999999", "PM"])
        #expect(Tokenizer.tokenize("AD 99999999999999999999999") == ["AD", "99999999999999999999999"])
    }

    // MARK: - Dashes and line-break hyphens

    @Test func dashAfterAUnitStillSplits() {
        #expect(Tokenizer.tokenize("2000 BCE—when") == ["2000 BCE—", "when"])
        #expect(Tokenizer.tokenize("2000 BCE--when") == ["2000 BCE--", "when"])
        #expect(Tokenizer.tokenize("long ago—2000 BCE to") == ["long", "ago—", "2000 BCE", "to"])
        #expect(Tokenizer.tokenize("1500—2000 BCE") == ["1500—", "2000 BCE"])
        #expect(Tokenizer.tokenize("at 5 PM—sharp") == ["at", "5 PM—", "sharp"])
        #expect(Tokenizer.tokenize("“in 44 BC—”") == ["“in", "44 BC—”"])
        #expect(Tokenizer.tokenize("2000—BCE") == ["2000—", "BCE"])
    }

    @Test func lineBreakHyphenCarryIsUnaffected() {
        #expect(Tokenizer.tokenize("in 2000 BCE infor-\nmation") == ["in", "2000 BCE", "information"])
        #expect(Tokenizer.tokenize("unmerged- 2000 BCE") == ["unmerged-", "2000 BCE"])
        #expect(Tokenizer.tokenize("2000 exam- BCE") == ["2000", "exam-", "BCE"])
        #expect(stream(["2000 BCE"], carry: "infor-") == ["infor-", "2000 BCE"])
    }

    // MARK: - Whitespace, CJK, and mixed script

    @Test func anyWhitespaceBetweenTheHalvesBecomesAPlainSpace() {
        #expect(Tokenizer.tokenize("2000\u{00A0}BCE") == ["2000 BCE"])
        #expect(Tokenizer.tokenize("2000\u{202F}BCE") == ["2000 BCE"])
        #expect(Tokenizer.tokenize("10\u{2009}AM") == ["10 AM"])
        #expect(Tokenizer.tokenize("2000\nBCE") == ["2000 BCE"])
        #expect(Tokenizer.tokenize("2000   BCE") == ["2000 BCE"])
        #expect(Tokenizer.tokenize("20\u{00AD}00 BCE") == ["2000 BCE"])
    }

    @Test func unitsJoinBesideOtherScripts() {
        #expect(Tokenizer.tokenize("في عام 622 CE كان") == ["في", "عام", "622 CE", "كان"])
        #expect(Tokenizer.tokenize("公元前 2000 BCE 的")
                == Tokenizer.tokenize("公元前") + ["2000 BCE"] + Tokenizer.tokenize("的"))
        #expect(Tokenizer.tokenize("2000 BCE中文") == ["2000 BCE"] + Tokenizer.tokenize("中文"))
    }

    @Test func cjkBetweenTheHalvesBlocksTheJoin() {
        #expect(Tokenizer.tokenize("2000 中文 BCE") == ["2000"] + Tokenizer.tokenize("中文") + ["BCE"])
        #expect(!Tokenizer.tokenize("2000年 BCE").contains { $0.contains(" ") })
        #expect(!Tokenizer.tokenize("2000 。 BCE").contains { $0.contains(" ") })
        #expect(!Tokenizer.tokenize("２０００ BCE").contains { $0.contains(" ") })
    }

    // MARK: - Streaming

    @Test func unitJoinsAcrossChunks() {
        #expect(stream(["built in 2000", "BCE by them"]) == ["built", "in", "2000 BCE", "by", "them"])
        #expect(stream(["built in 2000 \n", "\n BCE by them"]) == ["built", "in", "2000 BCE", "by", "them"])
        #expect(stream(["in AD", "79 Vesuvius"]) == ["in", "AD 79", "Vesuvius"])
        #expect(stream(["at 10:30", "p.m. we"]) == ["at", "10:30 p.m.", "we"])
        #expect(stream(["in 2000", "", "  ", "BCE"]) == ["in", "2000 BCE"])
        #expect(stream(["(27", "BCE–14", "CE)"]) == ["(27 BCE–", "14 CE)"])
    }

    @Test func chunkBoundaryDoesNotBypassTheRules() {
        #expect(stream(["ended in 2000.", "BC Hydro"]) == ["ended", "in", "2000.", "BC", "Hydro"])
        #expect(stream(["in 2000", ",", "BCE"]) == ["in", "2000,", "BCE"])
        #expect(stream(["in 2000", "中", "BCE"]) == ["in", "2000", "中", "BCE"])
    }

    @Test func perTokenStreamingMatchesWholeTextTokenization() {
        let text = """
        Augustus ruled from 27 BC to AD 14 (27 BCE–14 CE); Vesuvius erupted in A.D. 79 at about \
        1 p.m.—or 10:30 AM? It ended in 2000. BC Hydro, 2000–1500 BCE, infor-\nmation 中文 622 CE。
        """
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        #expect(stream(tokens) == Tokenizer.tokenize(text))
    }

    // MARK: - EPUB marker mapping

    @Test func epubMarkersOnEitherHalfMapToTheUnit() {
        let source = """
        <body><h2 id="h">The year 44 BC</h2><p>Built in <span id="year">2000</span> \
        <span id="era">bce</span> <span id="next">by</span> them at <a id="clock"/>10:30&#160;<span id="pm">p.m.</span> \
        in <span id="lead">AD</span> <span id="n">79</span>, (27 <span id="range">BCE–14</span> CE).</p></body>
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
        #expect(word(at: "year") == "2000 bce")
        #expect(word(at: "era") == "2000 bce")
        #expect(word(at: "next") == "by")
        #expect(word(at: "clock") == "10:30 p.m.")
        #expect(word(at: "pm") == "10:30 p.m.")
        #expect(word(at: "lead") == "AD 79,")
        #expect(word(at: "n") == "AD 79,")
        #expect(word(at: "range") == "14 CE).")
        #expect(content.headings.map(\.title) == ["The year 44 BC"])
        #expect(content.headings.first.flatMap { positions[$0.offset] }.map { words[$0] } == "The")
    }

    /// A heading, paragraph, or spine file starts a new block, and a unit
    /// never joins across the start of one.
    @Test func epubUnitsNeverJoinAcrossBlocks() {
        let first = EPUBContent.parse(Data("""
        <body><h1>Chapter 3</h1><p>AD 79 was the year, at 5 <span id='pm'>PM</span> sharp.</p>\
        <p>It ended in <span id='year'>1500</span></p></body>
        """.utf8))
        let second = EPUBContent.parse(Data("<body><p><span id='era'>BCE</span> <span id='after'>after</span> it.</p></body>".utf8))
        var words: [String] = []
        var carry: String?
        let firstPositions = first.appendWords(cleanedText: first.text, into: &words, carry: &carry)
        let secondPositions = second.appendWords(cleanedText: second.text, into: &words, carry: &carry)

        #expect(words == [
            "Chapter", "3", "AD 79", "was", "the", "year,", "at", "5 PM", "sharp.",
            "It", "ended", "in", "1500", "BCE", "after", "it."
        ])
        #expect(first.headings.first.flatMap { firstPositions[$0.offset] } == 0)
        #expect(firstPositions[first.anchors["pm"]!] == 7)
        #expect(firstPositions[first.anchors["year"]!] == 12)
        #expect(secondPositions[0] == 13)
        #expect(secondPositions[second.anchors["era"]!] == 13)
        #expect(secondPositions[second.anchors["after"]!] == 14)
    }

    @Test func blockStartKeepsTheFirstWordApart() {
        var words = ["in", "2000"]
        var carry: String?
        Tokenizer.appendTokenizedText("BCE after 44 BC", into: &words, carry: &carry, startsBlock: true)
        #expect(words == ["in", "2000", "BCE", "after", "44 BC"])
        Tokenizer.appendTokenizedText("AD 14", into: &words, carry: &carry)
        #expect(words == ["in", "2000", "BCE", "after", "44 BC", "AD 14"])
    }

    // MARK: - Consumers of words that hold a space

    @Test func wordStorageRoundTripsUnits() {
        let words = ["in", "2000 BCE,", "at", "10:30 p.m."]
        #expect(WordStorage.decode(WordStorage.encode(words)) == words)
    }

    @Test func complexityScoresStayParallelToUnits() {
        let words = Tokenizer.tokenize("Rome fell in 476 CE and Vesuvius erupted in AD 79 at 1 p.m. they say")
        #expect(words.contains("476 CE"))
        #expect(WordComplexityAnalyzer.analyzeComplexity(words).count == words.count)
        let (lexical, entity) = WordComplexityAnalyzer.tagText(words: words)
        #expect(lexical.count == words.count)
        #expect(entity.count == words.count)
    }

    @Test(.enabled(if: StrobeTests.lexicalTaggingAvailable))
    func complexityTagsStayAlignedAfterAUnit() {
        let words = ["Rome", "fell", "in", "476 CE", "the", "quick", "tomorrow"]
        let (lexical, _) = WordComplexityAnalyzer.tagText(words: words)
        #expect(lexical[3] == .number)
        #expect(lexical[4] == .determiner)
        #expect(lexical[5] == .adjective)
        #expect(lexical[6] != nil)
    }

    @Test func smartTimingDoesNotCountTheSpaceInAUnit() {
        #expect(RSVPEngine.smartTimingMultiplier(for: "2000 BCE", percentPerLetter: 4)
                == RSVPEngine.smartTimingMultiplier(for: "2000BCE", percentPerLetter: 4))
        #expect(RSVPEngine.smartTimingMultiplier(for: "2000 BCE,", percentPerLetter: 4)
                == RSVPEngine.smartTimingMultiplier(for: "2000BCE,", percentPerLetter: 4))
        #expect(RSVPEngine.smartTimingMultiplier(for: "5 PM", percentPerLetter: 4, minimumWordLength: 4) == 1.0)
    }

    /// The designator is a further part of the word, like the second half of
    /// `1990–1995`; a one-digit number is too short to count as a part.
    @Test func unitsTakeCompoundTime() {
        #expect(CompoundWord.partCount(in: "2000 BCE") == 2)
        #expect(CompoundWord.partCount(in: "10:30 PM") == 2)
        #expect(CompoundWord.partCount(in: "(AD 79),") == 2)
        #expect(CompoundWord.partCount(in: "2000–1500 BCE") == 3)
        #expect(CompoundWord.partCount(in: "(27 BCE–") == 2)
        #expect(CompoundWord.partCount(in: "5 PM") == 1)
        #expect(CompoundWord.additionalIntervals(for: "2000 BCE") == 0.5)
    }

    /// 600 WPM gives a 0.1s base interval. The designator is a further part
    /// read letter by letter, so a unit takes compound and acronym time, as
    /// `COVID-19` does.
    @MainActor
    @Test func unitDisplaysLikeACompoundWithAnAcronym() {
        let unit = RSVPEngine(words: ["2000 BCE"], wordsPerMinute: 600)
        let compound = RSVPEngine(words: ["COVID-19"], wordsPerMinute: 600)
        #expect(abs(unit.nextInterval() - 0.1 * (1 + 0.5 + 0.75)) < 0.0001)
        #expect(abs(unit.nextInterval() - compound.nextInterval()) < 0.0001)
    }

    @Test func spaceInAUnitIsNotPunctuation() {
        #expect(PunctuationMarks.marks(in: "2000 BCE") == [])
        #expect(PunctuationMarks.marks(in: "AD 79") == [])
        #expect(PunctuationMarks.marks(in: "2000 BCE,") == [.clause])
        #expect(PunctuationMarks.marks(in: "(27 BCE–") == [.dash])
    }

    // MARK: - Find in passage

    @Test func findMatchesPhraseInsideAUnit() {
        let words = ["built", "in", "2000 bce,", "by", "them"]
        #expect(PassageView.findMatchRanges(query: "2000 BCE", inLowercasedWords: words) == [2..<3])
        #expect(PassageView.findMatchRanges(query: "bce", inLowercasedWords: words) == [2..<3])
        #expect(PassageView.findMatchRanges(query: "2000", inLowercasedWords: words) == [2..<3])
        #expect(PassageView.findMatches(query: "2000 BCE", in: ["Built", "in", "2000 BCE,", "by"]) == [2])
    }

    @Test func findMatchesPhraseReachingIntoAUnit() {
        let words = ["built", "in", "2000 bce,", "by", "them"]
        #expect(PassageView.findMatchRanges(query: "in 2000", inLowercasedWords: words) == [1..<3])
        #expect(PassageView.findMatchRanges(query: "in 2000 bce", inLowercasedWords: words) == [1..<3])
        #expect(PassageView.findMatchRanges(query: "bce, by them", inLowercasedWords: words) == [2..<5])
        #expect(PassageView.findMatchRanges(query: "built in 2000 bce, by", inLowercasedWords: words) == [0..<4])
        #expect(PassageView.findMatchRanges(query: "in bce", inLowercasedWords: words).isEmpty)
        #expect(PassageView.findMatchRanges(query: "2000 by", inLowercasedWords: words).isEmpty)
    }

    @Test func findMatchesMergesPhraseMatchesStartingInTheSameWord() {
        let words = ["10 am", "10 am"]
        #expect(PassageView.findMatchRanges(query: "10 am", inLowercasedWords: words) == [0..<1, 1..<2])
        #expect(PassageView.findMatchRanges(query: "am 10", inLowercasedWords: words) == [0..<2])
        #expect(PassageView.findMatchRanges(query: "0 a", inLowercasedWords: ["0 a0 a"]) == [0..<1])
    }

    // MARK: - ORP anchor

    /// Letters and digits both count, so the anchor sits left of center in
    /// the whole unit rather than inside its designator.
    @Test func orpAnchorTreatsAUnitAsOneWord() {
        #expect(WordView.redIndex(of: "2000 BCE") == 2)
        #expect(WordView.redIndex(of: "(2000 BCE),") == 3)
        #expect(WordView.redIndex(of: "44 BC") == 1)
        #expect(WordView.redIndex(of: "AD 79") == 1)
        #expect(WordView.redIndex(of: "10:30 PM") == 3)
        #expect(WordView.redIndex(of: "5 p.m.") == 2)
        #expect(WordView.redIndex(of: "2000–1500 BCE") == 3)
    }

    @Test func orpAnchorNeverLandsOnTheSpaceOrPunctuation() {
        for word in ["2000 BCE", "5 PM", "1 AH;", "(27 BCE–", "10:30 p.m.", "A.D. 79.", "10,000 B.C.E.,"] {
            let index = WordView.redIndex(of: word)
            let anchor = word[word.index(word.startIndex, offsetBy: index)]
            #expect(anchor.isLetter || anchor.isNumber, "anchor of \(word) is '\(anchor)'")
        }
    }

    @Test func orpAnchorCountsDigitsLikeLetters() {
        #expect(WordView.redIndex(of: "2000") == 1)
        #expect(WordView.redIndex(of: "1,000,000") == 3)
        #expect(WordView.redIndex(of: "1990s") == 1)
        #expect(WordView.redIndex(of: "3rd") == 1)
        #expect(WordView.redIndex(of: "B12") == 1)
        #expect(WordView.redIndex(of: "$5") == 1)
        #expect(WordView.redIndex(of: "1.") == 0)
        #expect(WordView.redIndex(of: "٢٠٠٠") == 1)
        #expect(WordView.redIndex(of: "reading") == 2)
        #expect(WordView.redIndex(of: "don't") == 1)
        #expect(WordView.redIndex(of: "...") == 1)
    }

    @Test func orpAnchorSkipsSuperscriptsAndSubscripts() {
        #expect(WordView.redIndex(of: "m²") == 0)
        #expect(WordView.redIndex(of: "H₂O") == 2)
    }
}
