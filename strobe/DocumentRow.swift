import SwiftUI

struct DocumentRow: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title)
                .font(.custom("JetBrainsMono-Regular", size: 16))
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
            .font(.custom("JetBrainsMono-Regular", size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
