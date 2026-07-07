import Foundation

/// Drives the word-by-word Rapid Serial Visual Presentation playback.
///
/// Manages a timer that advances through the word array at the configured
/// words-per-minute rate. Supports smart timing (longer display for long words)
/// and sentence pauses (extra delay at sentence-ending punctuation).
///
/// Conforms to `@Observable` so SwiftUI views automatically update when
/// `currentIndex`, `isPlaying`, or settings change.
@Observable
final class RSVPEngine {

    /// The full array of words to display.
    private(set) var words: [String]
    /// The index of the word currently being displayed.
    private(set) var currentIndex: Int
    /// Whether playback is currently running.
    private(set) var isPlaying: Bool = false

    /// The target reading speed. Changing this during playback reschedules the timer.
    var wordsPerMinute: Int {
        didSet { onPlaybackSettingChanged() }
    }

    /// Temporary speed while the hold-to-read finger drags vertically.
    /// Cleared on `pause()` so every hold starts at `wordsPerMinute`.
    var wpmOverride: Int? {
        didSet { onPlaybackSettingChanged() }
    }

    /// The speed playback actually runs at: the hold override if one is
    /// active, otherwise the configured speed.
    var effectiveWordsPerMinute: Int {
        wpmOverride ?? wordsPerMinute
    }

    /// When enabled, longer words are displayed for proportionally more time.
    var smartTimingEnabled: Bool {
        didSet { onPlaybackSettingChanged() }
    }

    /// When enabled, words ending with `.`, `!`, or `?` receive extra display time.
    var sentencePauseEnabled: Bool {
        didSet { onPlaybackSettingChanged() }
    }

    /// Percentage points added to the display interval per letter when smart timing is on.
    /// E.g. 4.0 means a 10-letter word gets +40% duration (1.4× base interval).
    var smartTimingPercentPerLetter: Double {
        didSet { onPlaybackSettingChanged() }
    }

    /// Multiplier applied to the interval at sentence-ending punctuation when sentence pauses are on.
    var sentencePauseMultiplier: Double {
        didSet { onPlaybackSettingChanged() }
    }

    /// When enabled, per-word display time scales with cognitive complexity.
    var complexityTimingEnabled: Bool {
        didSet { onPlaybackSettingChanged() }
    }

    /// How strongly complexity affects timing (0.0 = no effect, 1.0 = full effect).
    var complexityIntensity: Double {
        didSet { onPlaybackSettingChanged() }
    }

    /// Pre-computed complexity scores, parallel to the `words` array. Nil for legacy documents.
    private(set) var complexityScores: [Float]?

    /// The word at the current playback position, or an empty string if out of bounds.
    var currentWord: String {
        guard currentIndex >= 0, currentIndex < words.count else { return "" }
        return words[currentIndex]
    }

    /// Whether the playback position is at the last word. `false` when the
    /// word array is empty (e.g. still loading) so an unloaded engine never
    /// reports a finished document.
    var isAtEnd: Bool {
        guard !words.isEmpty else { return false }
        return currentIndex >= words.count - 1
    }

    /// Playback progress as a value from 0.0 to 1.0.
    var progress: Double {
        guard words.count > 1 else { return isAtEnd ? 1 : 0 }
        return Double(currentIndex) / Double(words.count - 1)
    }

    private var timerSource: DispatchSourceTimer?
    /// The deadline the timer is currently scheduled for. Advancing anchors
    /// the next tick to this value (not `.now()`) so per-tick handler latency
    /// doesn't accumulate into drift at high WPM.
    private var scheduledDeadline: DispatchTime?

    private var baseInterval: TimeInterval {
        60.0 / Double(max(1, effectiveWordsPerMinute))
    }

