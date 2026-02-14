import SwiftUI
import SwiftData

struct ReaderView: View {
    private let navFadeDuration: Double = 0.3
    private let playIntentDelay: TimeInterval = 0.12

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("fontSize") private var fontSize: Int = 40
    @AppStorage("smartTimingEnabled") private var smartTimingEnabled: Bool = false
    @Bindable var document: Document
    @State private var engine: RSVPEngine
    @State private var isTouching = false
    @State private var scrubAccumulator: CGFloat = 0
    @State private var touchMode: TouchMode = .undecided
    @State private var pendingPlayWorkItem: DispatchWorkItem?
    @State private var wpmSliderValue: Double
    @State private var isAdjustingWPM = false
    @State private var isBarScrubbing = false
    @State private var showCompletion = false

    private let startingWordIndex: Int?

    init(document: Document, startingWordIndex: Int? = nil) {
        self.document = document
        self.startingWordIndex = startingWordIndex
        let effectiveIndex = startingWordIndex ?? document.currentWordIndex
        let usesSmartTiming = UserDefaults.standard.bool(forKey: "smartTimingEnabled")
        self._engine = State(initialValue: RSVPEngine(
            words: document.words,
            currentIndex: effectiveIndex,
            wordsPerMinute: document.wordsPerMinute,
            smartTimingEnabled: usesSmartTiming
        ))
        self._wpmSliderValue = State(initialValue: Double(document.wordsPerMinute))
    }

    var body: some View {
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
                        fontSize: CGFloat(fontSize)
                    )
                    .transition(.opacity)
                }

                Spacer()
                bottomBar
                    .opacity(engine.isPlaying ? 0.0 : 1.0)
                    .allowsHitTesting(!engine.isPlaying)
                    .animation(.easeInOut(duration: 0.2), value: engine.isPlaying)
            }
            .animation(.easeInOut(duration: 0.2), value: engine.isPlaying)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            navHeader
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if engine.isAtEnd { showCompletion = true }
        }
        .onDisappear {
            persistState(pauseEngine: true, touchLastReadDate: true)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                persistState(pauseEngine: false, touchLastReadDate: false)
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
        .onChange(of: smartTimingEnabled) { _, newValue in
            engine.smartTimingEnabled = newValue
        }
    }

    private enum TouchMode {
        case undecided
        case reading
        case scrubbing
    }

    // MARK: - Unified gesture

    private var unifiedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !showCompletion else { return }
                let horizontal = abs(value.translation.width)

                if !isTouching {
                    isTouching = true
                    touchMode = .undecided
                    scrubAccumulator = 0
                    schedulePlayIntent()
                }

                if touchMode == .undecided {
                    if horizontal > 20 {
                        touchMode = .scrubbing
                        cancelPlayIntent()
                        if engine.isPlaying {
                            engine.pause()
                            HapticManager.shared.playPause()
                        }
                    }
                }

                if touchMode == .scrubbing {
                    // Scrubbing is a paused-only interaction.
                    guard !engine.isPlaying else { return }

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
                cancelPlayIntent()
                if engine.isPlaying {
                    engine.pause()
                    HapticManager.shared.playPause()
                }
                scrubAccumulator = 0
                touchMode = .undecided
            }
    }

    private func schedulePlayIntent() {
        cancelPlayIntent()

        let workItem = DispatchWorkItem {
            guard isTouching, touchMode == .undecided, !showCompletion else { return }
            touchMode = .reading
            if !engine.isPlaying {
                engine.play()
                HapticManager.shared.playPause()
            }
        }
        pendingPlayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + playIntentDelay, execute: workItem)
    }

    private func cancelPlayIntent() {
        pendingPlayWorkItem?.cancel()
        pendingPlayWorkItem = nil
    }

    // MARK: - Top bar

    private var navHeader: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(10)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Circle())
            }
            .opacity(engine.isPlaying ? 0 : 1)
            .allowsHitTesting(!engine.isPlaying)
            .animation(.easeInOut(duration: navFadeDuration), value: engine.isPlaying)

            Spacer(minLength: 0)

            Text(document.title)
                .font(.custom("JetBrainsMono-Regular", size: 20))
                .lineLimit(1)
                .opacity(engine.isPlaying ? 0 : 1)
                .animation(.easeInOut(duration: navFadeDuration), value: engine.isPlaying)

            Spacer(minLength: 0)

            Circle()
                .fill(Color.clear)
                .frame(width: 37, height: 37)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color.clear)
    }

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(displayedWPM) WPM")
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

            Slider(value: $wpmSliderValue, in: 100...1000, step: 10) { editing in
                isAdjustingWPM = editing
                if !editing {
                    applyWPM(Int(wpmSliderValue), withHaptic: true)
                }
            }
            .tint(.red)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .opacity(engine.isPlaying ? 0.0 : 1.0)
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

    private var displayedWPM: Int {
        isAdjustingWPM ? Int(wpmSliderValue) : engine.wordsPerMinute
    }

    // MARK: - Persistence

    private func persistState(pauseEngine: Bool, touchLastReadDate: Bool) {
        if isAdjustingWPM {
            isAdjustingWPM = false
            applyWPM(Int(wpmSliderValue), withHaptic: false)
        }
        if pauseEngine {
            cancelPlayIntent()
            engine.pause()
        }
        document.currentWordIndex = engine.currentIndex
        document.wordsPerMinute = engine.wordsPerMinute
        if touchLastReadDate {
            document.lastReadDate = Date()
        }
        try? modelContext.save()
    }

    private func applyWPM(_ value: Int, withHaptic: Bool) {
        guard value != engine.wordsPerMinute else { return }
        engine.wordsPerMinute = value
        document.wordsPerMinute = value
        if withHaptic {
            HapticManager.shared.wpmChanged()
        }
    }
}
