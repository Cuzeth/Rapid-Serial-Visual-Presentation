import SwiftUI

/// Chooses and sizes the faded previous and next words shown around the
/// current word.
nonisolated enum ContextWords {
    struct Neighbors: Equatable {
        let previous: String?
        let next: String?
    }

    /// The words on either side of `index`: nil past either end of the
    /// document, and on both sides for an index outside it.
    static func neighbors(of index: Int, in words: [String]) -> Neighbors {
        guard words.indices.contains(index) else {
            return Neighbors(previous: nil, next: nil)
        }
        return Neighbors(
            previous: index > 0 ? words[index - 1] : nil,
            next: index + 1 < words.count ? words[index + 1] : nil
        )
    }

    struct Metrics: Equatable {
        let fontSize: CGFloat
        /// Distance from the word's center to the center of either slot.
        let offset: CGFloat

        /// Height of the slot a context word is centered in.
        var slotHeight: CGFloat { fontSize * ContextWords.slotHeightRatio }

        /// Distance from the word's center to the outer edge of either slot.
        var reach: CGFloat { offset + slotHeight / 2 }
    }

    /// Context font size as a fraction of the word's.
    static let fontSizeRatio: CGFloat = 0.45
    /// Keeps the context legible around the smallest word sizes.
    static let preferredMinimumFontSize: CGFloat = 14
    /// Below this the context hides rather than shrinking further.
    static let minimumFontSize: CGFloat = 12
    /// Slot height as a multiple of the context font size: room for every
    /// reader font's line box and for marks that overhang it, such as the
    /// dots under Arabic letters. Taller stacks, such as Arabic vowel marks
    /// and Thai tone marks, can reach into the gap or the bar margin.
    static let slotHeightRatio: CGFloat = 1.5
    /// Space between the end of the word's guide line and either slot, as a
    /// fraction of the word's font size.
    static let gapRatio: CGFloat = 0.1
    /// Space kept between either slot and a bar.
    static let barMargin: CGFloat = 8
    /// Space between the next word's slot and the top of the hold-speed
    /// readout below it.
    static let speedReadoutGap: CGFloat = 8

    /// The context font size wherever there is room for it.
    static func preferredFontSize(wordFontSize: CGFloat) -> CGFloat {
        max(preferredMinimumFontSize, wordFontSize * fontSizeRatio)
    }

    /// Distance from the word's center to the inner edge of either slot,
    /// just past the end of the word's guide line.
    static func innerEdge(wordFontSize: CGFloat) -> CGFloat {
        wordFontSize * (WordView.guideLineHeightRatio / 2 + gapRatio)
    }

    /// Sizes the context around a word set at `wordFontSize`, given how far
    /// the room around the word's center reaches before a bar.
    ///
    /// Depends on settings and layout only, never on the words, so the
    /// context holds still from word to word. Where the preferred size
    /// doesn't fit, the context shrinks; below `minimumFontSize` there is
    /// none (nil).
    static func metrics(wordFontSize: CGFloat, clearHalfHeight: CGFloat) -> Metrics? {
        let inner = innerEdge(wordFontSize: wordFontSize)
        let fitting = (clearHalfHeight - barMargin - inner) / slotHeightRatio
        let fontSize = min(preferredFontSize(wordFontSize: wordFontSize), fitting)
        guard fontSize >= minimumFontSize else { return nil }
        return Metrics(fontSize: fontSize, offset: inner + fontSize * slotHeightRatio / 2)
    }
}

/// The previous word above the current one and the next word below it,
/// faded and centered on the anchor's column. Opt-in from Settings.
///
/// Above and below because ORP centering moves the word's edges every tick:
/// a word beside it would jump with them, or be run into by long words.
///
/// Takes the `fixationSurround` stage role: the height it is proposed is
/// the room the bars leave around the word, and the context shrinks or
/// hides to fit it.
struct ContextWordsView: View {
    let engine: RSVPEngine
    /// The reader's text size setting; a long word may display smaller.
    let fontSize: CGFloat
    let isEnabled: Bool

    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue
    @AppStorage(ReaderTextTone.storageKey) private var readerTextToneSelection = ReaderTextTone.defaultValue.rawValue

    var body: some View {
        GeometryReader { geo in
            if isEnabled,
               let metrics = ContextWords.metrics(wordFontSize: fontSize, clearHalfHeight: geo.size.height / 2) {
                ContextWordPair(
                    engine: engine,
                    metrics: metrics,
                    font: ReaderFont.resolve(readerFontSelection),
                    tone: ReaderTextTone.resolve(readerTextToneSelection)
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        // The hold-to-read gesture layer lies underneath.
        .allowsHitTesting(false)
        // The current word is the reader's one VoiceOver element.
        .accessibilityHidden(true)
    }
}

/// Isolates the per-tick `engine.currentIndex` read: two array lookups and
/// two single-line texts, nothing measured.
private struct ContextWordPair: View {
    let engine: RSVPEngine
    let metrics: ContextWords.Metrics
    let font: ReaderFont
    let tone: ReaderTextTone

    var body: some View {
        let neighbors = ContextWords.neighbors(of: engine.currentIndex, in: engine.words)

        ZStack {
            ContextWordText(word: neighbors.previous ?? "", metrics: metrics, font: font, tone: tone)
                .equatable()
                .offset(y: -metrics.offset)

            ContextWordText(word: neighbors.next ?? "", metrics: metrics, font: font, tone: tone)
                .equatable()
                .offset(y: metrics.offset)
        }
        // A chapter announcement takes the word's place and runs taller than
        // it, and a sentence break empties the screen; the context leaves and
        // returns with the word.
        .opacity(engine.chapterAnnouncement == nil && !engine.isInSentenceBreak ? 1 : 0)
        // The engine can move in an animated transaction, such as a scrub
        // that pauses playback and so runs the stage's play/pause fade.
        // Nothing here may animate between words.
        .transaction { $0.animation = nil }
    }
}

/// One context word. A single `Text`, so shaping and glyph order hold in
/// every script; long words shrink, then truncate, rather than wrap.
private struct ContextWordText: View, Equatable {
    let word: String
    let metrics: ContextWords.Metrics
    let font: ReaderFont
    let tone: ReaderTextTone

    var body: some View {
        Text(word)
            .font(font.regularFont(size: metrics.fontSize, relativeTo: nil))
            .foregroundStyle(tone.fadedTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: metrics.slotHeight)
    }
}
