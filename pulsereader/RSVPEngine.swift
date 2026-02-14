import Foundation

@Observable
final class RSVPEngine {

    private(set) var words: [String]
    private(set) var currentIndex: Int
    private(set) var isPlaying: Bool = false

    var wordsPerMinute: Int {
        didSet {
            guard isPlaying else { return }
            stopTimer()
            startTimer()
        }
    }

    var currentWord: String {
        guard currentIndex >= 0, currentIndex < words.count else { return "" }
        return words[currentIndex]
    }

    var isAtEnd: Bool { currentIndex >= words.count }

    var progress: Double {
        guard !words.isEmpty else { return 0 }
        return Double(currentIndex) / Double(words.count)
    }

    private var timer: Timer?

    private var interval: TimeInterval {
        60.0 / Double(wordsPerMinute)
    }

    init(words: [String], currentIndex: Int = 0, wordsPerMinute: Int = 300) {
        self.words = words
        self.currentIndex = currentIndex
        self.wordsPerMinute = wordsPerMinute
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

    func scrub(by delta: Int) {
        seek(to: currentIndex + delta)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
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
        } else {
            pause()
        }
    }

    deinit {
        stopTimer()
    }
}
