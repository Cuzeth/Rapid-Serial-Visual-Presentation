import SwiftUI

struct DocumentRow: View {
    let document: Document
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title)
                .font(readerFont.regularFont(size: 16))
                .lineLimit(1)

            HStack(spacing: 6) {
                Text("\(document.wordCount) words")

                Text("\u{00B7}")

                Text("\(document.wordsPerMinute) WPM")

                if document.currentWordIndex > 0 {
                    Text("\u{00B7}")
                    Text("\(Int(document.progress * 100))%")
                }
            }
            .font(readerFont.regularFont(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
