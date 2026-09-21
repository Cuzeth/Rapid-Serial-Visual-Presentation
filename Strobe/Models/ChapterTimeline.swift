import Foundation

/// A document's chapters arranged for position lookups.
///
/// `Document.chapters` comes straight from the importer: it can be unsorted,
/// repeat a word index (nested PDF outline entries that land on one page),
/// or carry blank titles. The timeline keeps titled chapters only, one per
/// word index — the first listed wins, as it does for `RSVPEngine`'s
/// chapter announcements — sorted by where they start.
nonisolated struct ChapterTimeline: Equatable {
    let chapters: [Chapter]

    init(_ chapters: [Chapter]) {
        var seen = Set<Int>()
        self.chapters = chapters
            .filter { chapter in
                chapter.wordIndex >= 0 && chapter.title.contains { !$0.isWhitespace }
            }
            .filter { seen.insert($0.wordIndex).inserted }
            .sorted { $0.wordIndex < $1.wordIndex }
    }

    /// The chapter `wordIndex` falls in: the last one starting at or before
    /// it. Nil before the first chapter's start and when there are none.
    func chapter(containing wordIndex: Int) -> Chapter? {
        Self.index(in: chapters, containing: wordIndex).map { chapters[$0] }
    }

    /// Index of the last chapter starting at or before `wordIndex`, or nil
    /// when every chapter starts after it. Among chapters sharing a start,
    /// that is the last listed.
    ///
    /// A binary search — callers run it on every word tick.
    /// `sortedChapters` must be ascending by `wordIndex`.
    static func index(in sortedChapters: [Chapter], containing wordIndex: Int) -> Int? {
        var low = 0
        var high = sortedChapters.count
        while low < high {
            let mid = low + (high - low) / 2
            if sortedChapters[mid].wordIndex <= wordIndex {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low == 0 ? nil : low - 1
    }
}
