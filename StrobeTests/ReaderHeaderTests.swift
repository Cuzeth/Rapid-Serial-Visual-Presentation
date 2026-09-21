import Testing
import Foundation
@testable import Strobe

struct ReaderHeaderTests {

    private static func chapters(_ entries: [(String, Int)]) -> [Chapter] {
        entries.map { Chapter(title: $0.0, wordIndex: $0.1) }
    }

    private static let book = ChapterTimeline(chapters([
        ("One", 10), ("Two", 50), ("Three", 120)
    ]))

    // MARK: - Settings

    @Test func headerLinesAreOffByDefault() {
        #expect(ReaderSettings.Defaults.readingHeaderTitleEnabled == false)
        #expect(ReaderSettings.Defaults.readingHeaderChapterEnabled == false)
    }

    // MARK: - Current chapter lookup

    @Test func documentWithoutChaptersHasNoCurrentChapter() {
        let timeline = ChapterTimeline([])
        #expect(timeline.chapters.isEmpty)
        #expect(timeline.chapter(containing: 0) == nil)
        #expect(timeline.chapter(containing: 5_000) == nil)
    }

    @Test func noCurrentChapterBeforeTheFirstOneStarts() {
        #expect(Self.book.chapter(containing: 0) == nil)
        #expect(Self.book.chapter(containing: 9) == nil)
        #expect(Self.book.chapter(containing: -1) == nil)
    }

    @Test func chapterBeginsExactlyAtItsWordIndex() {
        #expect(Self.book.chapter(containing: 10)?.title == "One")
        #expect(Self.book.chapter(containing: 49)?.title == "One")
        #expect(Self.book.chapter(containing: 50)?.title == "Two")
        #expect(Self.book.chapter(containing: 119)?.title == "Two")
        #expect(Self.book.chapter(containing: 120)?.title == "Three")
    }

    @Test func lastChapterRunsToTheEndOfTheDocument() {
        #expect(Self.book.chapter(containing: 121)?.title == "Three")
        #expect(Self.book.chapter(containing: 1_000_000)?.title == "Three")
    }

    @Test func chapterStartingAtTheFirstWordCoversIt() {
        let timeline = ChapterTimeline(Self.chapters([("Prologue", 0), ("One", 40)]))
        #expect(timeline.chapter(containing: 0)?.title == "Prologue")
        #expect(timeline.chapter(containing: 39)?.title == "Prologue")
    }

    @Test func singleChapterDocument() {
        let timeline = ChapterTimeline(Self.chapters([("Only", 7)]))
        #expect(timeline.chapter(containing: 6) == nil)
        #expect(timeline.chapter(containing: 7)?.title == "Only")
        #expect(timeline.chapter(containing: 8)?.title == "Only")
    }

    @Test func unsortedChaptersAreSortedByStart() {
        let timeline = ChapterTimeline(Self.chapters([
            ("Three", 120), ("One", 10), ("Four", 300), ("Two", 50)
        ]))
        #expect(timeline.chapters.map(\.title) == ["One", "Two", "Three", "Four"])
        #expect(timeline.chapter(containing: 60)?.title == "Two")
        #expect(timeline.chapter(containing: 299)?.title == "Three")
        #expect(timeline.chapter(containing: 300)?.title == "Four")
    }

    /// Matches `RSVPEngine`, which announces the first chapter listed at a
    /// word index.
    @Test func firstChapterListedAtAWordIndexWins() {
        let timeline = ChapterTimeline(Self.chapters([
            ("Part I", 10), ("Chapter 1", 10), ("Chapter 2", 50), ("Duplicate 2", 50)
        ]))
        #expect(timeline.chapters.map(\.title) == ["Part I", "Chapter 2"])
        #expect(timeline.chapter(containing: 10)?.title == "Part I")
        #expect(timeline.chapter(containing: 50)?.title == "Chapter 2")
    }

    @Test func firstListedWinsEvenWhenDuplicatesArriveUnsorted() {
        let timeline = ChapterTimeline(Self.chapters([
            ("Late", 90), ("Early A", 5), ("Late again", 90), ("Early B", 5)
        ]))
        #expect(timeline.chapters.map(\.title) == ["Early A", "Late"])
    }