    init(
        words: [String],
        currentIndex: Int = 0,
        wordsPerMinute: Int = 300,
        smartTimingEnabled: Bool = false,
        sentencePauseEnabled: Bool = false,
        smartTimingPercentPerLetter: Double = 4.0,
        sentencePauseMultiplier: Double = 1.5,
        complexityTimingEnabled: Bool = false,
        complexityIntensity: Double = 0.5,
        complexityScores: [Float]? = nil
    ) {
        self.words = words
        self.currentIndex = words.isEmpty ? 0 : max(0, min(currentIndex, words.count - 1))
        self.wordsPerMinute = wordsPerMinute
        self.smartTimingEnabled = smartTimingEnabled
        self.sentencePauseEnabled = sentencePauseEnabled
        self.smartTimingPercentPerLetter = smartTimingPercentPerLetter
        self.sentencePauseMultiplier = sentencePauseMultiplier
        self.complexityTimingEnabled = complexityTimingEnabled
        self.complexityIntensity = complexityIntensity
        self.complexityScores = complexityScores
    }

    /// Replaces the word array, position, and complexity scores after
    /// asynchronous loading. The position is clamped to the new bounds.
    /// Intended to be called once, while paused, on an engine created empty.
    func load(words: [String], currentIndex: Int, complexityScores: [Float]?) {
        self.words = words
        self.complexityScores = complexityScores
        self.currentIndex = words.isEmpty ? 0 : max(0, min(currentIndex, words.count - 1))
    }

    /// Replaces the complexity scores (e.g. after a background backfill for a
    /// legacy document) without touching playback state.
    func updateComplexityScores(_ scores: [Float]?) {
        complexityScores = scores
    }

    /// Starts playback from the current position. No-op if already playing,
    /// at the end, or if no words are loaded.
    func play() {
        guard !isPlaying, !words.isEmpty, !isAtEnd else { return }
        isPlaying = true
        scheduleNextWord()
    }

    /// Stops playback, invalidates the timer, and discards any hold-to-read
    /// speed override so the next play resumes at the configured speed.
    func pause() {
        isPlaying = false
        stopTimer()
        wpmOverride = nil
    }

    /// Jumps to a specific word index, clamped to valid bounds.
    func seek(to index: Int) {
        currentIndex = max(0, min(index, words.count - 1))
    }

    /// Moves the position by `delta` words. Returns `true` if the move was clamped (hit a boundary).
    @discardableResult
    func scrub(by delta: Int) -> Bool {
        let target = currentIndex + delta
        seek(to: target)
        return currentIndex != target
    }

    /// Resets playback to the beginning of the word array.
    func restart() {
        seek(to: 0)
    }

    private func onPlaybackSettingChanged() {
        guard isPlaying else { return }
        guard let source = timerSource, let scheduled = scheduledDeadline else {
            scheduleNextWord()
            return
        }
        // Only ever pull the current word's deadline earlier. Pushing it out
        // would let a continuously dragged settings slider (each didSet lands
        // here) stall playback on one word indefinitely.
        let candidate = DispatchTime.now() + nextInterval()
        if candidate < scheduled {
            scheduledDeadline = candidate
            source.schedule(deadline: candidate)
        }
    }

    /// Schedules (or reschedules) the single reusable timer for the next word
    /// advance. When `anchor` is set (the previous tick's deadline), the next
    /// deadline is measured from it so scheduling latency doesn't compound —
    /// clamped to now so a long stall (app suspension) can't cause a burst of
    /// catch-up ticks.
    private func scheduleNextWord(anchor: DispatchTime? = nil) {
        guard isPlaying else { return }
        if timerSource == nil {
            let source = DispatchSource.makeTimerSource(queue: .main)
            source.setEventHandler { [weak self] in
                self?.advance()
            }
            source.resume()
            timerSource = source
        }
        let now = DispatchTime.now()
        let deadline = max((anchor ?? now) + nextInterval(), now)
        scheduledDeadline = deadline
        timerSource?.schedule(deadline: deadline)
    }

    private func stopTimer() {
        guard let source = timerSource else { return }
        source.setEventHandler {}
        source.cancel()
        timerSource = nil
        scheduledDeadline = nil
    }

    private func advance() {
        guard isPlaying else { return }
        if currentIndex < words.count - 1 {
            let previousDeadline = scheduledDeadline
            currentIndex += 1
            scheduleNextWord(anchor: previousDeadline)
        } else {
            pause()
        }
    }

