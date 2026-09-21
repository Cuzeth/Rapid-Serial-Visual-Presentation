import Testing
import Foundation
@testable import Strobe

struct PunctuationPauseTests {

    private typealias Expectation = (word: String, marks: PunctuationMarks)

    private func expectMarks(_ expectations: [Expectation]) {
        for (word, marks) in expectations {
            #expect(PunctuationMarks.marks(in: word) == marks, "mismatch for \(word)")
        }
    }

    // MARK: - Classification

    @Test func plainWordsCarryNoMarks() {
        expectMarks([
            ("word", []),
            ("", []),
            ("don't", []),
            ("well-known", []),
            ("***", []),
        ])
    }

    @Test func classifiesSentenceEnds() {
        expectMarks([
            ("end.", .sentenceEnd),
            ("what?", .sentenceEnd),
            ("wow!", .sentenceEnd),
            ("what?!", .sentenceEnd),
            ("Mr.", .sentenceEnd),
            ("U.S.A.", .sentenceEnd),
            ("wait..", .sentenceEnd),
            ("end.'", .sentenceEnd),
            ("home.\"", [.sentenceEnd, .bracket]),
            ("fun!)", [.sentenceEnd, .bracket]),
            ("end.])", [.sentenceEnd, .bracket]),
            ("end.\u{2019}\u{201D}", [.sentenceEnd, .bracket]),
        ])
    }

    @Test func classifiesClauseMarks() {
        expectMarks([
            ("hello,", .clause),
            ("semi;", .clause),
            ("note:", .clause),
            ("there,\u{2019}", .clause),
            ("said,\"", [.clause, .bracket]),
            ("word),", [.clause, .bracket]),
            ("word\",", [.clause, .bracket]),
        ])
    }

    /// A period with a clause mark or dash to its right closes an
    /// abbreviation, not a sentence.
    @Test func abbreviationPeriodBeforeAnotherMarkIsNotASentenceEnd() {
        expectMarks([
            ("e.g.,", .clause),
            ("etc.),", [.clause, .bracket]),
            ("U.S.\u{2014}", .dash),
            ("Why?\",", [.clause, .bracket]),
        ])
    }

    @Test func classifiesDashes() {
        expectMarks([
            ("elements\u{2014}", .dash),
            ("word\u{2013}", .dash),
            ("word\u{2015}", .dash),
            ("word--", .dash),
            ("word-", .dash),
            ("\u{2014}", .dash),
            ("I\u{2014}\u{201D}", [.dash, .bracket]),
        ])
    }

    @Test func classifiesEllipses() {
        expectMarks([
            ("wait...", .ellipsis),
            ("wait....", .ellipsis),
            ("wait\u{2026}", .ellipsis),
            ("wait...\"", [.ellipsis, .bracket]),
            ("wait...?", [.sentenceEnd, .ellipsis]),
            ("Really?...", [.sentenceEnd, .ellipsis]),
            ("well...,", [.clause, .ellipsis]),
            ("word...\u{2014}\u{2013}", [.ellipsis, .dash]),
        ])
    }

    @Test func classifiesClosingBracketsAndQuotes() {
        expectMarks([
            ("(word)", .bracket),
            ("word]", .bracket),
            ("word}", .bracket),
            ("\"hello\"", .bracket),
            ("\u{201C}hello\u{201D}", .bracket),
            ("\u{201E}Hallo\u{201C}", .bracket),
            ("\u{00AB}mot\u{00BB}", .bracket),
            ("\u{00BB}Wort\u{00AB}", .bracket),
        ])
    }

    /// A trailing apostrophe is a possessive or an elision far more often
    /// than the end of a quotation.
    @Test func trailingApostropheDoesNotPause() {
        expectMarks([
            ("dogs'", []),
            ("dogs\u{2019}", []),
            ("goin\u{2019}", []),
            ("\u{2018}Hello\u{2019}", []),
        ])
    }

    @Test func leadingMarksDoNotPause() {
        expectMarks([
            ("(word", []),
            ("\"word", []),
            ("\u{2014}stone", []),
            ("\u{201C}\u{2014}stone", []),
            ("...and", []),
            ("\u{2026}and", []),
            ("--verbose", []),
        ])
    }

    @Test func internalMarksDoNotPause() {
        expectMarks([
            ("3.14", []),
            ("1,000", []),
            ("10:30", []),
            ("example.com", []),
            ("a..b", []),
            ("1990\u{2013}1995", []),
            ("$1,000.", .sentenceEnd),
            ("3.14,", .clause),
        ])
    }

