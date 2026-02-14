import SwiftUI

// MARK: - Custom alignment for ORP anchor

extension HorizontalAlignment {
    private enum ORPAnchor: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.center]
        }
    }

    static let orpAnchor = HorizontalAlignment(ORPAnchor.self)
}

// MARK: - Word view

struct WordView: View {
    let word: String
    let fontSize: CGFloat

    private var redIndex: Int {
        if word.count <= 1 { return 0 }
        return max(1, word.count / 2)
    }

    private var before: String {
        guard !word.isEmpty else { return "" }
        return String(word.prefix(redIndex))
    }

    private var anchor: String {
        guard redIndex < word.count else { return "" }
        return String(word[word.index(word.startIndex, offsetBy: redIndex)])
    }

    private var after: String {
        guard redIndex + 1 < word.count else { return "" }
        return String(word.suffix(word.count - redIndex - 1))
    }

    var body: some View {
        ZStack {
            // Subtle vertical guide line at the anchor position
            Rectangle()
                .fill(Color.red.opacity(0.12))
                .frame(width: 1.5, height: fontSize * 1.6)

            // Word with ORP-anchored red letter
            HStack(spacing: 0) {
                Text(before)
                    .foregroundStyle(.primary)

                Text(anchor)
                    .foregroundStyle(.red)
                    .fontWeight(.bold)
                    .alignmentGuide(.orpAnchor) { d in
                        d[HorizontalAlignment.center]
                    }

                Text(after)
                    .foregroundStyle(.primary)
            }
            .font(.custom("JetBrainsMono-Regular", size: fontSize))
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: .orpAnchor, vertical: .center))
    }
}