    private func nextInterval() -> TimeInterval {
        var interval = baseInterval

        if smartTimingEnabled {
            interval *= Self.smartTimingMultiplier(for: currentWord, percentPerLetter: smartTimingPercentPerLetter)
        }

        if sentencePauseEnabled && Self.endsWithSentencePunctuation(currentWord) {
            interval *= sentencePauseMultiplier
        }

        if complexityTimingEnabled, let scores = complexityScores,
           currentIndex < scores.count {
            let score = Double(scores[currentIndex])
            interval *= Self.complexityMultiplier(score: score, intensity: complexityIntensity)
        }

        return interval
    }

    /// Maps a complexity score (0.0–1.0) and intensity (0.0–1.0) to a timing multiplier.
    ///
    /// At score 0.0 (trivial word) and full intensity: 0.7× (30% faster).
    /// At score 0.5 (average word): 1.0× (no change).
    /// At score 1.0 (complex word) and full intensity: 1.6× (60% slower).
    /// At zero intensity, the multiplier is always 1.0.
    nonisolated static func complexityMultiplier(score: Double, intensity: Double) -> Double {
        1.0 + (score - 0.5) * 1.2 * intensity
    }

    /// Returns a timing multiplier based on word length.
    /// Each letter contributes `percentPerLetter`% to the interval increase.
    /// E.g. at 4%, an 8-letter word yields a 1.32× multiplier.
    /// Trailing punctuation (commas, etc.) adds a fixed 0.2 bonus when `percentPerLetter > 0`.
    nonisolated static func smartTimingMultiplier(for word: String, percentPerLetter: Double = 4.0) -> Double {
        let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
        let letterCount = trimmed.count

        var multiplier = 1.0 + Double(letterCount) * (percentPerLetter / 100.0)

        if percentPerLetter > 0, hasTrailingPunctuation(word) {
            multiplier += 0.2
        }

        return multiplier
    }

    /// Maps a hold-to-read vertical drag to a temporary WPM. Movement within
    /// ±15pt of the touch-down point changes nothing; beyond that dead zone,
    /// each point is worth 2.5 WPM (up = faster), measured from the dead-zone
    /// edge, snapped to 10-WPM steps and clamped to the 100–1000 slider range.
    nonisolated static func holdSpeedWPM(baseWPM: Int, verticalTranslation: Double) -> Int {
        let deadZone = 15.0
        let wpmPerPoint = 2.5
        let magnitude = abs(verticalTranslation)
        guard magnitude > deadZone else { return baseWPM }
        let delta = (magnitude - deadZone) * wpmPerPoint * (verticalTranslation < 0 ? 1 : -1)
        let snapped = ((Double(baseWPM) + delta) / 10).rounded() * 10
        return Int(min(1000, max(100, snapped)))
    }

    nonisolated private static func hasTrailingPunctuation(_ word: String) -> Bool {
        guard let last = word.unicodeScalars.last else { return false }
        return CharacterSet.punctuationCharacters.contains(last)
    }

    nonisolated private static let sentenceEnders: Set<Character> = [
        ".", "!", "?",       // Latin
        "\u{3002}",          // 。 CJK full stop
        "\u{FF01}",          // ！ fullwidth exclamation
        "\u{FF1F}",          // ？ fullwidth question mark
        "\u{061F}",          // ؟ Arabic question mark
        "\u{06D4}",          // ۔ Arabic/Urdu full stop
    ]

    /// Characters that may wrap sentence-ending punctuation (closing quotes, parens, brackets).
    nonisolated private static let closingDelimiters: Set<Character> = [
        "\"", "'", "\u{201D}", "\u{2019}", // " ' " '
        ")", "]", "\u{00BB}",              // ) ] »
    ]

    /// Returns `true` if the word ends with sentence-terminating punctuation,
    /// looking past any trailing closing delimiters (quotes, parentheses, brackets).
    nonisolated static func endsWithSentencePunctuation(_ word: String) -> Bool {
        for char in word.reversed() {
            if sentenceEnders.contains(char) { return true }
            if !closingDelimiters.contains(char) { return false }
        }
        return false
    }

    deinit {
        stopTimer()
    }
}
