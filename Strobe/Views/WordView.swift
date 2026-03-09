import SwiftUI
import UIKit

// MARK: - Word view

/// Displays a single word with Optimal Recognition Point (ORP) highlighting.
///
/// The ORP anchor letter (approximately at the 1/3 position of the word's letters)
/// is displayed in red and centered on screen. The rest of the word is offset
/// so the reader's eye stays fixed at the center. Font size scales down
/// automatically for very long words.
///
/// Uses `AttributedString` to render the word as a single text run, which
/// preserves cursive shaping for Arabic and correct glyph order for all scripts.
struct WordView: View {
    let word: String
    let fontSize: CGFloat
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
    }

    /// The character index of the ORP anchor letter (the red letter).
    /// Calculated from letter-only positions, skipping punctuation.
    /// For short CJK words (≤3 characters), centers the anchor instead.
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

        // Short CJK words look better with the anchor centered rather than
        // at the 1/3 position used for longer Latin words.
        if letterCount <= 3, word.unicodeScalars.contains(where: { v in
            let c = v.value
            return (c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)
                || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0x20000 && c <= 0x2A6DF)
        }) {
            return letterIndices[letterCount / 2]
        }

        let letterPos = letterCount <= 1 ? 0 : max(1, letterCount / 2)
        return letterIndices[letterPos]
    }

    /// Whether the word contains Arabic script. Arabic is cursive — changing
    /// the font weight on individual characters breaks glyph connections,
    /// so only color is changed for the anchor letter.
    private var isArabic: Bool {
        word.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (v >= 0x0600 && v <= 0x06FF)
                || (v >= 0x0750 && v <= 0x077F)
                || (v >= 0x08A0 && v <= 0x08FF)
                || (v >= 0xFB50 && v <= 0xFDFF)
                || (v >= 0xFE70 && v <= 0xFEFF)
        }
    }

    /// Builds an `AttributedString` with the anchor letter colored red.
    /// For non-Arabic scripts the anchor is also bolded. For Arabic, only
    /// color is changed to avoid breaking cursive glyph connections.
    private func attributedWord(fontSize: CGFloat) -> AttributedString {
        var attributed = AttributedString(word)
        attributed.font = readerFont.regularFont(size: fontSize)
        attributed.foregroundColor = .primary

        guard redIndex < word.count else { return attributed }

        let start = word.index(word.startIndex, offsetBy: redIndex)
        let end = word.index(after: start)
        if let attrStart = AttributedString.Index(start, within: attributed),
           let attrEnd = AttributedString.Index(end, within: attributed) {
            attributed[attrStart..<attrEnd].foregroundColor = .red
            // Bold breaks Arabic cursive shaping — only apply for non-Arabic.
            if !isArabic {
                attributed[attrStart..<attrEnd].font = readerFont.boldFont(size: fontSize)
            }
        }

        return attributed
    }

    private var before: String {
        guard !word.isEmpty else { return "" }
        return String(word.prefix(redIndex))
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

                    Text(attributedWord(fontSize: displayFontSize))
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

    /// Scales the font size down if the word would exceed the available width.
    private func fittedFontSize(for availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return fontSize }
        let estimatedCharacterWidth = fontSize * 0.62
        let estimatedWordWidth = CGFloat(max(word.count, 1)) * estimatedCharacterWidth
        guard estimatedWordWidth > availableWidth else { return fontSize }

        let scaled = fontSize * (availableWidth / estimatedWordWidth)
        return max(fontSize * 0.58, scaled)
    }

    /// Calculates the horizontal offset to center the ORP anchor letter on screen.
    /// For Arabic the visual layout is mirrored, so the offset is negated.
    private func orpAnchorOffset(fontSize: CGFloat) -> CGFloat {
        let beforeWidth = textWidth(before, fontSize: fontSize)
        let afterWidth = textWidth(after, fontSize: fontSize)
        let offset = (afterWidth - beforeWidth) / 2
        return isArabic ? -offset : offset
    }

    /// Measures the rendered width of a text string using the current reader font.
    private func textWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }

        let font = readerFont.uiFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}