    /// Documents tokenized before dashes split words hold tokens like
    /// `elements—stone`.
    @Test func fusedTokensPauseForTheirInternalDashOrEllipsis() {
        expectMarks([
            ("elements\u{2014}stone", .dash),
            ("well--maybe", .dash),
            ("said\u{2014}\u{201C}but", .dash),
            ("wait...what", .ellipsis),
            ("I\u{2026}I", .ellipsis),
            ("elements\u{2014}stone.", [.sentenceEnd, .dash]),
            ("wait...what?", [.sentenceEnd, .ellipsis]),
        ])
    }

    @Test func classifiesChinesePunctuation() {
        expectMarks([
            ("好。", .sentenceEnd),
            ("吗？", .sentenceEnd),
            ("啊！", .sentenceEnd),
            ("好，", .clause),
            ("好、", .clause),
            ("好；", .clause),
            ("好：", .clause),
            ("什么……", .ellipsis),
            ("什么——", .dash),
            ("「好」", .bracket),
            ("（好）", .bracket),
            ("好。」", [.sentenceEnd, .bracket]),
        ])
    }

    @Test func classifiesArabicPunctuation() {
        expectMarks([
            ("ماذا؟", .sentenceEnd),
            ("نعم۔", .sentenceEnd),
            ("مرحبا،", .clause),
            ("مرحبا؛", .clause),
            ("مرحبا،\u{200F}", .clause),   // trailing right-to-left mark
            ("مرحبًا", []),
        ])
    }

    @Test func sentencePunctuationCheckTreatsEllipsisAsItsOwnType() {
        #expect(!RSVPEngine.endsWithSentencePunctuation("wait..."))
        #expect(RSVPEngine.endsWithSentencePunctuation("wait...?"))
        #expect(RSVPEngine.endsWithSentencePunctuation("好。」"))
    }

    // MARK: - Multiplier

    private func multiplier(
        for word: String,
        sentenceEnd: Double = 1.5,
        pauses: PunctuationPauses = PunctuationPauses()
    ) -> Double {
        pauses.multiplier(for: PunctuationMarks.marks(in: word), sentenceEnd: sentenceEnd)
    }

    @Test func eachTypeUsesItsOwnMultiplier() {
        let pauses = PunctuationPauses(clause: 1.1, dash: 1.2, ellipsis: 1.3, bracket: 1.4)
        #expect(multiplier(for: "word", sentenceEnd: 2.0, pauses: pauses) == 1.0)
        #expect(multiplier(for: "3.14", sentenceEnd: 2.0, pauses: pauses) == 1.0)
        #expect(multiplier(for: "end.", sentenceEnd: 2.0, pauses: pauses) == 2.0)
        #expect(multiplier(for: "hello,", sentenceEnd: 2.0, pauses: pauses) == 1.1)
        #expect(multiplier(for: "elements\u{2014}", sentenceEnd: 2.0, pauses: pauses) == 1.2)
        #expect(multiplier(for: "elements\u{2014}stone", sentenceEnd: 2.0, pauses: pauses) == 1.2)
        #expect(multiplier(for: "wait...", sentenceEnd: 2.0, pauses: pauses) == 1.3)
        #expect(multiplier(for: "(word)", sentenceEnd: 2.0, pauses: pauses) == 1.4)
    }

    @Test func severalMarksPauseOnceForTheLongest() {
        #expect(multiplier(for: "word),") == 1.3)
        #expect(multiplier(for: "home.\"") == 1.5)
        #expect(multiplier(for: "what?!") == 1.5)
        #expect(multiplier(for: "home.\"", sentenceEnd: 1.0, pauses: PunctuationPauses(bracket: 1.8)) == 1.8)
    }

    @Test func multiplierOfOneTurnsATypeOff() {
        let pauses = PunctuationPauses(clause: 1.0, bracket: 1.0)
        #expect(multiplier(for: "word),", pauses: pauses) == 1.0)
        #expect(multiplier(for: "end.", sentenceEnd: 1.0) == 1.0)
    }

    @Test func multiplierNeverShortensAWord() {
        #expect(multiplier(for: "hello,", pauses: PunctuationPauses(clause: 0.5)) == 1.0)
        #expect(multiplier(for: "end.", sentenceEnd: 0.5) == 1.0)
    }

    @Test func defaultPausesAreShorterThanOrEqualToASentenceEnd() {
        let pauses = PunctuationPauses()
        for value in [pauses.clause, pauses.dash, pauses.ellipsis, pauses.bracket] {
            #expect(value > 1.0)
            #expect(value <= ReaderSettings.Defaults.sentencePauseMultiplier)
        }
    }

    // MARK: - Smart timing bonus

