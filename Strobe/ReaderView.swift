import SwiftUI
import SwiftData

/// The RSVP reading interface — displays words one at a time.
///
/// Gesture-driven: hold to play, release to pause, swipe to scrub.
/// Includes a WPM slider, progress bar scrubber, and completion overlay.
/// Persists reading state on disappear and scene phase changes.
struct ReaderView: View {
    private let navFadeDuration: Double = 0.3
    private let playIntentDelay: TimeInterval = 0.12

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("fontSize") private var fontSize: Int = 40
    @AppStorage("smartTimingEnabled") private var smartTimingEnabled: Bool = false
    @AppStorage("sentencePauseEnabled") private var sentencePauseEnabled: Bool = false
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue
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
    @State private var persistenceError: String?

    private let startingWordIndex: Int?

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
    }

    /// On iPad (regular width) we constrain controls to a comfortable column so
    /// sliders and buttons don't stretch the full width of a 12.9" display.
    private var controlsMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 680 : .infinity
    }

    init(document: Document, startingWordIndex: Int? = nil) {
        self.document = document
        self.startingWordIndex = startingWordIndex
        let effectiveIndex = startingWordIndex ?? document.currentWordIndex
        let words = document.readingWords
        let usesSmartTiming = UserDefaults.standard.bool(forKey: "smartTimingEnabled")
        let usesSentencePause = UserDefaults.standard.bool(forKey: "sentencePauseEnabled")
        self._engine = State(initialValue: RSVPEngine(
            words: words,
            currentIndex: effectiveIndex,
            wordsPerMinute: document.wordsPerMinute,
            smartTimingEnabled: usesSmartTiming,
            sentencePauseEnabled: usesSentencePause
        ))
        self._wpmSliderValue = State(initialValue: Double(document.wordsPerMinute))
    }

    var body: some View {
        ZStack {
            // Immersive Background
            StrobeTheme.Gradients.mainBackground
                .ignoresSafeArea()
            
            // Gesture Layer
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .gesture(unifiedGesture)

            VStack {
                topBar
                Spacer()

                if showCompletion {
                    completionView
                        .transition(.scale.combined(with: .opacity))
                } else {
                    WordView(
                        word: engine.currentWord,
                        fontSize: CGFloat(fontSize)
                    )
                    .id("wordview") // stabilize identity
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
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
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
                    withAnimation(.spring(duration: 0.6)) {
                        showCompletion = true
                    }
                }
            }
        }
        .onChange(of: smartTimingEnabled) { _, newValue in
            engine.smartTimingEnabled = newValue
        }
        .onChange(of: sentencePauseEnabled) { _, newValue in
            engine.sentencePauseEnabled = newValue
        }
        .alert("Save Error", isPresented: .init(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK") { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "")
        }
        .preferredColorScheme(.dark)
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

    private var topBar: some View {
        VStack(spacing: 0) {
            topBarContent
                .frame(maxWidth: controlsMaxWidth)
                .frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: navFadeDuration), value: engine.isPlaying)
    }

    private var topBarContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(StrobeTheme.textSecondary)
                        .padding(12)
                        .background(StrobeTheme.surface)
                        .clipShape(Circle())
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text(document.title)
                        .font(readerFont.boldFont(size: 16))
                        .foregroundStyle(StrobeTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Text("\(engine.currentIndex + 1) / \(engine.words.count)")
                        .font(readerFont.regularFont(size: 12))
                        .foregroundStyle(StrobeTheme.textSecondary)
                }
                
                Spacer()
                
                // Placeholder for symmetry or settings
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .opacity(engine.isPlaying ? 0.0 : 1.0)
            
            Spacer().frame(height: 20)
            
            // WPM Control
            HStack {
                Text("\(displayedWPM)")
                    .font(readerFont.boldFont(size: 24))
                    .foregroundStyle(StrobeTheme.accent)
                    .frame(width: 80)
                
                Text("wpm")
                    .font(readerFont.regularFont(size: 14))
                    .foregroundStyle(StrobeTheme.textSecondary)
                    .padding(.bottom, 4)
                
                Slider(value: $wpmSliderValue, in: 100...1000, step: 10) { editing in
                    isAdjustingWPM = editing
                    if !editing {
                        applyWPM(Int(wpmSliderValue), withHaptic: true)
                    }
                }
                .tint(StrobeTheme.accent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(StrobeTheme.surface.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .opacity(engine.isPlaying ? 0.0 : 1.0)
        }
        .animation(.easeInOut(duration: navFadeDuration), value: engine.isPlaying)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            // Progress Scrubber
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(StrobeTheme.surface)
                        .frame(height: 6)

                    Capsule()
                        .fill(StrobeTheme.accent)
                        .frame(width: geo.size.width * engine.progress, height: 6)

                    // Thumb
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .offset(x: (geo.size.width * engine.progress) - 8)
                }
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

            Text(hintText)
                .font(StrobeTheme.bodyFont(size: 14))
                .foregroundStyle(StrobeTheme.textSecondary)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: controlsMaxWidth)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Completion view

    private var completionView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(StrobeTheme.accent.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(StrobeTheme.accent)
            }
            .scaleEffect(showCompletion ? 1 : 0.5)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showCompletion)

            VStack(spacing: 8) {
                Text("Finished!")
                    .font(StrobeTheme.titleFont(size: 32))
                    .foregroundStyle(StrobeTheme.textPrimary)

                Text("\(engine.words.count) words read")
                    .font(StrobeTheme.bodyFont(size: 18))
                    .foregroundStyle(StrobeTheme.textSecondary)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showCompletion = false
                }
                engine.restart()
            } label: {
                Text("Read Again")
                    .font(StrobeTheme.bodyFont(size: 16, bold: true))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(StrobeTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 16)
        }
        .padding(40)
        .background(StrobeTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
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
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Could not save reading progress: \(error.localizedDescription)"
        }
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
