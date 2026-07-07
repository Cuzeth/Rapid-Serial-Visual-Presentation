import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// The RSVP reading interface — displays words one at a time.
///
/// Gesture-driven: hold to play (or tap to toggle, when `holdToReadEnabled`
/// is off), release to pause, swipe to scrub. Includes a WPM slider, chapter
/// navigation (when chapters exist), progress bar scrubber, and completion
/// overlay. Persists reading state on disappear and scene phase changes.
struct ReaderView: View {
    private let navFadeDuration: Double = 0.3
    private let playIntentDelay: TimeInterval = 0.12

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ReaderSettings.Keys.fontSize) private var fontSize: Int = ReaderSettings.Defaults.fontSize
    @AppStorage(ReaderSettings.Keys.smartTimingEnabled) private var smartTimingEnabled: Bool = ReaderSettings.Defaults.smartTimingEnabled
    @AppStorage(ReaderSettings.Keys.sentencePauseEnabled) private var sentencePauseEnabled: Bool = ReaderSettings.Defaults.sentencePauseEnabled
    @AppStorage(ReaderSettings.Keys.smartTimingPercentPerLetter) private var smartTimingPercentPerLetter: Double = ReaderSettings.Defaults.smartTimingPercentPerLetter
    @AppStorage(ReaderSettings.Keys.sentencePauseMultiplier) private var sentencePauseMultiplierValue: Double = ReaderSettings.Defaults.sentencePauseMultiplier
    @AppStorage(ReaderSettings.Keys.complexityTimingEnabled) private var complexityTimingEnabled: Bool = ReaderSettings.Defaults.complexityTimingEnabled
    @AppStorage(ReaderSettings.Keys.complexityIntensity) private var complexityIntensity: Double = ReaderSettings.Defaults.complexityIntensity
    @AppStorage(ReaderSettings.Keys.holdToReadEnabled) private var holdToReadEnabled: Bool = ReaderSettings.Defaults.holdToReadEnabled
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
    @State private var showChapterPicker = false
    @State private var showPassage = false
    @State private var persistenceError: String?
    @State private var isLoaded = false
    @State private var isBackfillingComplexity = false
    @FocusState private var readerFocused: Bool

    private let startingWordIndex: Int?

    /// On iPad (regular width) we constrain controls to a comfortable column so
    /// sliders and buttons don't stretch the full width of a 12.9" display.
    private var controlsMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 680 : .infinity
    }

    init(document: Document, startingWordIndex: Int? = nil) {
        self.document = document
        self.startingWordIndex = startingWordIndex
        // Read settings via the shared snapshot because @AppStorage properties
        // aren't accessible before `self` is fully initialized. ReaderSettings
        // owns the keys and defaults the @AppStorage declarations above use.
        let timing = ReaderSettings.timingSnapshot()
        // The engine starts empty; words are decoded off the main actor in
        // `.task` so opening a large document doesn't hitch navigation.
        self._engine = State(initialValue: RSVPEngine(
            words: [],
            wordsPerMinute: document.wordsPerMinute,
            smartTimingEnabled: timing.smartTimingEnabled,
            sentencePauseEnabled: timing.sentencePauseEnabled,
            smartTimingPercentPerLetter: timing.smartTimingPercentPerLetter,
            sentencePauseMultiplier: timing.sentencePauseMultiplier,
            complexityTimingEnabled: timing.complexityTimingEnabled,
            complexityIntensity: timing.complexityIntensity
        ))
        self._wpmSliderValue = State(initialValue: Double(document.wordsPerMinute))
    }

    /// Decodes the word and complexity blobs (off-main) and hands them to the
    /// engine. Runs once; `isLoaded` gates persistence so a reader closed
    /// mid-load can't overwrite the saved position with the empty state.
    private func loadDocumentIfNeeded() async {
        guard !isLoaded else { return }
        let words = await document.loadReadingWordsAsync()
        let scores = await document.loadComplexityScoresAsync()
        let effectiveIndex = startingWordIndex ?? document.currentWordIndex
        engine.load(words: words, currentIndex: effectiveIndex, complexityScores: scores)
        isLoaded = true
        // A document resumed at its last word (with more than one word) opens
        // onto the completion card; single-word documents show their word.
        if engine.isAtEnd && engine.words.count > 1 {
            showCompletion = true
        }
        if scores == nil && complexityTimingEnabled {
            backfillComplexityScores()
        }
    }

    /// Computes and stores complexity scores for documents imported before
    /// complexity timing existed — without this, the setting is a silent
    /// no-op for them. Runs off-main; playback works normally meanwhile.
    private func backfillComplexityScores() {
        guard !isBackfillingComplexity else { return }
        let words = engine.words
        guard !words.isEmpty else { return }
        isBackfillingComplexity = true
        Task {
            defer { isBackfillingComplexity = false }
            let scores = await Task.detached(priority: .utility) {
                WordComplexityAnalyzer.analyzeComplexity(words)
            }.value
            document.storeComplexityScores(scores)
            engine.updateComplexityScores(scores)
            // Benign if this fails — the scores are recomputed next open.
            try? modelContext.save()
        }
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
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                } else {
                    CurrentWordView(engine: engine, fontSize: CGFloat(fontSize))
                    .id("wordview") // stabilize identity
                    .transition(.opacity)
                    // Overlay (not a sibling) so the word never shifts when
                    // the readout appears.
                    .overlay {
                        HoldSpeedReadoutView(engine: engine)
                            .offset(y: CGFloat(fontSize) * 1.4)
                            .accessibilityHidden(true)
                    }
                    // The word display sits above the gesture layer; without
                    // this, holding directly on the word would swallow the
                    // hold-to-read gesture.
                    .allowsHitTesting(false)
                    .accessibilityAction(named: engine.isPlaying ? "Pause" : "Play") {
                        togglePlayback()
                    }
                }

                Spacer()
                bottomBar
                    .opacity(engine.isPlaying ? 0.0 : 1.0)
                    .allowsHitTesting(!engine.isPlaying)
                    .animation(.easeInOut(duration: 0.2), value: engine.isPlaying)
            }
            .animation(.easeInOut(duration: 0.2), value: engine.isPlaying)
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        #endif
        .task {
            await loadDocumentIfNeeded()
        }
        .onAppear {
            readerFocused = true
        }
        // Re-assert keyboard focus whenever any overlay (passage view, chapter
        // picker, save-error alert) closes, so Space/arrow shortcuts keep
        // working on macOS. One derived flag covers all presentations — adding
        // a new one only requires extending `isPresentingOverlay`.
        .onChange(of: isPresentingOverlay) { _, isPresenting in
            if !isPresenting { readerFocused = true }
        }
        .onDisappear {
            persistState(pauseEngine: true, touchLastReadDate: true)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                // Pause as well as persist — words advancing while the app is
                // covered (Notification Center, app switcher, a call) are
                // words the user never saw.
                persistState(pauseEngine: true, touchLastReadDate: false)
            }
        }
        .onChange(of: showPassage) { _, isShowing in
            // Tapping a word in the passage view seeks the engine — if the
            // completion overlay was up, it's stale once the position left
            // the end. (Deliberately keyed on the sheet, not on
            // `engine.currentIndex`: reading the index here would subscribe
            // the whole reader body to every word tick.)
            if !isShowing && showCompletion && !engine.isAtEnd {
                withAnimation { showCompletion = false }
            }
        }
        .onChange(of: engine.isPlaying) { wasPlaying, isNowPlaying in
            if wasPlaying && !isNowPlaying && engine.isAtEnd {
                HapticManager.shared.completedReading()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    // The user may have scrubbed away or resumed during the
                    // delay — re-check before showing the overlay.
                    guard engine.isAtEnd, !engine.isPlaying else { return }
                    showCompletionOverlay()
                }
            }
        }
        .onChange(of: smartTimingEnabled) { _, newValue in
            engine.smartTimingEnabled = newValue
        }
        .onChange(of: sentencePauseEnabled) { _, newValue in
            engine.sentencePauseEnabled = newValue
        }
        .onChange(of: smartTimingPercentPerLetter) { _, newValue in
            engine.smartTimingPercentPerLetter = newValue
        }
        .onChange(of: sentencePauseMultiplierValue) { _, newValue in
            engine.sentencePauseMultiplier = newValue
        }
        .onChange(of: complexityTimingEnabled) { _, newValue in
            engine.complexityTimingEnabled = newValue
            // The setting can be flipped on mid-session (macOS Settings
            // window) for a legacy document with no stored scores.
            if newValue && isLoaded && engine.complexityScores == nil {
                backfillComplexityScores()
            }
        }
        .onChange(of: complexityIntensity) { _, newValue in
            engine.complexityIntensity = newValue
        }
        .alert("Save Error", isPresented: .init(isPresent: $persistenceError)) {
            Button("OK") { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "")
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showPassage) {
            PassageView(document: document, engine: engine)
        }
        #elseif os(macOS)
        .sheet(isPresented: $showPassage) {
            PassageView(document: document, engine: engine)
                .frame(minWidth: 600, minHeight: 700)
        }
        #endif
        .preferredColorScheme(.dark)
        .focusable()
        .focusEffectDisabled()
        .focused($readerFocused)
        .onKeyPress(.space) {
            guard !showCompletion else { return .ignored }
            togglePlayback()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            scrubWithFeedback(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            scrubWithFeedback(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        #if os(macOS)
        // Cmd+Q doesn't reliably trigger onDisappear/scenePhase on macOS —
        // without this hook, quitting mid-read loses the session's position.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            persistState(pauseEngine: true, touchLastReadDate: true)
        }
        #endif
    }

    /// Shared pause + scrub + haptic used by both arrow keys.
    private func scrubWithFeedback(by delta: Int) {
        if engine.isPlaying { engine.pause() }
        if showCompletion {
            withAnimation { showCompletion = false }
        }
        if engine.scrub(by: delta) {
            HapticManager.shared.scrubBoundary()
        } else {
            HapticManager.shared.scrubTick()
        }
    }

    private enum TouchMode {
        case undecided
        case reading
        case scrubbing
    }

    /// True while any focus-stealing presentation is up. Used to restore
    /// keyboard focus when the last one closes.
    private var isPresentingOverlay: Bool {
        showPassage || showChapterPicker || persistenceError != nil
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
                    if holdToReadEnabled {
                        schedulePlayIntent()
                    }
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

                if touchMode == .reading {
                    // Vertical drag while holding adjusts speed live. The
                    // override is nil inside the dead zone so the readout
                    // only appears once the finger commits to adjusting.
                    guard engine.isPlaying else { return }
                    let base = engine.wordsPerMinute
                    let mapped = RSVPEngine.holdSpeedWPM(
                        baseWPM: base,
                        verticalTranslation: value.translation.height
                    )
                    if mapped != engine.effectiveWordsPerMinute {
                        engine.wpmOverride = mapped == base ? nil : mapped
                        HapticManager.shared.scrubTick()
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
                let wasScrubbing = touchMode == .scrubbing
                isTouching = false
                cancelPlayIntent()
                // pause() clears the override; this covers the not-playing
                // edge case (e.g. the document ended mid-hold).
                engine.wpmOverride = nil
                if holdToReadEnabled {
                    if engine.isPlaying {
                        engine.pause()
                        HapticManager.shared.playPause()
                    }
                } else if !wasScrubbing && !showCompletion {
                    // Tap-to-toggle mode: a release without a horizontal swipe
                    // counts as a tap. Toggle playback.
                    if engine.isPlaying {
                        engine.pause()
                        HapticManager.shared.playPause()
                    } else if engine.isAtEnd {
                        // A tap at the last word can't start playback — show
                        // the completion card rather than a false "playing"
                        // haptic with no visible change.
                        showCompletionOverlay()
                    } else {
                        engine.play()
                        HapticManager.shared.playPause()
                    }
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
                if engine.isAtEnd {
                    showCompletionOverlay()
                } else {
                    engine.play()
                    HapticManager.shared.playPause()
                }
            }
        }
        pendingPlayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + playIntentDelay, execute: workItem)
    }

    private func cancelPlayIntent() {
        pendingPlayWorkItem?.cancel()
        pendingPlayWorkItem = nil
    }

    /// Shared play/pause toggle used by the Space key and the VoiceOver
    /// custom action, so playback isn't gesture-only.
    private func togglePlayback() {
        if engine.isPlaying {
            engine.pause()
        } else if engine.isAtEnd {
            // Playing at the end is impossible — surface the completion card
            // instead of doing nothing (or worse, a false "playing" haptic).
            showCompletionOverlay()
            return
        } else {
            engine.play()
        }
        HapticManager.shared.playPause()
    }

    /// Presents the completion overlay, respecting Reduce Motion.
    private func showCompletionOverlay() {
        guard !showCompletion else { return }
        if reduceMotion {
            showCompletion = true
        } else {
            withAnimation(.spring(duration: 0.6)) {
                showCompletion = true
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        topBarContent
            .constrainedAndCentered(maxWidth: controlsMaxWidth)
            .animation(.easeInOut(duration: navFadeDuration), value: engine.isPlaying)
    }

    private var topBarContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                CircleIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {
                    dismiss()
                }

                Spacer()

                VStack(spacing: 2) {
                    Text(document.title)
                        .font(StrobeTheme.bodyFont(size: 16, bold: true))
                        .foregroundStyle(StrobeTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    WordCounterView(engine: engine)
                }

                Spacer()

                CircleIconButton(systemImage: "text.alignleft", accessibilityLabel: "View text") {
                    showPassage = true
                }
                .accessibilityHint("Shows the full passage with your current word highlighted")
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .opacity(engine.isPlaying ? 0.0 : 1.0)
            .allowsHitTesting(!engine.isPlaying)
            
            Spacer().frame(height: 20)
            
            // WPM Control
            HStack {
                Text("\(displayedWPM)")
                    .font(StrobeTheme.bodyFont(size: 24, bold: true))
                    .foregroundStyle(StrobeTheme.accent)
                    .frame(width: 80)

                Text("wpm")
                    .font(StrobeTheme.bodyFont(size: 14))
                    .foregroundStyle(StrobeTheme.textSecondary)
                    .padding(.bottom, 4)
                
                Slider(value: $wpmSliderValue, in: 100...1000, step: 10) { editing in
                    isAdjustingWPM = editing
                    if !editing {
                        applyWPM(Int(wpmSliderValue), withHaptic: true)
                    }
                }
                .tint(StrobeTheme.accent)
                .frame(minHeight: 44)
                .accessibilityLabel("Words per minute")
                .accessibilityValue("\(displayedWPM) words per minute")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(StrobeTheme.surface.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .opacity(engine.isPlaying ? 0.0 : 1.0)
            // Zero opacity does not disable hit testing — without this, taps
            // during playback land on the invisible slider instead of the
            // gesture layer (and can silently change the reading speed).
            .allowsHitTesting(!engine.isPlaying)
        }
        .animation(.easeInOut(duration: navFadeDuration), value: engine.isPlaying)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            if !document.chapters.isEmpty {
                ChapterNavigationView(
                    chapters: document.chapters,
                    engine: engine,
                    showChapterPicker: $showChapterPicker
                ) {
                    if showCompletion {
                        withAnimation { showCompletion = false }
                    }
                }
            }

            ProgressScrubberView(
                engine: engine,
                isBarScrubbing: $isBarScrubbing,
                showCompletion: $showCompletion
            )

            Text(hintText)
                .font(StrobeTheme.bodyFont(size: 14))
                .foregroundStyle(StrobeTheme.textSecondary)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .constrainedAndCentered(maxWidth: controlsMaxWidth)
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
            .scaleEffect(reduceMotion ? 1 : (showCompletion ? 1 : 0.5))
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6), value: showCompletion)

            VStack(spacing: 8) {
                Text("Finished!")
                    .font(StrobeTheme.titleFont(size: 32))
                    .foregroundStyle(StrobeTheme.textPrimary)

                Text(engine.words.count == 1 ? "1 word read" : "\(engine.words.count) words read")
                    .font(StrobeTheme.bodyFont(size: 18))
                    .foregroundStyle(StrobeTheme.textSecondary)
            }

            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(StrobeTheme.bodyFont(size: 16, bold: true))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(StrobeTheme.textPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Return to the previous screen")

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showCompletion = false
                    }
                    engine.restart()
                } label: {
                    Text("Read Again")
                        .font(StrobeTheme.bodyFont(size: 16, bold: true))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(StrobeTheme.accent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
        }
        .padding(40)
        .background(StrobeTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }

    // MARK: - Hint text

    // The hint lives in the bottom bar, which is hidden during playback —
    // so only paused-state hints exist.
    private var hintText: String {
        if showCompletion { return "Completed" }
        if isBarScrubbing { return "Seeking..." }
        #if os(macOS)
        return "Press Space to read, arrows to scrub"
        #else
        return holdToReadEnabled ? "Hold to read" : "Tap to read"
        #endif
    }

    private var displayedWPM: Int {
        isAdjustingWPM ? Int(wpmSliderValue) : engine.wordsPerMinute
    }

    // MARK: - Persistence

    private func persistState(pauseEngine: Bool, touchLastReadDate: Bool) {
        // Before the async load completes the engine holds no words and index
        // 0 — persisting that would erase the real saved position.
        guard isLoaded else { return }
        if isAdjustingWPM {
            isAdjustingWPM = false
            applyWPM(Int(wpmSliderValue), withHaptic: false)
        }
        if pauseEngine {
            cancelPlayIntent()
            engine.pause()
        }
        document.recordPosition(
            currentIndex: engine.currentIndex,
            wordsPerMinute: engine.wordsPerMinute,
            touchLastReadDate: touchLastReadDate
        )
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Could not save reading progress: \(error.localizedDescription)"
        }
    }

    private func applyWPM(_ value: Int, withHaptic: Bool) {
        let clamped = max(1, value)
        guard clamped != engine.wordsPerMinute else { return }
        engine.wordsPerMinute = clamped
        document.wordsPerMinute = value
        if withHaptic {
            HapticManager.shared.selectionTick()
        }
    }
}

// MARK: - Per-tick child views
//
// These read `engine.currentIndex`/`currentWord`/`progress` in their own
// bodies so @Observable tracking invalidates only these small subtrees on
// every word tick (16×/sec at 1000 WPM) — not the entire reader.

/// The word display. Isolates the per-tick `currentWord` read.
private struct CurrentWordView: View {
    let engine: RSVPEngine
    let fontSize: CGFloat

    var body: some View {
        WordView(word: engine.currentWord, fontSize: fontSize)
            .equatable()
    }
}

/// The transient speed readout shown while a hold-to-read vertical drag
/// has an active WPM override. Isolates the per-change speed read.
private struct HoldSpeedReadoutView: View {
    let engine: RSVPEngine

    var body: some View {
        Text("\(engine.effectiveWordsPerMinute) WPM")
            .font(StrobeTheme.bodyFont(size: 14))
            .monospacedDigit()
            .foregroundStyle(StrobeTheme.textSecondary)
            .opacity(engine.wpmOverride != nil ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: engine.wpmOverride != nil)
    }
}

/// The "n / total" counter in the top bar.
private struct WordCounterView: View {
    let engine: RSVPEngine

    var body: some View {
        Text("\(engine.currentIndex + 1) / \(engine.words.count)")
            .font(StrobeTheme.bodyFont(size: 12))
            .foregroundStyle(StrobeTheme.textSecondary)
    }
}

/// The progress bar with drag-to-seek and VoiceOver adjustment.
private struct ProgressScrubberView: View {
    let engine: RSVPEngine
    @Binding var isBarScrubbing: Bool
    @Binding var showCompletion: Bool

    var body: some View {
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
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Reading progress")
        .accessibilityValue("\(Int(engine.progress * 100)) percent, word \(engine.currentIndex + 1) of \(engine.words.count)")
        .accessibilityAdjustableAction { direction in
            // Step ~1% per adjustment — single-word steps made the scrubber
            // unusable with VoiceOver on book-length documents.
            let step = max(1, engine.words.count / 100)
            switch direction {
            case .increment:
                _ = engine.scrub(by: step)
            case .decrement:
                _ = engine.scrub(by: -step)
            @unknown default:
                break
            }
            if showCompletion && !engine.isAtEnd {
                showCompletion = false
            }
        }
    }
}