    @Test func smartTimingDropsPunctuationBonusOnRequest() {
        #expect(abs(RSVPEngine.smartTimingMultiplier(for: "and,", punctuationBonus: false) - 1.12) < 0.0001)
        #expect(abs(RSVPEngine.smartTimingMultiplier(for: "reading.", punctuationBonus: false) - 1.28) < 0.0001)
        #expect(RSVPEngine.smartTimingMultiplier(for: "and,", minimumWordLength: 6, punctuationBonus: false) == 1.0)
        #expect(RSVPEngine.smartTimingMultiplier(for: "cat", punctuationBonus: false)
            == RSVPEngine.smartTimingMultiplier(for: "cat"))
    }

    // MARK: - Engine timing

    /// 600 WPM gives a 0.1s base interval.
    @MainActor
    private func interval(
        for word: String,
        smartTiming: Bool = false,
        pauses: Bool = false,
        sentencePauseMultiplier: Double = 1.5
    ) -> TimeInterval {
        RSVPEngine(
            words: [word],
            wordsPerMinute: 600,
            smartTimingEnabled: smartTiming,
            sentencePauseEnabled: pauses,
            sentencePauseMultiplier: sentencePauseMultiplier
        ).nextInterval()
    }

    @MainActor
    @Test func clauseMarksPauseWithoutSmartTiming() {
        #expect(abs(interval(for: "hello,") - 0.1) < 0.0001)
        #expect(abs(interval(for: "hello,", pauses: true) - 0.13) < 0.0001)
        #expect(abs(interval(for: "elements\u{2014}", pauses: true) - 0.14) < 0.0001)
        #expect(abs(interval(for: "hello", pauses: true) - 0.1) < 0.0001)
    }

    /// With both features on, the pause replaces smart timing's fixed bonus
    /// instead of compounding with it.
    @MainActor
    @Test func punctuationIsNotCountedTwiceWithSmartTiming() {
        #expect(abs(interval(for: "and,", smartTiming: true) - 0.132) < 0.0001)
        #expect(abs(interval(for: "and,", smartTiming: true, pauses: true) - 0.1 * 1.12 * 1.3) < 0.0001)
        #expect(abs(interval(for: "end.", smartTiming: true, pauses: true) - 0.1 * 1.12 * 1.5) < 0.0001)
    }

    @MainActor
    @Test func storedSentenceMultiplierKeepsItsMeaning() {
        #expect(abs(interval(for: "end.", pauses: true, sentencePauseMultiplier: 2.5) - 0.25) < 0.0001)
        #expect(abs(interval(for: "hello,", pauses: true, sentencePauseMultiplier: 2.5) - 0.13) < 0.0001)
    }

    @MainActor
    @Test func engineUsesUpdatedPunctuationPauses() {
        let engine = RSVPEngine(words: ["hello,"], wordsPerMinute: 600, sentencePauseEnabled: true)
        engine.punctuationPauses.clause = 2.0
        #expect(abs(engine.nextInterval() - 0.2) < 0.0001)
        engine.punctuationPauses = PunctuationPauses(clause: 1.0)
        #expect(abs(engine.nextInterval() - 0.1) < 0.0001)
    }

    // MARK: - Settings

    @Test func settingsDefaultsMatchEngineDefaults() throws {
        let suiteName = "PunctuationPauseTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let snapshot = ReaderSettings.timingSnapshot(from: defaults)
        #expect(snapshot.punctuationPauses == PunctuationPauses())
        #expect(snapshot.punctuationPauses == PunctuationPauses(
            clause: ReaderSettings.Defaults.clausePauseMultiplier,
            dash: ReaderSettings.Defaults.dashPauseMultiplier,
            ellipsis: ReaderSettings.Defaults.ellipsisPauseMultiplier,
            bracket: ReaderSettings.Defaults.bracketPauseMultiplier
        ))
    }

    @Test func settingsSnapshotReadsStoredPauses() throws {
        let suiteName = "PunctuationPauseTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(1.8, forKey: ReaderSettings.Keys.clausePauseMultiplier)
        defaults.set(2.2, forKey: ReaderSettings.Keys.dashPauseMultiplier)
        defaults.set(1.0, forKey: ReaderSettings.Keys.bracketPauseMultiplier)

        let snapshot = ReaderSettings.timingSnapshot(from: defaults)
        #expect(snapshot.punctuationPauses.clause == 1.8)
        #expect(snapshot.punctuationPauses.dash == 2.2)
        #expect(snapshot.punctuationPauses.bracket == 1.0)
        // Unset keys still fall back to defaults.
        #expect(snapshot.punctuationPauses.ellipsis == ReaderSettings.Defaults.ellipsisPauseMultiplier)
    }
}
