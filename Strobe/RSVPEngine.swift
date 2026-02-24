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

    /// The target reading speed. Changing this during playback restarts the timer.
    var wordsPerMinute: Int {
        didSet {
            guard isPlaying else { return }
            restartTimer()
        }
    }

    /// When enabled, longer words are displayed for proportionally more time.
    var smartTimingEnabled: Bool {
        didSet {
            guard isPlaying else { return }
            restartTimer()
        }
    }

    /// When enabled, words ending with `.`, `!`, or `?` receive extra display time.
    var sentencePauseEnabled: Bool {
        didSet {
            guard isPlaying else { return }
            restartTimer()
        }
    }

    /// Percentage points added to the display interval per letter when smart timing is on.
    /// E.g. 4.0 means a 10-letter word gets +40% duration (1.4× base interval).
    var smartTimingPercentPerLetter: Double {
        didSet {
            guard isPlaying else { return }
            restartTimer()
        }
    }

    /// Multiplier applied to the interval at sentence-ending punctuation when sentence pauses are on.
    var sentencePauseMultiplier: Double {
        didSet {
            guard isPlaying else { return }
            restartTimer()
        }
    }

    /// The word at the current playback position, or an empty string if out of bounds.
    var currentWord: String {
        guard currentIndex >= 0, currentIndex < words.count else { return "" }
        return words[currentIndex]
    }

    /// Whether the playback position is at the last word.
    var isAtEnd: Bool { currentIndex >= words.count - 1 }

    /// Playback progress as a value from 0.0 to 1.0.
    var progress: Double {
        guard words.count > 1 else { return isAtEnd ? 1 : 0 }
        return Double(currentIndex) / Double(words.count - 1)
    }

    private var timer: Timer?

    private var baseInterval: TimeInterval {
        60.0 / Double(wordsPerMinute)
    }

    init(
        words: [String],
        currentIndex: Int = 0,
        wordsPerMinute: Int = 300,
        smartTimingEnabled: Bool = false,
        sentencePauseEnabled: Bool = false,
        smartTimingPercentPerLetter: Double = 4.0,
        sentencePauseMultiplier: Double = 1.5
    ) {
        self.words = words
        self.currentIndex = currentIndex
        self.wordsPerMinute = wordsPerMinute
        self.smartTimingEnabled = smartTimingEnabled
        self.sentencePauseEnabled = sentencePauseEnabled
        self.smartTimingPercentPerLetter = smartTimingPercentPerLetter
        self.sentencePauseMultiplier = sentencePauseMultiplier
    }

    /// Starts playback from the current position. No-op if already playing or at end.
    func play() {
        guard !isPlaying, !isAtEnd else { return }
        isPlaying = true
        startTimer()
    }

    /// Stops playback and invalidates the timer.
    func pause() {
        isPlaying = false
        stopTimer()
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

    private func startTimer() {
        guard isPlaying else { return }
        let delay = nextInterval()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.advance()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        if currentIndex < words.count - 1 {
            currentIndex += 1
            if isPlaying {
                startTimer()
            }
        } else {
            pause()
        }
    }

    private func restartTimer() {
        stopTimer()
        startTimer()
    }

    private func nextInterval() -> TimeInterval {
        var interval = baseInterval

        if smartTimingEnabled {
            interval *= Self.smartTimingMultiplier(for: currentWord, percentPerLetter: smartTimingPercentPerLetter)
        }

        if sentencePauseEnabled && Self.endsWithSentencePunctuation(currentWord) {
            interval *= sentencePauseMultiplier
        }

        return interval
    }

    /// Returns a timing multiplier based on word length.
    /// Each letter contributes `percentPerLetter`% to the interval increase.
    /// E.g. at 4%, an 8-letter word yields a 1.32× multiplier.
    /// Trailing punctuation (commas, etc.) adds a fixed 0.2 bonus.
    nonisolated static func smartTimingMultiplier(for word: String, percentPerLetter: Double = 4.0) -> Double {
        let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
        let letterCount = trimmed.count

        var multiplier = 1.0 + Double(letterCount) * (percentPerLetter / 100.0)

        if percentPerLetter > 0, hasTrailingPunctuation(word) {
            multiplier += 0.2
        }

        return multiplier
    }

    nonisolated private static func hasTrailingPunctuation(_ word: String) -> Bool {
        guard let last = word.unicodeScalars.last else { return false }
        return CharacterSet.punctuationCharacters.contains(last)
    }

    nonisolated private static let sentenceEnders: Set<Character> = [".", "!", "?"]

    /// Returns `true` if the word ends with sentence-terminating punctuation (`.`, `!`, `?`).
    nonisolated static func endsWithSentencePunctuation(_ word: String) -> Bool {
        guard let last = word.last else { return false }
        return sentenceEnders.contains(last)
    }

    deinit {
        stopTimer()
    }
}
