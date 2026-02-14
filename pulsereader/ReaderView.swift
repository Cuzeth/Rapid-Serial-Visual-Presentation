import SwiftUI
import SwiftData

struct ReaderView: View {
    @Bindable var document: Document
    @State private var engine: RSVPEngine
    @State private var isTouching = false
    @State private var scrubAccumulator: CGFloat = 0
    @State private var wpmSliderValue: Double
    @State private var isBarScrubbing = false
    @State private var showCompletion = false

    init(document: Document) {
        self.document = document
        self._engine = State(initialValue: RSVPEngine(
            words: document.words,
            currentIndex: document.currentWordIndex,
            wordsPerMinute: document.wordsPerMinute
        ))
        self._wpmSliderValue = State(initialValue: Double(document.wordsPerMinute))
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.opacity(0.001)
                    .gesture(unifiedGesture)

                VStack {
                    topBar
                    Spacer()

                    if showCompletion {
                        completionView
                            .transition(.opacity)
                    } else {
                        WordView(
                            word: engine.currentWord,
                            fontSize: 40
                        )
                            .transition(.opacity)
                    }

                    Spacer()
                    bottomBar
                        .opacity(engine.isPlaying ? 0.4 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: engine.isPlaying)
                }
                .allowsHitTesting(true)
                .animation(.easeInOut(duration: 0.2), value: engine.isPlaying)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(engine.isPlaying ? "" : document.title)
        .navigationBarBackButtonHidden(engine.isPlaying)
        .onAppear {
            if engine.isAtEnd { showCompletion = true }
        }
        .onDisappear(perform: saveState)
        .onChange(of: engine.currentIndex) { _, newIndex in
            if newIndex % 10 == 0 {
                document.currentWordIndex = newIndex
            }
        }
        .onChange(of: engine.isPlaying) { wasPlaying, isNowPlaying in
            if wasPlaying && !isNowPlaying && engine.isAtEnd {
                HapticManager.shared.completedReading()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showCompletion = true
                    }
                }
            }
        }
        .onChange(of: wpmSliderValue) { _, newValue in
            let snapped = Int(newValue)
            if snapped != engine.wordsPerMinute {
                engine.wordsPerMinute = snapped
                HapticManager.shared.wpmChanged()
            }
        }
    }

    // MARK: - Unified gesture

    private var unifiedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !showCompletion else { return }
                let horizontal = abs(value.translation.width)

                if !isTouching {
                    isTouching = true
                    engine.play()
                    HapticManager.shared.playPause()
                }

                if horizontal > 20 {
                    if engine.isPlaying { engine.pause() }

                    let threshold: CGFloat = 30
                    let newAccumulator = value.translation.width
                    let delta = Int(newAccumulator / threshold) - Int(scrubAccumulator / threshold)
                    if delta != 0 {
                        if engine.scrub(by: delta) {
                            HapticManager.shared.scrubBoundary()
                        } else {
                            HapticManager.shared.scrubTick()
                        }
                        scrubAccumulator = newAccumulator
                    }
                }
            }
            .onEnded { _ in
                isTouching = false
                engine.pause()
                HapticManager.shared.playPause()
                scrubAccumulator = 0
            }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(engine.wordsPerMinute) WPM")
                    .font(.custom("JetBrainsMono-Regular", size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)

                Spacer()

                Text("\(engine.currentIndex + 1) / \(engine.words.count)")
                    .font(.custom("JetBrainsMono-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: $wpmSliderValue,
                in: 100...1000,
                step: 10
            )
            .tint(.red)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .opacity(engine.isPlaying ? 0.0 : 1.0)
        .offset(y: engine.isPlaying ? -6 : 0)
        .allowsHitTesting(!engine.isPlaying)
        .animation(.easeInOut(duration: 0.2), value: engine.isPlaying)
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
                .frame(height: 3)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if engine.isPlaying { engine.pause() }
                            isBarScrubbing = true
                            if showCompletion {
                                withAnimation { showCompletion = false }
                            }
                            let pct = max(0, min(value.location.x / geo.size.width, 1))
                            let target = Int(pct * Double(engine.words.count - 1))
                            engine.seek(to: target)
                        }
                        .onEnded { _ in
                            isBarScrubbing = false
                        }
                )
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 1.5))

            Text(hintText)
                .font(.custom("JetBrainsMono-Regular", size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
    }

    // MARK: - Completion view

    private var completionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Finished!")
                .font(.custom("JetBrainsMono-Bold", size: 28))

            Text("\(engine.words.count) words read")
                .font(.custom("JetBrainsMono-Regular", size: 16))
                .foregroundStyle(.secondary)

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showCompletion = false
                }
                engine.restart()
            } label: {
                Text("Read Again")
                    .font(.custom("JetBrainsMono-Regular", size: 16))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
            }
        }
    }

    // MARK: - Hint text

    private var hintText: String {
        if showCompletion { return "Completed" }
        if isBarScrubbing { return "Seeking..." }
        if engine.isPlaying { return "Release to pause" }
        return "Hold to read"
    }

    // MARK: - Persistence

    private func saveState() {
        engine.pause()
        document.currentWordIndex = engine.currentIndex
        document.wordsPerMinute = engine.wordsPerMinute
        document.lastReadDate = Date()
    }
}
