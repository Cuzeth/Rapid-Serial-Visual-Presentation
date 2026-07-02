import SwiftUI
import SwiftData

/// Displays the chapter list for a document with progress indicators.
///
/// Shows a "Read Full Document" option and individual chapters with
/// not-started / in-progress / completed status based on the furthest
/// position the user has read to.
struct ChapterListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let document: Document

    @FocusState private var listFocused: Bool

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 720 : .infinity
    }

    var body: some View {
        ZStack {
            // Background
            StrobeTheme.Gradients.mainBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Full Document Option
                        NavigationLink(value: ReaderRoute(document: document)) {
                            fullDocumentRow
                        }
                        .buttonStyle(StrobeCardButtonStyle())

                        // Divide
                        Rectangle()
                            .fill(StrobeTheme.surface)
                            .frame(height: 1)
                            .padding(.horizontal)

                        // Chapters
                        LazyVStack(spacing: 12) {
                            ForEach(Array(document.chapters.enumerated()), id: \.element.id) { index, chapter in
                                NavigationLink(value: ReaderRoute(
                                    document: document,
                                    startingWordIndex: startingWordIndex(forChapterAt: index)
                                )) {
                                    chapterRow(chapter: chapter, index: index)
                                }
                                .buttonStyle(StrobeCardButtonStyle())
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        // Escape pops this list on macOS, matching the reader and passage
        // view. Focus is taken on appear so the key has a responder.
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onAppear { listFocused = true }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            CircleIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {
                dismiss()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(StrobeTheme.titleFont(size: 20))
                    .foregroundStyle(StrobeTheme.textPrimary)
                    .lineLimit(1)

                Text("\(document.chapters.count) chapters")
                    .font(StrobeTheme.bodyFont(size: 14))
                    .foregroundStyle(StrobeTheme.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(StrobeTheme.background.opacity(0.8))
    }

    // MARK: - Full document row

    private var fullDocumentRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Read Full Document")
                    .font(StrobeTheme.bodyFont(size: 18, bold: true))
                    .foregroundStyle(StrobeTheme.textPrimary)

                HStack(spacing: 6) {
                    Text("\(document.wordCount) words")
                    Text("•")
                    Text("\(Int(document.progress * 100))% complete")
                }
                .font(StrobeTheme.bodyFont(size: 14))
                .foregroundStyle(StrobeTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(StrobeTheme.accent)
        }
        .padding(16)
        .background(StrobeTheme.Gradients.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Chapter row

    private func chapterRow(chapter: Chapter, index: Int) -> some View {
        let wordCount = chapterWordCount(at: index)
        let status = chapterStatus(at: index)

        return HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(chapter.title)
                    .font(StrobeTheme.bodyFont(size: 16, bold: true))
                    .foregroundStyle(status == .completed ? StrobeTheme.textSecondary : StrobeTheme.textPrimary)
                    .lineLimit(2)

                Text("\(wordCount) words")
                    .font(StrobeTheme.bodyFont(size: 12))
                    .foregroundStyle(StrobeTheme.textSecondary)
            }

            Spacer()

            switch status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(StrobeTheme.accent)
                    .font(.system(size: 20))
            case .inProgress:
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(StrobeTheme.accent)
                    .font(.system(size: 20))
            case .notStarted:
                Image(systemName: "circle")
                    .foregroundStyle(StrobeTheme.surface)
                    .font(.system(size: 20))
            }
        }
        .padding(16)
        .background(StrobeTheme.Gradients.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(status == .completed ? 0.6 : 1.0)
    }

    // MARK: - Helpers

    // nonisolated so the synthesized Equatable can be used off the main
    // actor (tests compare statuses inside nonisolated #expect closures).
    nonisolated enum ChapterStatus {
        case notStarted, inProgress, completed
    }

    private func chapterBounds(at index: Int) -> (start: Int, end: Int) {
        Self.chapterBounds(at: index, chapters: document.chapters, totalWordCount: document.wordCount)
    }

    private func startingWordIndex(forChapterAt index: Int) -> Int {
        Self.startingWordIndex(
            forChapterAt: index,
            chapters: document.chapters,
            totalWordCount: document.wordCount,
            currentWordIndex: document.currentWordIndex
        )
    }

    private func chapterWordCount(at index: Int) -> Int {
        let (start, end) = chapterBounds(at: index)
        return max(0, end - start)
    }

    private func chapterStatus(at index: Int) -> ChapterStatus {
        Self.chapterStatus(
            at: index,
            chapters: document.chapters,
            totalWordCount: document.wordCount,
            furthestWordIndex: document.displayedFurthestWordIndex
        )
    }

    // MARK: - Pure helpers (testable)

    /// Half-open word-index bounds of the chapter at `index`.
    nonisolated static func chapterBounds(at index: Int, chapters: [Chapter], totalWordCount: Int) -> (start: Int, end: Int) {
        let start = chapters[index].wordIndex
        let end = index + 1 < chapters.count
            ? chapters[index + 1].wordIndex
            : totalWordCount
        return (start, end)
    }

    /// Where the reader should start when a chapter row is tapped.
    ///
    /// Resumes at the user's current position when it falls inside this
    /// chapter — otherwise tapping the chapter you're partway through (and
    /// then leaving the reader) would overwrite your saved position with the
    /// chapter start. Judged on `currentWordIndex`, not the furthest-read
    /// marker: status can say "in progress" for a chapter the user has read
    /// into and then scrubbed back out of.
    nonisolated static func startingWordIndex(
        forChapterAt index: Int,
        chapters: [Chapter],
        totalWordCount: Int,
        currentWordIndex: Int
    ) -> Int {
        let (start, end) = chapterBounds(at: index, chapters: chapters, totalWordCount: totalWordCount)
        if currentWordIndex > start && currentWordIndex < end - 1 {
            return currentWordIndex
        }
        return start
    }

    /// Chapter completion state, judged against the furthest position ever
    /// reached so navigating backward doesn't mark finished chapters
    /// un-finished.
    nonisolated static func chapterStatus(
        at index: Int,
        chapters: [Chapter],
        totalWordCount: Int,
        furthestWordIndex: Int
    ) -> ChapterStatus {
        let (start, end) = chapterBounds(at: index, chapters: chapters, totalWordCount: totalWordCount)
        if furthestWordIndex >= end - 1 {
            return .completed
        } else if furthestWordIndex > start {
            return .inProgress
        }
        return .notStarted
    }
}
