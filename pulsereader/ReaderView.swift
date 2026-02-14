import SwiftUI
import SwiftData

struct ReaderView: View {
    @Bindable var document: Document
    @State private var engine: RSVPEngine
    @State private var isTouching = false
    @State private var scrubAccumulator: CGFloat = 0

    private let wpmOptions = [100, 150, 200, 250, 300, 400, 500, 600, 800, 1000]

    init(document: Document) {
        self.document = document
        self._engine = State(initialValue: RSVPEngine(
            words: document.words,
            currentIndex: document.currentWordIndex,
            wordsPerMinute: document.wordsPerMinute
        ))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.001)
                    .gesture(unifiedGesture)

                VStack {
                    topBar
                    Spacer()

                    WordView(word: engine.currentWord, fontSize: 40)

                    Spacer()
                    bottomBar
                }
                .allowsHitTesting(true)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(document.title)
        .onDisappear(perform: saveState)
        .onChange(of: engine.currentIndex) { _, newIndex in
            if newIndex % 10 == 0 {
                document.currentWordIndex = newIndex
            }
        }
    }

    // MARK: - Unified gesture

    /// Hold-to-play + swipe-to-scrub in a single gesture.
    /// Finger down = play. Horizontal movement > 20pt = pause & scrub. Finger up = pause.
    private var unifiedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let horizontal = abs(value.translation.width)

                if !isTouching {
                    isTouching = true
                    engine.play()
                }

                if horizontal > 20 {
                    if engine.isPlaying { engine.pause() }

                    let threshold: CGFloat = 30
                    let newAccumulator = value.translation.width
                    let delta = Int(newAccumulator / threshold) - Int(scrubAccumulator / threshold)
                    if delta != 0 {
                        engine.scrub(by: delta)
                        scrubAccumulator = newAccumulator
                    }
                }
            }
            .onEnded { _ in
                isTouching = false
                engine.pause()
                scrubAccumulator = 0
            }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Menu {
                ForEach(wpmOptions, id: \.self) { wpm in
                    Button("\(wpm) WPM") {
                        engine.wordsPerMinute = wpm
                    }
                }
            } label: {
                Text("\(engine.wordsPerMinute) WPM")
                    .font(.custom("JetBrainsMono-Regular", size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }

            Spacer()

            Text("\(engine.currentIndex + 1) / \(engine.words.count)")
                .font(.custom("JetBrainsMono-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.2))
                    Rectangle().fill(Color.red)
                        .frame(width: geo.size.width * engine.progress)
                }
            }
            .frame(height: 3)
            .clipShape(RoundedRectangle(cornerRadius: 1.5))

            Text(engine.isPlaying ? "Release to pause" : "Hold to read")
                .font(.custom("JetBrainsMono-Regular", size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
    }

    // MARK: - Persistence

    private func saveState() {
        engine.pause()
        document.currentWordIndex = engine.currentIndex
        document.wordsPerMinute = engine.wordsPerMinute
        document.lastReadDate = Date()
    }
}
