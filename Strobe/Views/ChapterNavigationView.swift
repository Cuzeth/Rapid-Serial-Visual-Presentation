import SwiftUI

/// Chapter navigation bar for the reader: previous/next chapter buttons and
/// a tappable current-chapter title that opens a jump picker.
///
/// A separate view so its dependency on `engine.currentIndex` (via the
/// current-chapter computation) invalidates only this small subtree on every
/// word tick instead of the whole reader.
struct ChapterNavigationView: View {
    let chapters: [Chapter]
    let engine: RSVPEngine
    @Binding var showChapterPicker: Bool
    /// Called after any chapter jump — the reader clears its completion overlay.
    var onNavigate: () -> Void = {}

    /// A "previous chapter" tap within this many words of the chapter start
    /// goes to the prior chapter instead of restarting the current one.
    private static let nearChapterStartThreshold = 2

    /// Index of the chapter containing the current word (largest chapter whose
    /// `wordIndex` is at or before `engine.currentIndex`). Nil if no chapters.
    private var currentChapterIndex: Int? {
        guard !chapters.isEmpty else { return nil }
        var result = 0
        for (i, chapter) in chapters.enumerated() {
            if chapter.wordIndex <= engine.currentIndex {
                result = i
            } else {
                break
            }
        }
        return result
    }

    private var canGoPreviousChapter: Bool {
        guard let idx = currentChapterIndex else { return false }
        return engine.currentIndex > chapters[idx].wordIndex + Self.nearChapterStartThreshold || idx > 0
    }

    private var canGoNextChapter: Bool {
        guard let idx = currentChapterIndex else { return false }
        return idx + 1 < chapters.count
    }

    var body: some View {
        let idx = currentChapterIndex ?? 0
        let title = chapters.indices.contains(idx) ? chapters[idx].title : ""

        HStack(spacing: 10) {
            Button {
                jumpToPreviousChapter()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(canGoPreviousChapter ? StrobeTheme.textSecondary : StrobeTheme.textSecondary.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .background(StrobeTheme.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoPreviousChapter)
            .accessibilityLabel("Previous chapter")

            Button {
                showChapterPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(StrobeTheme.bodyFont(size: 13, bold: true))
                        .foregroundStyle(StrobeTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(StrobeTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(StrobeTheme.surface)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showChapterPicker, arrowEdge: .bottom) {
                chapterPickerContent
            }
            .accessibilityLabel("Chapter")
            .accessibilityValue(title)
            .accessibilityHint("Pick a chapter to jump to")

            Button {
                jumpToNextChapter()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(canGoNextChapter ? StrobeTheme.textSecondary : StrobeTheme.textSecondary.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .background(StrobeTheme.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoNextChapter)
            .accessibilityLabel("Next chapter")
        }
    }

    @ViewBuilder
    private var chapterPickerContent: some View {
        let activeIndex = currentChapterIndex

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { i, chapter in
                        Button {
                            showChapterPicker = false
                            jumpToChapter(i)
                        } label: {
                            HStack(spacing: 12) {
                                Text(chapter.title)
                                    .font(StrobeTheme.bodyFont(size: 15, bold: i == activeIndex))
                                    .foregroundStyle(i == activeIndex ? StrobeTheme.accent : StrobeTheme.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if i == activeIndex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(StrobeTheme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(chapter.id)

                        if i < chapters.count - 1 {
                            Divider()
                                .background(StrobeTheme.surface)
                                .padding(.leading, 16)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(StrobeTheme.background)
            .onAppear {
                guard let idx = activeIndex, chapters.indices.contains(idx) else { return }
                // Defer one runloop so LazyVStack rows are registered before we scroll.
                DispatchQueue.main.async {
                    proxy.scrollTo(chapters[idx].id, anchor: .center)
                }
            }
        }
        .frame(idealWidth: 360, idealHeight: 480)
        .presentationDetents([.medium, .large])
    }

    private func jumpToChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        if engine.isPlaying { engine.pause() }
        engine.seek(to: chapters[index].wordIndex)
        HapticManager.shared.scrubBoundary()
        onNavigate()
    }

    private func jumpToPreviousChapter() {
        guard let idx = currentChapterIndex else { return }
        let chapterStart = chapters[idx].wordIndex
        if engine.currentIndex > chapterStart + Self.nearChapterStartThreshold {
            jumpToChapter(idx)
        } else if idx > 0 {
            jumpToChapter(idx - 1)
        }
    }

    private func jumpToNextChapter() {
        guard let idx = currentChapterIndex, idx + 1 < chapters.count else { return }
        jumpToChapter(idx + 1)
    }
}
