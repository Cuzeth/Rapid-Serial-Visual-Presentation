import SwiftUI
import SwiftData

struct ChapterListView: View {
    @Bindable var document: Document
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
    }

    var body: some View {
        List {
            Section {
                NavigationLink(destination: ReaderView(document: document)) {
                    fullDocumentRow
                }
            }

            Section {
                ForEach(Array(document.chapters.enumerated()), id: \.element.id) { index, chapter in
                    NavigationLink(destination: ReaderView(document: document, startingWordIndex: chapter.wordIndex)) {
                        chapterRow(chapter: chapter, index: index)
                    }
                }
            } header: {
                Text("\(document.chapters.count) chapters")
                    .font(readerFont.regularFont(size: 12))
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Full document row

    private var fullDocumentRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Full Document")
                .font(readerFont.regularFont(size: 16))

            HStack(spacing: 6) {
                Text("\(document.wordCount) words")
                Text("\u{00B7}")
                Text("\(Int(document.progress * 100))%")
            }
            .font(readerFont.regularFont(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Chapter row

    private func chapterRow(chapter: Chapter, index: Int) -> some View {
        let wordCount = chapterWordCount(at: index)
        let status = chapterStatus(at: index)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(chapter.title)
                    .font(readerFont.regularFont(size: 16))
                    .lineLimit(2)

                Spacer()

                switch status {
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))
                case .inProgress:
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14))
                case .notStarted:
                    EmptyView()
                }
            }

            Text("\(wordCount) words")
                .font(readerFont.regularFont(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