    @Test func untitledChaptersAreIgnored() {
        let timeline = ChapterTimeline(Self.chapters([
            ("One", 10), ("", 50), ("  \n", 80), ("Two", 120)
        ]))
        #expect(timeline.chapters.map(\.title) == ["One", "Two"])
        #expect(timeline.chapter(containing: 50)?.title == "One")
        #expect(timeline.chapter(containing: 119)?.title == "One")
        #expect(timeline.chapter(containing: 120)?.title == "Two")
    }

    @Test func untitledChapterDoesNotShadowATitledOneAtTheSameIndex() {
        let timeline = ChapterTimeline(Self.chapters([("", 10), ("One", 10)]))
        #expect(timeline.chapter(containing: 10)?.title == "One")
    }

    @Test func onlyUntitledChaptersMeansNoCurrentChapter() {
        let timeline = ChapterTimeline(Self.chapters([("", 0), (" ", 30)]))
        #expect(timeline.chapters.isEmpty)
        #expect(timeline.chapter(containing: 40) == nil)
    }

    @Test func chaptersWithNegativeWordIndexesAreIgnored() {
        let timeline = ChapterTimeline(Self.chapters([("Broken", -4), ("One", 10)]))
        #expect(timeline.chapters.map(\.wordIndex) == [10])
        #expect(timeline.chapter(containing: 0) == nil)
    }

    @Test func timelinesBuiltFromEquivalentInputAreEqual() {
        let sorted = ChapterTimeline(Self.chapters([("One", 10), ("Two", 50)]))
        let shuffled = ChapterTimeline(Self.chapters([("Two", 50), ("", 20), ("One", 10), ("Dup", 50)]))
        #expect(sorted == shuffled)
    }

    // MARK: - Sorted-array search (shared with the chapter navigation bar)

    @Test func indexSearchReturnsNilBeforeTheFirstChapterAndForNoChapters() {
        #expect(ChapterTimeline.index(in: [], containing: 0) == nil)
        #expect(ChapterTimeline.index(in: Self.book.chapters, containing: 9) == nil)
    }

    /// The navigation bar searches the document's raw list, which can repeat
    /// a word index; it has always resolved to the last of them.
    @Test func indexSearchPicksTheLastChapterSharingAStart() {
        let raw = Self.chapters([("A", 10), ("B", 10), ("C", 10), ("D", 40)])
        #expect(ChapterTimeline.index(in: raw, containing: 10) == 2)
        #expect(ChapterTimeline.index(in: raw, containing: 39) == 2)
        #expect(ChapterTimeline.index(in: raw, containing: 40) == 3)
    }

    @Test func indexSearchAgreesWithALinearScan() {
        let starts = [0, 3, 4, 4, 9, 27, 28, 64, 64, 64, 200, 1_000]
        let sorted = starts.enumerated().map { Chapter(title: "Ch \($0.offset)", wordIndex: $0.element) }
        for count in 0...sorted.count {
            let list = Array(sorted.prefix(count))
            for wordIndex in -2...1_002 {
                let expected = list.lastIndex { $0.wordIndex <= wordIndex }
                #expect(ChapterTimeline.index(in: list, containing: wordIndex) == expected,
                        "count \(count), word \(wordIndex)")
            }
        }
    }

    // MARK: - Faded tone

    /// WCAG relative luminance of `rgb` drawn at `opacity` over black.
    private static func luminance(of rgb: UInt32, opacity: Double) -> Double {
        func linear(_ channel: UInt32) -> Double {
            let value = Double(channel & 0xFF) / 255 * opacity
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb >> 16) + 0.7152 * linear(rgb >> 8) + 0.0722 * linear(rgb)
    }

    private static func contrastOnBlack(_ rgb: UInt32, opacity: Double) -> Double {
        (luminance(of: rgb, opacity: opacity) + 0.05) / 0.05
    }

    /// Faded text stays legible without nearing the word's own contrast, and
    /// reads equally quiet whichever tone is active.
    @Test func fadedTextLandsNearThreeToOneInEveryTone() {
        for tone in ReaderTextTone.allCases {
            let faded = Self.contrastOnBlack(tone.textRGB, opacity: tone.fadedTextOpacity)
            let word = Self.contrastOnBlack(tone.textRGB, opacity: 1)
            #expect(faded >= 2.7 && faded <= 3.3, "\(tone.rawValue): \(faded)")
            #expect(faded < word * 0.6, "\(tone.rawValue): \(faded) vs \(word)")
        }
    }
}
