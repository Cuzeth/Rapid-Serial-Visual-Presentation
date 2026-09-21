import SwiftUI

/// App settings sheet for configuring reading speed, font, text size, and behavior.
struct SettingsView: View {
    @AppStorage(ReaderSettings.Keys.defaultWPM) private var defaultWPM: Int = ReaderSettings.Defaults.defaultWPM
    @AppStorage(ReaderSettings.Keys.fontSize) private var fontSize: Int = ReaderSettings.Defaults.fontSize
    @AppStorage(ReaderSettings.Keys.smartTimingEnabled) private var smartTimingEnabled: Bool = ReaderSettings.Defaults.smartTimingEnabled
    @AppStorage(ReaderSettings.Keys.sentencePauseEnabled) private var sentencePauseEnabled: Bool = ReaderSettings.Defaults.sentencePauseEnabled
    @AppStorage(ReaderSettings.Keys.smartTimingPercentPerLetter) private var smartTimingPercentPerLetter: Double = ReaderSettings.Defaults.smartTimingPercentPerLetter
    @AppStorage(ReaderSettings.Keys.smartTimingMinimumWordLength) private var smartTimingMinimumWordLength: Int = ReaderSettings.Defaults.smartTimingMinimumWordLength
    @AppStorage(ReaderSettings.Keys.sentencePauseMultiplier) private var sentencePauseMultiplierValue: Double = ReaderSettings.Defaults.sentencePauseMultiplier
    @AppStorage(ReaderSettings.Keys.complexityTimingEnabled) private var complexityTimingEnabled: Bool = ReaderSettings.Defaults.complexityTimingEnabled
    @AppStorage(ReaderSettings.Keys.complexityIntensity) private var complexityIntensity: Double = ReaderSettings.Defaults.complexityIntensity
    @AppStorage(ReaderSettings.Keys.clausePauseMultiplier) private var clausePauseMultiplier: Double = ReaderSettings.Defaults.clausePauseMultiplier
    @AppStorage(ReaderSettings.Keys.dashPauseMultiplier) private var dashPauseMultiplier: Double = ReaderSettings.Defaults.dashPauseMultiplier
    @AppStorage(ReaderSettings.Keys.ellipsisPauseMultiplier) private var ellipsisPauseMultiplier: Double = ReaderSettings.Defaults.ellipsisPauseMultiplier
    @AppStorage(ReaderSettings.Keys.bracketPauseMultiplier) private var bracketPauseMultiplier: Double = ReaderSettings.Defaults.bracketPauseMultiplier
    @AppStorage(ReaderSettings.Keys.holdToReadEnabled) private var holdToReadEnabled: Bool = ReaderSettings.Defaults.holdToReadEnabled
    @AppStorage(ReaderSettings.Keys.holdSpeedAdjustEnabled) private var holdSpeedAdjustEnabled: Bool = ReaderSettings.Defaults.holdSpeedAdjustEnabled
    @AppStorage(ReaderSettings.Keys.trueBlackBackgroundEnabled) private var trueBlackBackgroundEnabled: Bool = ReaderSettings.Defaults.trueBlackBackgroundEnabled
    @AppStorage(ReaderSettings.Keys.readingHeaderTitleEnabled) private var readingHeaderTitleEnabled: Bool = ReaderSettings.Defaults.readingHeaderTitleEnabled
    @AppStorage(ReaderSettings.Keys.readingHeaderChapterEnabled) private var readingHeaderChapterEnabled: Bool = ReaderSettings.Defaults.readingHeaderChapterEnabled
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue
    @AppStorage(ReaderTextTone.storageKey) private var readerTextToneSelection = ReaderTextTone.defaultValue.rawValue
    @AppStorage(TextCleaningLevel.storageKey) private var textCleaningLevel = TextCleaningLevel.defaultValue.rawValue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var wpmSliderValue: Double = 300
    @State private var fontSizeSliderValue: Double = 40
    @State private var showTutorial = false
    @State private var selectedPauseType: PauseType = .sentenceEnd

