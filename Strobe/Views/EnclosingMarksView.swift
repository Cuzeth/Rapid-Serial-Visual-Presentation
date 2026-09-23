import SwiftUI

/// Sizes and places the opening marks kept above the word.
nonisolated enum EnclosingMarksLayout {
    struct Metrics: Equatable {
        let fontSize: CGFloat
        /// Distance from the word's center up to the center of the marks'
        /// slot.
        let offset: CGFloat

        /// Height of the slot the marks are centered in.
        var slotHeight: CGFloat { fontSize * ContextWords.slotHeightRatio }

        /// Distance from the word's center to the top of the marks' slot.
        var reach: CGFloat { offset + slotHeight / 2 }
    }

    /// Mark size as a fraction of the word's. Larger than the context words'
    /// ratio: a lone mark carries far less ink than a word.
    static let fontSizeRatio: CGFloat = 0.6
    /// Space between the previous word's slot and the marks' slot, as a
    /// fraction of the word's font size.
    static let gapRatio: CGFloat = ContextWords.gapRatio

    /// The marks' font size wherever there is room for it.
    static func preferredFontSize(wordFontSize: CGFloat) -> CGFloat {
        max(ContextWords.preferredMinimumFontSize, wordFontSize * fontSizeRatio)
    }

    /// Sizes the marks' slot for a word set at `wordFontSize`, given how far
    /// the room around the word's center reaches before a bar and the context
    /// words shown in it, if any.
    ///
    /// The slot sits right above the word, or above the previous word while
    /// context words show. It depends on settings and layout only, never on
    /// the words, so the marks hold still from word to word. Where the
    /// preferred size doesn't fit, the marks shrink; below
    /// `ContextWords.minimumFontSize` there are none (nil).
    static func metrics(
        wordFontSize: CGFloat,
        clearHalfHeight: CGFloat,
        contextWords: ContextWords.Metrics?
    ) -> Metrics? {
        let inner = contextWords.map { $0.reach + wordFontSize * gapRatio }
            ?? ContextWords.innerEdge(wordFontSize: wordFontSize)
        let fitting = (clearHalfHeight - ContextWords.barMargin - inner) / ContextWords.slotHeightRatio
        let fontSize = min(preferredFontSize(wordFontSize: wordFontSize), fitting)
        guard fontSize >= ContextWords.minimumFontSize else { return nil }
        return Metrics(fontSize: fontSize, offset: inner + fontSize * ContextWords.slotHeightRatio / 2)
    }
}

/// The opening marks of the quotations and parentheses the current word is
/// inside, faded, above it on the anchor's column. Opt-in from Settings.
///
/// Above because nothing else there moves: ORP centering moves the word's
/// left and right edges every tick, so a mark beside it would either jump
/// with them or, at a fixed spot, be run into by long words. The word's line
/// never reaches the slot above it.
///
/// Takes the `fixationSurround` stage role, like the context words: the
/// height it is proposed is the room the bars leave around the word, and the
/// marks shrink or hide to fit it.
struct EnclosingMarksView: View {
    let engine: RSVPEngine
    /// Nil until the document's marks are paired.
    let marks: EnclosingMarks?
    /// The reader's text size setting; a long word may display smaller.
    let fontSize: CGFloat
    let isEnabled: Bool
    let contextWordsEnabled: Bool

    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue
    @AppStorage(ReaderTextTone.storageKey) private var readerTextToneSelection = ReaderTextTone.defaultValue.rawValue

    var body: some View {
        GeometryReader { geo in
            let clearHalfHeight = geo.size.height / 2
            let context = contextWordsEnabled
                ? ContextWords.metrics(wordFontSize: fontSize, clearHalfHeight: clearHalfHeight)
                : nil

            if isEnabled, let marks,
               let metrics = EnclosingMarksLayout.metrics(
                   wordFontSize: fontSize,
                   clearHalfHeight: clearHalfHeight,
                   contextWords: context
               ) {
                EnclosingMarksSlot(
                    engine: engine,
                    marks: marks,
                    metrics: metrics,
                    font: ReaderFont.resolve(readerFontSelection),
                    tone: ReaderTextTone.resolve(readerTextToneSelection)
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        .animation(.easeInOut(duration: 0.2), value: marks != nil)
        // The hold-to-read gesture layer lies underneath.
        .allowsHitTesting(false)
        // The current word is the reader's one VoiceOver element.
        .accessibilityHidden(true)
    }
}

/// Isolates the per-tick `engine.currentIndex` read: one array lookup; the
/// marks below re-render only when they change.
private struct EnclosingMarksSlot: View {
    let engine: RSVPEngine
    let marks: EnclosingMarks
    let metrics: EnclosingMarksLayout.Metrics
    let font: ReaderFont
    let tone: ReaderTextTone

    /// A chapter announcement takes the word's place and runs taller than
    /// it, and a sentence break empties the screen; the marks leave and
    /// return with the word.
    private var isShowingWord: Bool {
        engine.chapterAnnouncement == nil && !engine.isInSentenceBreak
    }

    var body: some View {
        EnclosingMarksText(stack: marks.stack(at: engine.currentIndex), metrics: metrics, font: font, tone: tone)
            .equatable()
            .offset(y: -metrics.offset)
            .opacity(isShowingWord ? 1 : 0)
            // The engine can move in an animated transaction, such as a scrub
            // that pauses playback and so runs the stage's play/pause fade.
            // Nothing here may animate between words.
            .transaction { $0.animation = nil }
    }
}

/// The marks around one word. The outermost stays centered on the anchor's
/// column while inner ones open and close beside it, on the side the text
/// reads toward.
private struct EnclosingMarksText: View, Equatable {
    let stack: EnclosingMarks.Stack
    let metrics: EnclosingMarksLayout.Metrics
    let font: ReaderFont
    let tone: ReaderTextTone

    var body: some View {
        let outermost = stack.marks.first.map(String.init) ?? ""
        let inner = String(stack.marks.dropFirst())
        let rightToLeft = stack.isRightToLeft

        mark(outermost)
            .overlay(alignment: rightToLeft ? .leading : .trailing) {
                mark(inner)
                    .alignmentGuide(rightToLeft ? .leading : .trailing) { d in
                        rightToLeft ? d[.trailing] : d[.leading]
                    }
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.slotHeight)
            // Sides follow the text's direction, not the app's.
            .environment(\.layoutDirection, .leftToRight)
    }

    /// Marks set as the text sets them. The leading direction mark makes
    /// brackets and guillemets mirror in right-to-left text, as they do on
    /// the word, and keeps them unmirrored in left-to-right text whatever the
    /// app's language.
    private func mark(_ marks: String) -> some View {
        Text((stack.isRightToLeft ? "\u{200F}" : "\u{200E}") + marks)
            .font(font.regularFont(size: metrics.fontSize, relativeTo: nil))
            .foregroundStyle(tone.fadedTextColor)
            .lineLimit(1)
            .fixedSize()
    }
}
