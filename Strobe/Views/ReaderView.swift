import SwiftUI
import SwiftData

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
    @AppStorage("fontSize") private var fontSize: Int = 40
    @AppStorage("smartTimingEnabled") private var smartTimingEnabled: Bool = false
    @AppStorage("sentencePauseEnabled") private var sentencePauseEnabled: Bool = false
    @AppStorage("smartTimingPercentPerLetter") private var smartTimingPercentPerLetter: Double = 4.0
    @AppStorage("sentencePauseMultiplier") private var sentencePauseMultiplierValue: Double = 1.5
    @AppStorage("complexityTimingEnabled") private var complexityTimingEnabled: Bool = false
    @AppStorage("complexityIntensity") private var complexityIntensity: Double = 0.5
    @AppStorage("holdToReadEnabled") private var holdToReadEnabled: Bool = true
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
    @State private var showChapterPicker = false
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
        // Read settings via UserDefaults because @AppStorage properties aren't
        // accessible before `self` is fully initialized. Keys and defaults must
        // match the @AppStorage declarations above.
        let usesSmartTiming = UserDefaults.standard.bool(forKey: "smartTimingEnabled")
        let usesSentencePause = UserDefaults.standard.bool(forKey: "sentencePauseEnabled")
        let percentPerLetter = UserDefaults.standard.object(forKey: "smartTimingPercentPerLetter") as? Double ?? 4.0
        let pauseMultiplier = UserDefaults.standard.object(forKey: "sentencePauseMultiplier") as? Double ?? 1.5
        let usesComplexityTiming = UserDefaults.standard.bool(forKey: "complexityTimingEnabled")
        let complexityIntensityValue = UserDefaults.standard.object(forKey: "complexityIntensity") as? Double ?? 0.5
        self._engine = State(initialValue: RSVPEngine(
            words: words,
            currentIndex: effectiveIndex,
            wordsPerMinute: document.wordsPerMinute,
            smartTimingEnabled: usesSmartTiming,
            sentencePauseEnabled: usesSentencePause,
            smartTimingPercentPerLetter: percentPerLetter,
            sentencePauseMultiplier: pauseMultiplier,
            complexityTimingEnabled: usesComplexityTiming,
            complexityIntensity: complexityIntensityValue,
            complexityScores: document.complexityScores
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
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                } else {
                    WordView(
                        word: engine.currentWord,
                        fontSize: CGFloat(fontSize)
                    )
                    .equatable()
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
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        #endif
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
                    if reduceMotion {
                        showCompletion = true
                    } else {
                        withAnimation(.spring(duration: 0.6)) {
                            showCompletion = true
                        }
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
        .onChange(of: smartTimingPercentPerLetter) { _, newValue in
            engine.smartTimingPercentPerLetter = newValue
        }
        .onChange(of: sentencePauseMultiplierValue) { _, newValue in
            engine.sentencePauseMultiplier = newValue
        }
        .onChange(of: complexityTimingEnabled) { _, newValue in
            engine.complexityTimingEnabled = newValue
        }
        .onChange(of: complexityIntensity) { _, newValue in
            engine.complexityIntensity = newValue
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
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard !showCompletion else { return .ignored }
            if engine.isPlaying {
                engine.pause()
                HapticManager.shared.playPause()
            } else {
                engine.play()
                HapticManager.shared.playPause()
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if engine.isPlaying { engine.pause() }
            if showCompletion {
                withAnimation { showCompletion = false }
            }
            if engine.scrub(by: -1) {
                HapticManager.shared.scrubBoundary()
            } else {
                HapticManager.shared.scrubTick()
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if engine.isPlaying { engine.pause() }
            if showCompletion {
                withAnimation { showCompletion = false }
            }
            if engine.scrub(by: 1) {
                HapticManager.shared.scrubBoundary()
            } else {
                HapticManager.shared.scrubTick()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
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
                    } else if !engine.isAtEnd {
                        engine.play()
                    }
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
        topBarContent
            .constrainedAndCentered(maxWidth: controlsMaxWidth)
            .animation(.easeInOut(duration: navFadeDuration), value: engine.isPlaying)
    }

    private var topBarContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                #if os(iOS)
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
                .buttonStyle(.plain)
                #endif

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
        }
        .animation(.easeInOut(duration: navFadeDuration), value: engine.isPlaying)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            if !document.chapters.isEmpty {
                chapterNavigation
            }

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
            .frame(height: 44)
            .accessibilityElement()
            .accessibilityLabel("Reading progress")
            .accessibilityValue("\(Int(engine.progress * 100)) percent, word \(engine.currentIndex + 1) of \(engine.words.count)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    _ = engine.scrub(by: 1)
                case .decrement:
                    _ = engine.scrub(by: -1)
                @unknown default:
                    break
                }
            }

            Text(hintText)
                .font(StrobeTheme.bodyFont(size: 14))
                .foregroundStyle(StrobeTheme.textSecondary)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .constrainedAndCentered(maxWidth: controlsMaxWidth)
    }

    // MARK: - Chapter navigation

    /// Index of the chapter containing the current word (largest chapter whose
    /// `wordIndex` is at or before `engine.currentIndex`). Nil if no chapters.
    private var currentChapterIndex: Int? {
        let chapters = document.chapters
        guard !chapters.isEmpty else { return nil }
        var result = 0
        for (i, chapter) in chapters.enumerated() {
            if chapter.wordIndex <= engine.currentIndex {
                result = i
            } else {
                break
            }
        }
        return result
    }

    private var canGoPreviousChapter: Bool {
        let chapters = document.chapters
        guard let idx = currentChapterIndex else { return false }
        return engine.currentIndex > chapters[idx].wordIndex + 2 || idx > 0
    }

    private var canGoNextChapter: Bool {
        guard let idx = currentChapterIndex else { return false }
        return idx + 1 < document.chapters.count
    }

    private var chapterNavigation: some View {
        let chapters = document.chapters
        let idx = currentChapterIndex ?? 0
        let title = chapters.indices.contains(idx) ? chapters[idx].title : ""

        return HStack(spacing: 10) {
            Button {
                jumpToPreviousChapter()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(canGoPreviousChapter ? StrobeTheme.textSecondary : StrobeTheme.textSecondary.opacity(0.35))
                    .frame(width: 36, height: 36)
                    .background(StrobeTheme.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoPreviousChapter)
            .accessibilityLabel("Previous chapter")

            Button {
                showChapterPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(readerFont.boldFont(size: 13))
                        .foregroundStyle(StrobeTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(StrobeTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(StrobeTheme.surface)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showChapterPicker, arrowEdge: .bottom) {
                chapterPickerContent
            }
            .accessibilityLabel("Chapter")
            .accessibilityValue(title)
            .accessibilityHint("Pick a chapter to jump to")

            Button {
                jumpToNextChapter()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(canGoNextChapter ? StrobeTheme.textSecondary : StrobeTheme.textSecondary.opacity(0.35))
                    .frame(width: 36, height: 36)
                    .background(StrobeTheme.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoNextChapter)
            .accessibilityLabel("Next chapter")
        }
    }

    @ViewBuilder
    private var chapterPickerContent: some View {
        let chapters = document.chapters
        let activeIndex = currentChapterIndex

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { i, chapter in
                        Button {
                            showChapterPicker = false
                            jumpToChapter(i)
                        } label: {
                            HStack(spacing: 12) {
                                Text(chapter.title)
                                    .font(StrobeTheme.bodyFont(size: 15, bold: i == activeIndex))
                                    .foregroundStyle(i == activeIndex ? StrobeTheme.accent : StrobeTheme.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if i == activeIndex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(StrobeTheme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(chapter.id)

                        if i < chapters.count - 1 {
                            Divider()
                                .background(StrobeTheme.surface)
                                .padding(.leading, 16)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(StrobeTheme.background)
            .onAppear {
                guard let idx = activeIndex, chapters.indices.contains(idx) else { return }
                // Defer one runloop so LazyVStack rows are registered before we scroll.
                DispatchQueue.main.async {
                    proxy.scrollTo(chapters[idx].id, anchor: .center)
                }
            }
        }
        .frame(idealWidth: 360, idealHeight: 480)
        .presentationDetents([.medium, .large])
    }

    private func jumpToChapter(_ index: Int) {
        let chapters = document.chapters
        guard chapters.indices.contains(index) else { return }
        if engine.isPlaying { engine.pause() }
        if showCompletion {
            withAnimation { showCompletion = false }
        }
        engine.seek(to: chapters[index].wordIndex)
        HapticManager.shared.scrubBoundary()
    }

    private func jumpToPreviousChapter() {
        let chapters = document.chapters
        guard let idx = currentChapterIndex else { return }
        let chapterStart = chapters[idx].wordIndex
        if engine.currentIndex > chapterStart + 2 {
            jumpToChapter(idx)
        } else if idx > 0 {
            jumpToChapter(idx - 1)
        }
    }

    private func jumpToNextChapter() {
        guard let idx = currentChapterIndex, idx + 1 < document.chapters.count else { return }
        jumpToChapter(idx + 1)
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
            .buttonStyle(.plain)
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
        #if os(macOS)
        if engine.isPlaying { return "Press Space to pause" }
        return "Press Space to read, arrows to scrub"
        #else
        if holdToReadEnabled {
            if engine.isPlaying { return "Release to pause" }
            return "Hold to read"
        } else {
            if engine.isPlaying { return "Tap to pause" }
            return "Tap to read"
        }
        #endif
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
        let clamped = max(1, value)
        guard clamped != engine.wordsPerMinute else { return }
        engine.wordsPerMinute = clamped
        document.wordsPerMinute = value
        if withHaptic {
            HapticManager.shared.wpmChanged()
        }
    }
}
