import SwiftUI

/// App settings sheet for configuring reading speed, font, text size, and behavior.
struct SettingsView: View {
    @AppStorage(ReaderSettings.Keys.defaultWPM) private var defaultWPM: Int = ReaderSettings.Defaults.defaultWPM
    @AppStorage(ReaderSettings.Keys.fontSize) private var fontSize: Int = ReaderSettings.Defaults.fontSize
    @AppStorage(ReaderSettings.Keys.smartTimingEnabled) private var smartTimingEnabled: Bool = ReaderSettings.Defaults.smartTimingEnabled
    @AppStorage(ReaderSettings.Keys.sentencePauseEnabled) private var sentencePauseEnabled: Bool = ReaderSettings.Defaults.sentencePauseEnabled
    @AppStorage(ReaderSettings.Keys.smartTimingPercentPerLetter) private var smartTimingPercentPerLetter: Double = ReaderSettings.Defaults.smartTimingPercentPerLetter
    @AppStorage(ReaderSettings.Keys.sentencePauseMultiplier) private var sentencePauseMultiplierValue: Double = ReaderSettings.Defaults.sentencePauseMultiplier
    @AppStorage(ReaderSettings.Keys.complexityTimingEnabled) private var complexityTimingEnabled: Bool = ReaderSettings.Defaults.complexityTimingEnabled
    @AppStorage(ReaderSettings.Keys.complexityIntensity) private var complexityIntensity: Double = ReaderSettings.Defaults.complexityIntensity
    @AppStorage(ReaderSettings.Keys.holdToReadEnabled) private var holdToReadEnabled: Bool = ReaderSettings.Defaults.holdToReadEnabled
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue
    @AppStorage(TextCleaningLevel.storageKey) private var textCleaningLevel = TextCleaningLevel.defaultValue.rawValue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var wpmSliderValue: Double = 300
    @State private var fontSizeSliderValue: Double = 40
    @State private var showTutorial = false

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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(StrobeTheme.textSecondary)
                            .padding(10)
                            .background(StrobeTheme.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
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
                                    Text("\(defaultWPM)")
                                        .font(StrobeTheme.bodyFont(size: 32, bold: true))
                                        .foregroundStyle(StrobeTheme.accent)
                                    Text("WPM")
                                        .font(StrobeTheme.bodyFont(size: 16))
                                        .foregroundStyle(StrobeTheme.textSecondary)
                                        .padding(.bottom, 6)
                                    Spacer()
                                }

                                VStack(spacing: 4) {
                                    // Haptic fires once on release rather than on
                                    // every tick of the drag.
                                    Slider(value: $wpmSliderValue, in: 100...1000, step: 10) { editing in
                                        if !editing {
                                            HapticManager.shared.wpmChanged()
                                        }
                                    }
                                    .tint(StrobeTheme.accent)
                                    .frame(minHeight: 44)
                                    .accessibilityLabel("Default words per minute")
                                    .accessibilityValue("\(defaultWPM) words per minute")
                                    .onChange(of: wpmSliderValue) { _, newValue in
                                        let snapped = Int(newValue)
                                        if snapped != defaultWPM {
                                            defaultWPM = snapped
                                        }
                                    }

                                    sliderRangeLabels(min: "100", max: "1000")
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

                                VStack(spacing: 4) {
                                    Slider(value: $fontSizeSliderValue, in: 24...72, step: 2) { editing in
                                        if !editing {
                                            HapticManager.shared.wpmChanged()
                                        }
                                    }
                                    .tint(StrobeTheme.accent)
                                    .frame(minHeight: 44)
                                    .accessibilityLabel("Reader text size")
                                    .accessibilityValue("\(fontSize) points")
                                    .onChange(of: fontSizeSliderValue) { _, newValue in
                                        let snapped = Int(newValue)
                                        if snapped != fontSize {
                                            fontSize = snapped
                                        }
                                    }

                                    sliderRangeLabels(min: "24", max: "72")
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
                                    }
                                    .padding(.leading, 4)
                                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                                }

                                Divider().background(StrobeTheme.surface)

                                Toggle(isOn: $sentencePauseEnabled) {
                                    VStack(alignment: .leading) {
                                        Text("Sentence Pauses")
                                            .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                            .foregroundStyle(StrobeTheme.textPrimary)
                                        Text("Brief pause at sentence-ending punctuation")
                                            .font(StrobeTheme.bodyFont(size: 12))
                                            .foregroundStyle(StrobeTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .tint(StrobeTheme.accent)

                                if sentencePauseEnabled {
                                    VStack(spacing: 8) {
                                        HStack {
                                            Text("Pause multiplier")
                                                .font(StrobeTheme.bodyFont(size: 14))
                                                .foregroundStyle(StrobeTheme.textSecondary)
                                            Spacer()
                                            Text(String(format: "%.1fx", sentencePauseMultiplierValue))
                                                .font(StrobeTheme.bodyFont(size: 14, bold: true))
                                                .foregroundStyle(StrobeTheme.textPrimary)
                                        }
                                        Slider(value: $sentencePauseMultiplierValue, in: 1...4, step: 0.1)
                                            .tint(StrobeTheme.accent)
                                            .frame(minHeight: 44)
                                            .accessibilityLabel("Sentence pause multiplier")
                                            .accessibilityValue(String(format: "%.1fx", sentencePauseMultiplierValue))
                                    }
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
                                #endif
                            }
                            .toggleStyle(.switch)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: smartTimingEnabled)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: sentencePauseEnabled)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: complexityTimingEnabled)
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
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 16))
                                Text("Replay Tutorial")
                                    .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                Spacer()
                                Image(systemName: "chevron.right")
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
                        .buttonStyle(.plain)

                        // Source Code
                        Link(destination: URL(string: "https://github.com/Cuzeth/Rapid-Serial-Visual-Presentation")!) {
                            HStack(spacing: 10) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 16))
                                Text("View Source Code")
                                    .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                Spacer()
                                Image(systemName: "arrow.up.right")
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
        #if os(iOS)
        .fullScreenCover(isPresented: $showTutorial) {
            TutorialView()
        }
        #else
        .sheet(isPresented: $showTutorial) {
            TutorialView()
                .frame(minWidth: 600, minHeight: 500)
        }
        #endif
    }

    // MARK: - Components

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
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "x.x"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "x"
        return "Strobe v\(version) (\(build))"
    }
}