    /// On iPad (regular width), constrain the settings content to a readable column width.
    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 640 : .infinity
    }

    private var currentCleaningLevel: TextCleaningLevel {
        TextCleaningLevel.resolve(textCleaningLevel)
    }

    private var textCleaningEnabled: Binding<Bool> {
        Binding(
            get: { textCleaningLevel == TextCleaningLevel.standard.rawValue },
            set: { textCleaningLevel = $0 ? TextCleaningLevel.standard.rawValue : TextCleaningLevel.none.rawValue }
        )
    }

    /// Bridges the Int-backed minimum word length setting to `Slider`'s Double binding.
    private var smartTimingMinimumWordLengthSlider: Binding<Double> {
        Binding(
            get: { Double(smartTimingMinimumWordLength) },
            set: { smartTimingMinimumWordLength = Int($0.rounded()) }
        )
    }

    /// The punctuation types with their own pause multiplier. The pause slider
    /// edits whichever type is selected.
    private enum PauseType: CaseIterable, Identifiable {
        case sentenceEnd, clause, dash, ellipsis, bracket

        var id: Self { self }

        var title: String {
            switch self {
            case .sentenceEnd: "Sentence end"
            case .clause: "Commas, colons, semicolons"
            case .dash: "Dashes"
            case .ellipsis: "Ellipses"
            case .bracket: "Closing brackets and quotes"
            }
        }

        /// The marks shown on the type's selector button.
        var sample: String {
            switch self {
            case .sentenceEnd: ". ! ?"
            case .clause: ", ; :"
            case .dash: "\u{2014}"
            case .ellipsis: "\u{2026}"
            case .bracket: ") \u{201D}"
            }
        }
    }

    private func pauseMultiplier(for type: PauseType) -> Binding<Double> {
        switch type {
        case .sentenceEnd: $sentencePauseMultiplierValue
        case .clause: $clausePauseMultiplier
        case .dash: $dashPauseMultiplier
        case .ellipsis: $ellipsisPauseMultiplier
        case .bracket: $bracketPauseMultiplier
        }
    }

    /// A multiplier of 1.0 adds no pause, so it reads as "Off" rather than "1.0x".
    private func pauseMultiplierLabel(_ multiplier: Double) -> String {
        multiplier < 1.05 ? "Off" : String(format: "%.1fx", multiplier)
    }

    /// At the minimum (1) smart timing applies to every word — the label makes
    /// that off-state legible instead of showing a cryptic "1+ letters".
    private var minimumWordLengthLabel: String {
        smartTimingMinimumWordLength <= 1 ? "All words" : "\(smartTimingMinimumWordLength)+ letters"
    }

    var body: some View {
        ZStack {
            StrobeTheme.Gradients.mainBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(StrobeTheme.titleFont(size: 24))
                        .foregroundStyle(StrobeTheme.textPrimary)

                    Spacer()

                    // iOS only: on macOS this view lives in a Settings scene,
                    // where dismiss() has no presentation to act on — the
                    // window's own close control is the standard affordance.
                    #if os(iOS)
                    CircleIconButton(systemImage: "xmark", iconSize: 16, padding: 10, accessibilityLabel: "Close") {
                        dismiss()
                    }
                    #endif
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(24)

                ScrollView {
                    VStack(spacing: 24) {
                        // Reading Speed
                        settingCard(title: "Default Speed") {
                            VStack(spacing: 16) {
                                HStack {
                                    // Matches the Text Size card's numeral:
                                    // serif display face in primary white.
                                    Text("\(defaultWPM)")
                                        .font(StrobeTheme.titleFont(size: 32))
                                        .foregroundStyle(StrobeTheme.textPrimary)
                                    Text("WPM")
                                        .font(StrobeTheme.bodyFont(size: 16))
                                        .foregroundStyle(StrobeTheme.textSecondary)
                                        .padding(.bottom, 6)
                                    Spacer()
                                }

                                snappingSlider(
                                    value: $wpmSliderValue,
                                    in: ReaderSettings.wpmRange,
                                    step: ReaderSettings.wpmStep,
                                    accessibilityLabel: "Default words per minute",
                                    accessibilityValue: "\(defaultWPM) words per minute"
                                ) { snapped in
                                    if snapped != defaultWPM {
                                        defaultWPM = snapped
                                    }
                                }

                                Text("Applies to newly added documents — each document keeps its own speed afterward.")
                                    .font(StrobeTheme.bodyFont(size: 11))
                                    .foregroundStyle(StrobeTheme.textSecondary.opacity(0.7))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        // Font Size
                        settingCard(title: "Text Size") {
                            VStack(spacing: 16) {
                                HStack {
                                    Text("\(fontSize)")
                                        .font(StrobeTheme.titleFont(size: 32))
                                        .foregroundStyle(StrobeTheme.textPrimary)
                                    Text("pt")
                                        .font(StrobeTheme.bodyFont(size: 16))
                                        .foregroundStyle(StrobeTheme.textSecondary)
                                        .padding(.bottom, 6)
                                    Spacer()
                                }

                                snappingSlider(
                                    value: $fontSizeSliderValue,
                                    in: 24...72,
                                    step: 2,
                                    accessibilityLabel: "Reader text size",
                                    accessibilityValue: "\(fontSize) points"
                                ) { snapped in
                                    if snapped != fontSize {
                                        fontSize = snapped
                                    }
                                }
                            }
                        }

                        // Style
                        settingCard(title: "Font") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(ReaderFont.allCases) { fontOption in
                                        fontButton(fontOption: fontOption)
                                    }
                                }
                                .padding(.horizontal, 2) // Add tiny padding to prevent clipping at exact edges
                            }
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .black, location: 0.1),
                                        .init(color: .black, location: 0.9),
                                        .init(color: .clear, location: 1)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }

                        // Text tone
                        settingCard(title: "Text Color") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    ForEach(ReaderTextTone.allCases) { tone in
                                        toneButton(tone: tone)
                                    }
                                }

                                Text("Softer tones are easier on the eyes when reading in the dark.")
                                    .font(StrobeTheme.bodyFont(size: 11))
                                    .foregroundStyle(StrobeTheme.textSecondary.opacity(0.7))
                            }
                        }

                        // Display
                        settingCard(title: "Reading Display") {
                            VStack(spacing: 16) {
                                Toggle(isOn: $trueBlackBackgroundEnabled) {
                                    VStack(alignment: .leading) {
                                        Text("True Black Background")
                                            .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                            .foregroundStyle(StrobeTheme.textPrimary)
                                        Text("Pure black behind the words, for reading in the dark")
                                            .font(StrobeTheme.bodyFont(size: 12))
                                            .foregroundStyle(StrobeTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .tint(StrobeTheme.accent)

                                Divider().background(StrobeTheme.surface)

                                Toggle(isOn: $readingHeaderTitleEnabled) {
                                    VStack(alignment: .leading) {
                                        Text("Title While Reading")
                                            .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                            .foregroundStyle(StrobeTheme.textPrimary)
                                        Text("Shows the document's title faintly at the top")
                                            .font(StrobeTheme.bodyFont(size: 12))
                                            .foregroundStyle(StrobeTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .tint(StrobeTheme.accent)

                                Divider().background(StrobeTheme.surface)

                                Toggle(isOn: $readingHeaderChapterEnabled) {
                                    VStack(alignment: .leading) {
                                        Text("Chapter While Reading")
                                            .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                            .foregroundStyle(StrobeTheme.textPrimary)
                                        Text("Shows the current chapter faintly at the top")
                                            .font(StrobeTheme.bodyFont(size: 12))
                                            .foregroundStyle(StrobeTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .tint(StrobeTheme.accent)
                            }
                            .toggleStyle(.switch)
                        }

                        // Behavior
                        settingCard(title: "Reading Behavior") {
                            VStack(spacing: 16) {
                                Toggle(isOn: $smartTimingEnabled) {
                                    VStack(alignment: .leading) {
                                        Text("Smart Timing")
                                            .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                            .foregroundStyle(StrobeTheme.textPrimary)
                                        Text("Longer words stay on screen longer")
                                            .font(StrobeTheme.bodyFont(size: 12))
                                            .foregroundStyle(StrobeTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .tint(StrobeTheme.accent)

                                if smartTimingEnabled {
                                    VStack(spacing: 8) {
                                        HStack {
                                            Text("Slowdown per letter")
                                                .font(StrobeTheme.bodyFont(size: 14))
                                                .foregroundStyle(StrobeTheme.textSecondary)
                                            Spacer()
                                            Text("\(Int(smartTimingPercentPerLetter))%")
                                                .font(StrobeTheme.bodyFont(size: 14, bold: true))
                                                .foregroundStyle(StrobeTheme.textPrimary)
                                        }
                                        Slider(value: $smartTimingPercentPerLetter, in: 0...50, step: 1)
                                            .tint(StrobeTheme.accent)
                                            .frame(minHeight: 44)
                                            .accessibilityLabel("Slowdown per letter")
                                            .accessibilityValue("\(Int(smartTimingPercentPerLetter)) percent")

                                        HStack {
                                            Text("Minimum word length")
                                                .font(StrobeTheme.bodyFont(size: 14))
                                                .foregroundStyle(StrobeTheme.textSecondary)
                                            Spacer()
                                            Text(minimumWordLengthLabel)
                                                .font(StrobeTheme.bodyFont(size: 14, bold: true))
                                                .foregroundStyle(StrobeTheme.textPrimary)
                                        }
                                        .padding(.top, 8)
                                        Slider(value: smartTimingMinimumWordLengthSlider, in: 1...15, step: 1)
                                            .tint(StrobeTheme.accent)
                                            .frame(minHeight: 44)
                                            .accessibilityLabel("Minimum word length")
                                            .accessibilityValue(smartTimingMinimumWordLength <= 1
                                                ? "All words"
                                                : "\(smartTimingMinimumWordLength) or more letters")
                                        Text("Shorter words show at your exact speed.")
                                            .font(StrobeTheme.bodyFont(size: 11))
                                            .foregroundStyle(StrobeTheme.textSecondary.opacity(0.7))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.leading, 4)
                                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                                }

                                Divider().background(StrobeTheme.surface)

                                Toggle(isOn: $sentencePauseEnabled) {
                                    VStack(alignment: .leading) {
                                        Text("Punctuation Pauses")
                                            .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                            .foregroundStyle(StrobeTheme.textPrimary)
                                        Text("Brief pause after punctuation marks")
                                            .font(StrobeTheme.bodyFont(size: 12))
                                            .foregroundStyle(StrobeTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .tint(StrobeTheme.accent)

                                if sentencePauseEnabled {
                                    punctuationPauseControls
                                        .padding(.leading, 4)
                                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                                }
                                Divider().background(StrobeTheme.surface)

                                Toggle(isOn: $complexityTimingEnabled) {
                                    VStack(alignment: .leading) {
                                        Text("Complexity Timing")
                                            .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                            .foregroundStyle(StrobeTheme.textPrimary)
                                        Text("Adapts speed to word difficulty, not just length")
                                            .font(StrobeTheme.bodyFont(size: 12))
                                            .foregroundStyle(StrobeTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .tint(StrobeTheme.accent)

                                if complexityTimingEnabled {
                                    VStack(spacing: 8) {
                                        HStack {
                                            Text("Intensity")
                                                .font(StrobeTheme.bodyFont(size: 14))
                                                .foregroundStyle(StrobeTheme.textSecondary)
                                            Spacer()
                                            Text("\(Int(complexityIntensity * 100))%")
                                                .font(StrobeTheme.bodyFont(size: 14, bold: true))
                                                .foregroundStyle(StrobeTheme.textPrimary)
                                        }
                                        Slider(value: $complexityIntensity, in: 0...1, step: 0.05)
                                            .tint(StrobeTheme.accent)
                                            .frame(minHeight: 44)
                                            .accessibilityLabel("Complexity intensity")
                                            .accessibilityValue("\(Int(complexityIntensity * 100)) percent")
                                        Text("How much to speed up common words and slow down rare ones. Higher = more variation.")
                                            .font(StrobeTheme.bodyFont(size: 11))
                                            .foregroundStyle(StrobeTheme.textSecondary.opacity(0.7))
                                    }
                                    .padding(.leading, 4)
                                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                                }

                                #if os(iOS)
                                Divider().background(StrobeTheme.surface)

                                Toggle(isOn: $holdToReadEnabled) {
                                    VStack(alignment: .leading) {
                                        Text("Hold to Read")
                                            .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                            .foregroundStyle(StrobeTheme.textPrimary)
                                        Text(holdToReadEnabled
                                             ? "Hold the screen to read, release to pause"
                                             : "Tap once to play, tap again to pause — hands-free")
                                            .font(StrobeTheme.bodyFont(size: 12))
                                            .foregroundStyle(StrobeTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .tint(StrobeTheme.accent)

                                if holdToReadEnabled {
                                    Toggle(isOn: $holdSpeedAdjustEnabled) {
                                        VStack(alignment: .leading) {
                                            Text("Drag to Adjust Speed")
                                                .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                                .foregroundStyle(StrobeTheme.textPrimary)
                                            Text("While holding to read, drag up or down to change speed")
                                                .font(StrobeTheme.bodyFont(size: 12))
                                                .foregroundStyle(StrobeTheme.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .tint(StrobeTheme.accent)
                                    .padding(.leading, 4)
                                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                                }
                                #endif
                                #if os(macOS)
                                Divider().background(StrobeTheme.surface)

                                Toggle(isOn: $holdSpeedAdjustEnabled) {
                                    VStack(alignment: .leading) {
                                        Text("Drag to Adjust Speed")
                                            .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                            .foregroundStyle(StrobeTheme.textPrimary)
                                        Text("While reading, click-drag up or down to change speed")
                                            .font(StrobeTheme.bodyFont(size: 12))
                                            .foregroundStyle(StrobeTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .tint(StrobeTheme.accent)
                                #endif
                            }
                            .toggleStyle(.switch)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: smartTimingEnabled)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: sentencePauseEnabled)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: complexityTimingEnabled)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: holdToReadEnabled)
                        }

                        // Text Cleaning
                        settingCard(title: "Text Processing") {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(isOn: textCleaningEnabled) {
                                    VStack(alignment: .leading) {
                                        Text("Text Cleaning")
                                            .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                            .foregroundStyle(StrobeTheme.textPrimary)
                                        Text("Removes page numbers, headers, footers, and common boilerplate")
                                            .font(StrobeTheme.bodyFont(size: 12))
                                            .foregroundStyle(StrobeTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .tint(StrobeTheme.accent)
                                .toggleStyle(.switch)

                                Text("Applies to new imports only — existing documents aren't re-processed.")
                                    .font(StrobeTheme.bodyFont(size: 11))
                                    .foregroundStyle(StrobeTheme.textSecondary.opacity(0.7))
                            }
                        }

                        // Replay Tutorial
                        Button {
                            showTutorial = true
                        } label: {
                            navigationRowLabel(
                                icon: "arrow.counterclockwise",
                                title: "Replay Tutorial",
                                trailingIcon: "chevron.right"
                            )
                        }
                        .buttonStyle(.plain)

                        // Source Code
                        Link(destination: URL(string: "https://github.com/Cuzeth/Rapid-Serial-Visual-Presentation")!) {
                            navigationRowLabel(
                                icon: "chevron.left.forwardslash.chevron.right",
                                title: "View Source Code",
                                trailingIcon: "arrow.up.right"
                            )
                        }

                        Text(appVersionLabel)
                            .font(StrobeTheme.bodyFont(size: 12))
                            .foregroundStyle(StrobeTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                    .padding(24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            wpmSliderValue = Double(defaultWPM)
            fontSizeSliderValue = Double(fontSize)
        }
        .tutorialCover(isPresented: $showTutorial)
    }

    // MARK: - Components

    /// A selector button per punctuation type above the one slider that edits
    /// the selected type's multiplier.
    private var punctuationPauseControls: some View {
        let multiplier = pauseMultiplier(for: selectedPauseType)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(PauseType.allCases) { type in
                    pauseTypeButton(type: type)
                }
            }

            HStack {
                Text(selectedPauseType.title)
                    .font(StrobeTheme.bodyFont(size: 14))
                    .foregroundStyle(StrobeTheme.textSecondary)
                Spacer()
                Text(pauseMultiplierLabel(multiplier.wrappedValue))
                    .font(StrobeTheme.bodyFont(size: 14, bold: true))
                    .foregroundStyle(StrobeTheme.textPrimary)
            }
            .padding(.top, 8)
            Slider(value: multiplier, in: 1...4, step: 0.1)
                .tint(StrobeTheme.accent)
                .frame(minHeight: 44)
                .accessibilityLabel("\(selectedPauseType.title) pause multiplier")
                .accessibilityValue(pauseMultiplierLabel(multiplier.wrappedValue))
            Text("Words with several marks get the longest pause.")
                .font(StrobeTheme.bodyFont(size: 11))
                .foregroundStyle(StrobeTheme.textSecondary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pauseTypeButton(type: PauseType) -> some View {
        let isSelected = selectedPauseType == type
        let label = pauseMultiplierLabel(pauseMultiplier(for: type).wrappedValue)
        return Button {
            selectedPauseType = type
        } label: {
            VStack(spacing: 2) {
                Text(type.sample)
                    .font(StrobeTheme.bodyFont(size: 16, bold: true))
                    .foregroundStyle(StrobeTheme.textPrimary)
                Text(label)
                    .font(StrobeTheme.bodyFont(size: 11))
                    .foregroundStyle(StrobeTheme.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
            .background(StrobeTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? StrobeTheme.accent : StrobeTheme.textSecondary.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.title)
        .accessibilityValue(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// A stepped settings slider with haptic-on-release, integer snapping via
    /// `onSnap`, and min/max range labels derived from `range`.
    private func snappingSlider(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        accessibilityLabel: String,
        accessibilityValue: String,
        onSnap: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 4) {
            // Haptic fires once on release rather than on
            // every tick of the drag.
            Slider(value: value, in: range, step: step) { editing in
                if !editing {
                    HapticManager.shared.selectionTick()
                }
            }
            .tint(StrobeTheme.accent)
            .frame(minHeight: 44)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .onChange(of: value.wrappedValue) { _, newValue in
                onSnap(Int(newValue))
            }

            sliderRangeLabels(
                min: String(Int(range.lowerBound)),
                max: String(Int(range.upperBound))
            )
        }
    }

    /// Row chrome shared by "Replay Tutorial" and "View Source Code": leading
    /// icon, bold title, and a trailing affordance icon on a surface card.
    private func navigationRowLabel(icon: String, title: String, trailingIcon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
            Text(title)
                .font(StrobeTheme.bodyFont(size: 16, bold: true))
            Spacer()
            Image(systemName: trailingIcon)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(StrobeTheme.textPrimary)
        .padding(16)
        .background(StrobeTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func sliderRangeLabels(min: String, max: String) -> some View {
        HStack {
            Text(min)
            Spacer()
            Text(max)
        }
        .font(StrobeTheme.bodyFont(size: 11))
        .foregroundStyle(StrobeTheme.textSecondary.opacity(0.7))
        .accessibilityHidden(true)
    }

    private func settingCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(StrobeTheme.bodyFont(size: 14, bold: true))
                .foregroundStyle(StrobeTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(1)

            content()
        }
        .padding(20)
        .background(StrobeTheme.Gradients.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func fontButton(fontOption: ReaderFont) -> some View {
        let isSelected = readerFontSelection == fontOption.rawValue
        return Button {
            readerFontSelection = fontOption.rawValue
        } label: {
            Text(fontOption.displayName)
                .font(fontOption.regularFont(size: 17))
                .foregroundStyle(isSelected ? .white : StrobeTheme.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(isSelected ? StrobeTheme.accent : StrobeTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.clear : StrobeTheme.textSecondary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        // Selection is otherwise color-only — invisible to VoiceOver.
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// A tone swatch rendered the way the reader draws a word: the name in
    /// the tone's text color on the reader background, with the ORP letter in
    /// the tone's anchor color.
    private func toneButton(tone: ReaderTextTone) -> some View {
        let isSelected = readerTextToneSelection == tone.rawValue
        return Button {
            readerTextToneSelection = tone.rawValue
        } label: {
            Text(toneSample(for: tone))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .padding(.vertical, 12)
                .background { ReaderBackdrop() }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ? StrobeTheme.accent : StrobeTheme.textSecondary.opacity(0.2),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tone.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func toneSample(for tone: ReaderTextTone) -> AttributedString {
        let font = ReaderFont.resolve(readerFontSelection)
        var sample = AttributedString(tone.displayName)
        sample.font = font.regularFont(size: 15)
        sample.foregroundColor = tone.textColor

        let anchorOffset = WordView.orpLetterPosition(letterCount: tone.displayName.count)
        let anchorStart = sample.index(sample.startIndex, offsetByCharacters: anchorOffset)
        let anchorEnd = sample.index(anchorStart, offsetByCharacters: 1)
        sample[anchorStart..<anchorEnd].foregroundColor = tone.anchorColor
        sample[anchorStart..<anchorEnd].font = font.boldFont(size: 15)
        return sample
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "x.x"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "x"
        return "Strobe v\(version) (\(build))"
    }
}
