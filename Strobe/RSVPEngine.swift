import Foundation

@Observable
final class RSVPEngine {

    private(set) var words: [String]
    private(set) var currentIndex: Int
    private(set) var isPlaying: Bool = false

    var wordsPerMinute: Int {
        didSet {
            guard isPlaying else { return }
            restartTimer()
        }
    }

    var smartTimingEnabled: Bool {
        didSet {
            guard isPlaying else { return }
            restartTimer()
        }
    }

    var currentWord: String {
        guard currentIndex >= 0, currentIndex < words.count else { return "" }
        return words[currentIndex]
    }

    var isAtEnd: Bool { currentIndex >= words.count - 1 }

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
        smartTimingEnabled: Bool = false
    ) {
        self.words = words
        self.currentIndex = currentIndex
        self.wordsPerMinute = wordsPerMinute
        self.smartTimingEnabled = smartTimingEnabled
    }

    func play() {
        guard !isPlaying, !isAtEnd else { return }
        isPlaying = true
        startTimer()
    }

    func pause() {
        isPlaying = false
        stopTimer()
    }

    func seek(to index: Int) {
        currentIndex = max(0, min(index, words.count - 1))
    }

    @discardableResult
    func scrub(by delta: Int) -> Bool {
        let target = currentIndex + delta
        seek(to: target)
        return currentIndex != target
    }

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
        guard smartTimingEnabled else { return baseInterval }
        return baseInterval * Self.smartTimingMultiplier(for: currentWord)
    }

    nonisolated static func smartTimingMultiplier(for word: String) -> Double {
        let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
        let letterCount = trimmed.count

        var multiplier: Double = 1.0

        switch letterCount {
        case 0...6:
            multiplier = 1.0
        case 7...9:
            multiplier = 1.3
        case 10...12:
            multiplier = 1.4
        default:
            multiplier = 1.5
        }

        if hasTrailingPunctuation(word) {
            multiplier += 0.2
        }

        return min(multiplier, 1.7)
    }

    nonisolated private static func hasTrailingPunctuation(_ word: String) -> Bool {
        guard let last = word.unicodeScalars.last else { return false }
        return CharacterSet.punctuationCharacters.contains(last)
    }

    deinit {
        stopTimer()
    }
}
