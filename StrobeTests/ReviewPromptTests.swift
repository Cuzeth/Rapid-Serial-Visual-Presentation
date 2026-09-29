import Foundation
import Testing
@testable import Strobe

struct ReviewPromptTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Noon UTC on 2026-09-01, plus `offset` days.
    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let start = Date(timeIntervalSince1970: 1_788_220_800) // 2026-09-01 00:00 UTC
        return start.addingTimeInterval(TimeInterval(offset * 86_400 + hour * 3_600))
    }

    private func readingDays(_ offsets: [Int], into prompt: inout ReviewPrompt) {
        for offset in offsets {
            prompt.recordWordsRead(ReviewPrompt.wordsPerReadingDay, at: day(offset), calendar: Self.calendar)
        }
    }

    @Test func dueOnTheThirdReadingDay() {
        var prompt = ReviewPrompt()
        readingDays([0, 1], into: &prompt)
        #expect(!prompt.isDue(at: day(1), appVersion: "3.1", calendar: Self.calendar))
        readingDays([5], into: &prompt)
        #expect(prompt.readingDays == 3)
        #expect(prompt.isDue(at: day(5), appVersion: "3.1", calendar: Self.calendar))
    }

    @Test func shortSessionsAddUpWithinADay() {
        var prompt = ReviewPrompt()
        let half = ReviewPrompt.wordsPerReadingDay / 2
        prompt.recordWordsRead(half, at: day(0, hour: 8), calendar: Self.calendar)
        #expect(prompt.readingDays == 0)
        prompt.recordWordsRead(half, at: day(0, hour: 20), calendar: Self.calendar)
        #expect(prompt.readingDays == 1)
        // More reading the same day doesn't make it two days.
        prompt.recordWordsRead(half * 10, at: day(0, hour: 21), calendar: Self.calendar)
        #expect(prompt.readingDays == 1)
    }

    @Test func shortSessionsOnDifferentDaysDontCount() {
        var prompt = ReviewPrompt()
        let almost = ReviewPrompt.wordsPerReadingDay - 1
        for offset in 0..<10 {
            prompt.recordWordsRead(almost, at: day(offset), calendar: Self.calendar)
        }
        #expect(prompt.readingDays == 0)
        #expect(!prompt.isDue(at: day(9), appVersion: "3.1", calendar: Self.calendar))
    }

    @Test func notDueOnADayWithoutReading() {
        var prompt = ReviewPrompt()
        readingDays([0, 1, 2], into: &prompt)
        #expect(!prompt.isDue(at: day(3), appVersion: "3.1", calendar: Self.calendar))
        prompt.recordWordsRead(10, at: day(3), calendar: Self.calendar)
        #expect(!prompt.isDue(at: day(3), appVersion: "3.1", calendar: Self.calendar))
    }

    @Test func asksOncePerVersion() {
        var prompt = ReviewPrompt()
        readingDays([0, 1, 2], into: &prompt)
        prompt.recordPrompt(at: day(2), appVersion: "3.1")
        #expect(prompt.readingDays == 0)
        readingDays([100, 101, 102], into: &prompt)
        #expect(!prompt.isDue(at: day(102), appVersion: "3.1", calendar: Self.calendar))
        #expect(prompt.isDue(at: day(102), appVersion: "3.2", calendar: Self.calendar))
    }

    @Test func waitsBetweenPrompts() {
        var prompt = ReviewPrompt()
        readingDays([0, 1, 2], into: &prompt)
        prompt.recordPrompt(at: day(2), appVersion: "3.1")
        let lastDay = 2 + ReviewPrompt.minimumDaysBetweenPrompts
        readingDays([lastDay - 3, lastDay - 2, lastDay - 1], into: &prompt)
        #expect(!prompt.isDue(at: day(lastDay - 1), appVersion: "3.2", calendar: Self.calendar))
        readingDays([lastDay], into: &prompt)
        #expect(prompt.isDue(at: day(lastDay), appVersion: "3.2", calendar: Self.calendar))
    }

    @Test func readingDaysStartOverAfterAsking() {
        var prompt = ReviewPrompt()
        readingDays([0, 1, 2], into: &prompt)
        prompt.recordPrompt(at: day(2), appVersion: "3.1")
        readingDays([90, 91], into: &prompt)
        #expect(!prompt.isDue(at: day(91), appVersion: "3.2", calendar: Self.calendar))
    }

    @Test func persistsAndRecoversFromBadData() throws {
        let suite = "ReviewPromptTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ReviewPrompt.load(from: defaults) == ReviewPrompt())
        ReviewPrompt.update(in: defaults) {
            $0.recordWordsRead(ReviewPrompt.wordsPerReadingDay, at: day(0), calendar: Self.calendar)
            $0.recordPrompt(at: day(0), appVersion: "3.1")
        }
        let loaded = ReviewPrompt.load(from: defaults)
        #expect(loaded.wordsOnDay == ReviewPrompt.wordsPerReadingDay)
        #expect(loaded.lastPromptVersion == "3.1")
        #expect(loaded.lastPromptDate == day(0))

        defaults.set(Data("not json".utf8), forKey: ReviewPrompt.storageKey)
        #expect(ReviewPrompt.load(from: defaults) == ReviewPrompt())
    }

    @MainActor
    @Test func engineCountsOnlyPlayedWords() {
        let engine = RSVPEngine(words: ["one", "two", "three", "four", "five"], wordsPerMinute: 1)
        defer { engine.pause() }
        engine.play()
        engine.advance()
        engine.advance()
        engine.seek(to: 4) // Scrubbing and seeking aren't reading.
        engine.seek(to: 0)
        #expect(engine.takePlayedWordCount() == 2)
        #expect(engine.takePlayedWordCount() == 0)
        engine.play()
        engine.advance()
        #expect(engine.takePlayedWordCount() == 1)
    }

    @MainActor
    @Test func engineDoesNotCountWordsAChapterTitleReplaces() {
        let chapter = Chapter(title: "Chapter One", wordIndex: 0)
        let engine = RSVPEngine(
            words: ["Chapter", "One", "It", "began"], wordsPerMinute: 1, chapters: [chapter]
        )
        defer { engine.pause() }
        engine.play()
        engine.advance() // Title fades out.
        engine.advance() // Reading picks up after the heading's words.
        #expect(engine.currentWord == "It")
        #expect(engine.takePlayedWordCount() == 0)
        engine.advance()
        #expect(engine.takePlayedWordCount() == 1)
    }
}
