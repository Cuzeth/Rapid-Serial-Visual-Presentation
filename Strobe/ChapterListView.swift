import SwiftUI
import SwiftData

struct ChapterListView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var document: Document
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
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
                            NavigationLink(destination: ReaderView(document: document)) {
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
                                    NavigationLink(destination: ReaderView(document: document, startingWordIndex: chapter.wordIndex)) {
                                        chapterRow(chapter: chapter, index: index)
                                    }
                                    .buttonStyle(StrobeCardButtonStyle())
                                }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(StrobeTheme.textSecondary)
                    .padding(12)
                    .background(StrobeTheme.surface)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(readerFont.boldFont(size: 20))
                    .foregroundStyle(StrobeTheme.textPrimary)
                    .lineLimit(1)
                
                Text("\(document.chapters.count) chapters")
                    .font(readerFont.regularFont(size: 14))
                    .foregroundStyle(StrobeTheme.textSecondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(StrobeTheme.background.opacity(0.8))
    }

    // MARK: - Full document row

    private var fullDocumentRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Read Full Document")
                    .font(readerFont.boldFont(size: 18))
                    .foregroundStyle(StrobeTheme.textPrimary)

                HStack(spacing: 6) {
                    Text("\(document.wordCount) words")
                    Text("•")
                    Text("\(Int(document.progress * 100))% complete")
                }
                .font(readerFont.regularFont(size: 14))
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
                    .font(readerFont.boldFont(size: 16))
                    .foregroundStyle(status == .completed ? StrobeTheme.textSecondary : StrobeTheme.textPrimary)
                    .lineLimit(2)

                Text("\(wordCount) words")
                    .font(readerFont.regularFont(size: 12))
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

    private enum ChapterStatus {
        case notStarted, inProgress, completed
    }

    private func chapterWordCount(at index: Int) -> Int {
        let chapters = document.chapters
        let start = chapters[index].wordIndex
        let end = index + 1 < chapters.count
            ? chapters[index + 1].wordIndex
            : document.wordCount
        return max(0, end - start)
    }

    private func chapterStatus(at index: Int) -> ChapterStatus {
        let chapters = document.chapters
        let start = chapters[index].wordIndex
        let end = index + 1 < chapters.count
            ? chapters[index + 1].wordIndex
            : document.wordCount
        let current = document.currentWordIndex

        if current >= end - 1 {
            return .completed
        } else if current > start {
            return .inProgress
        }
        return .notStarted
    }
}
