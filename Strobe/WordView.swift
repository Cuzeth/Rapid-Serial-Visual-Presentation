import SwiftUI
import UIKit

// MARK: - Word view

struct WordView: View {
    let word: String
    let fontSize: CGFloat
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
    }

    private var redIndex: Int {
        // Collect indices of letter characters only (skip punctuation like apostrophes)
        let letterIndices = word.enumerated().compactMap { offset, char in
            char.isLetter ? offset : nil
        }

        guard !letterIndices.isEmpty else {
            // Pure punctuation fallback
            return word.count / 2
        }

        let letterCount = letterIndices.count
        let letterPos = letterCount <= 1 ? 0 : max(1, letterCount / 2)
        return letterIndices[letterPos]
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
        GeometryReader { geo in
            let displayFontSize = fittedFontSize(for: geo.size.width * 0.8)

            ZStack {
                ZStack {
                    // Subtle vertical guide line at the anchor position
                    Rectangle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 1.5, height: displayFontSize * 1.6)

                    // Word with ORP-anchored red letter
                    HStack(spacing: 0) {
                        Text(before)
                            .foregroundStyle(.primary)

                        Text(anchor)
                            .foregroundStyle(.red)
                            .fontWeight(.bold)

                        Text(after)
                            .foregroundStyle(.primary)
                    }
                    .font(readerFont.regularFont(size: displayFontSize))
                    // Shift the entire word so the red ORP letter sits exactly on center.
                    .offset(x: orpAnchorOffset(fontSize: displayFontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .padding(.horizontal, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: max(120, fontSize * 2.3))
    }

    private func fittedFontSize(for availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return fontSize }
        let estimatedCharacterWidth = fontSize * 0.62
        let estimatedWordWidth = CGFloat(max(word.count, 1)) * estimatedCharacterWidth
        guard estimatedWordWidth > availableWidth else { return fontSize }

        let scaled = fontSize * (availableWidth / estimatedWordWidth)
        return max(fontSize * 0.58, scaled)
    }

    private func orpAnchorOffset(fontSize: CGFloat) -> CGFloat {
        let beforeWidth = textWidth(before, fontSize: fontSize)
        let afterWidth = textWidth(after, fontSize: fontSize)
        return (afterWidth - beforeWidth) / 2
    }

    private func textWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }

        let font = readerFont.uiFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}
