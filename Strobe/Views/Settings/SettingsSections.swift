import SwiftUI

// MARK: - Rows

/// A settings row: a title and the current value above a stepped slider,
/// with a haptic tick when the slider is let go.
struct SettingsSliderRow<Title: View>: View {
    let value: String
    let accessibilityLabel: String
    let accessibilityValue: String
    @Binding var sliderValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let title: Title

    init(
        value: String,
        accessibilityLabel: String,
        accessibilityValue: String? = nil,
        sliderValue: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        @ViewBuilder title: () -> Title
    ) {
        self.value = value
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue ?? value
        self._sliderValue = sliderValue
        self.range = range
        self.step = step
        self.title = title()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                title
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityHidden(true)

            Slider(value: $sliderValue, in: range, step: step) { editing in
                if !editing {
                    HapticManager.shared.selectionTick()
                }
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
        }
        .padding(.vertical, 2)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}

extension SettingsSliderRow where Title == Text {
    init(
        _ title: String,
        value: String,
        accessibilityValue: String? = nil,
        sliderValue: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double
    ) {
        self.init(
            value: value,
            accessibilityLabel: title,
            accessibilityValue: accessibilityValue,
            sliderValue: sliderValue,
            in: range,
            step: step
        ) {
            Text(title)
        }
    }
}

/// An `Int` setting as the `Double` a `Slider` edits.
private func sliderBinding(_ value: Binding<Int>) -> Binding<Double> {
    Binding(
        get: { Double(value.wrappedValue) },
        set: { value.wrappedValue = Int($0.rounded()) }
    )
}

// MARK: - Reading

/// The word "Strobe" as the reader draws it, in the current font, size,
/// color, and background, so appearance changes show as they're made.
struct ReaderPreview: View {
    @AppStorage(ReaderSettings.Keys.fontSize) private var fontSize: Int = ReaderSettings.Defaults.fontSize
    @AppStorage(ReaderSettings.Keys.contextWordsEnabled) private var contextWordsEnabled: Bool = ReaderSettings.Defaults.contextWordsEnabled

    var body: some View {
        WordView(
            word: "Strobe",
            fontSize: CGFloat(fontSize),
            context: contextWordsEnabled ? ContextWords.Neighbors(previous: "read", next: "faster") : nil
        )
        .frame(maxWidth: .infinity)
        .background { ReaderBackdrop() }
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview")
        .accessibilityValue("Strobe, \(fontSize) points")
    }
}

/// Speed, size, font, color, and background.
struct ReadingAppearanceSection: View {
    @AppStorage(ReaderSettings.Keys.defaultWPM) private var defaultWPM: Int = ReaderSettings.Defaults.defaultWPM
    @AppStorage(ReaderSettings.Keys.fontSize) private var fontSize: Int = ReaderSettings.Defaults.fontSize
    @AppStorage(ReaderSettings.Keys.trueBlackBackgroundEnabled) private var trueBlackBackgroundEnabled: Bool = ReaderSettings.Defaults.trueBlackBackgroundEnabled
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue
    @AppStorage(ReaderTextTone.storageKey) private var readerTextToneSelection = ReaderTextTone.defaultValue.rawValue

    var body: some View {
        Section {
            SettingsSliderRow(
                "Default Speed",
                value: "\(defaultWPM) wpm",
                accessibilityValue: "\(defaultWPM) words per minute",
                sliderValue: sliderBinding($defaultWPM),
                in: ReaderSettings.wpmRange,
                step: ReaderSettings.wpmStep
            )

            SettingsSliderRow(
                "Text Size",
                value: "\(fontSize) pt",
                accessibilityValue: "\(fontSize) points",
                sliderValue: sliderBinding($fontSize),
                in: 24...72,
                step: 2
            )

            Picker("Font", selection: $readerFontSelection) {
                ForEach(ReaderFont.allCases) { font in
                    Text(font.displayName)
                        .font(font.regularFont(size: 17))
                        .tag(font.rawValue)
                }
            }
            #if os(iOS)
            .pickerStyle(.navigationLink)
            #endif

            ToneRow(selection: $readerTextToneSelection, font: ReaderFont.resolve(readerFontSelection))

            Toggle(isOn: $trueBlackBackgroundEnabled) {
                Text("True Black Background")
                Text("Pure black behind the words, for reading in the dark")
            }
        } header: {
            Text("Reading")
        } footer: {
            Text("Speed applies to documents you add from now on. Each document remembers its own speed.")
        }
    }
}

/// The text color choices, each drawn the way the reader draws a word: the
/// name in the tone's color on the reader background, with the anchor
/// letter in the tone's anchor color.
private struct ToneRow: View {
    @Binding var selection: String
    let font: ReaderFont

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Text Color")
            HStack(spacing: 8) {
                ForEach(ReaderTextTone.allCases) { tone in
                    toneButton(tone)
                }
            }
        }
        .padding(.vertical, 4)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    private func toneButton(_ tone: ReaderTextTone) -> some View {
        let isSelected = selection == tone.rawValue
        return Button {
            selection = tone.rawValue
        } label: {
            Text(sample(for: tone))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .padding(.vertical, 12)
                .background { ReaderBackdrop() }
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? StrobeTheme.accent : Color.white.opacity(0.14),
                            lineWidth: isSelected ? 2 : 0.5
                        )
                }
                .contentShape(.rect(cornerRadius: 10))
        }
        // Each swatch keeps its own tap target inside the form row.
        .buttonStyle(.plain)
        .accessibilityLabel(tone.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func sample(for tone: ReaderTextTone) -> AttributedString {
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
}

// MARK: - Controls

/// How playback is started and how speed changes mid-read.
struct ReadingControlsSection: View {
    @AppStorage(ReaderSettings.Keys.holdToReadEnabled) private var holdToReadEnabled: Bool = ReaderSettings.Defaults.holdToReadEnabled
    @AppStorage(ReaderSettings.Keys.holdSpeedAdjustEnabled) private var holdSpeedAdjustEnabled: Bool = ReaderSettings.Defaults.holdSpeedAdjustEnabled

    var body: some View {
        Section {
            #if os(iOS)
            Toggle("Hold to Read", isOn: $holdToReadEnabled.animation())
            if holdToReadEnabled {
                Toggle("Drag to Change Speed", isOn: $holdSpeedAdjustEnabled)
            }
            #else
            Toggle("Drag to Change Speed", isOn: $holdSpeedAdjustEnabled)
            #endif
        } header: {
            Text("Controls")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        #if os(iOS)
        guard holdToReadEnabled else {
            return "Tap the screen to start reading and tap again to pause."
        }
        return holdSpeedAdjustEnabled
            ? "Hold the screen to read and let go to pause. While holding, drag up or down to change speed."
            : "Hold the screen to read and let go to pause."
        #else
        return "While reading, click and drag up or down to change speed."
        #endif
    }
}

// MARK: - While reading

/// Optional text shown around the word.
struct WhileReadingSections: View {
    @AppStorage(ReaderSettings.Keys.readingHeaderTitleEnabled) private var readingHeaderTitleEnabled: Bool = ReaderSettings.Defaults.readingHeaderTitleEnabled
    @AppStorage(ReaderSettings.Keys.readingHeaderChapterEnabled) private var readingHeaderChapterEnabled: Bool = ReaderSettings.Defaults.readingHeaderChapterEnabled
    @AppStorage(ReaderSettings.Keys.contextWordsEnabled) private var contextWordsEnabled: Bool = ReaderSettings.Defaults.contextWordsEnabled
    @AppStorage(ReaderSettings.Keys.enclosingMarksEnabled) private var enclosingMarksEnabled: Bool = ReaderSettings.Defaults.enclosingMarksEnabled

    var body: some View {
        Section {
            Toggle(isOn: $readingHeaderTitleEnabled) {
                Text("Document Title")
                Text("Faintly at the top while words play")
            }
            Toggle(isOn: $readingHeaderChapterEnabled) {
                Text("Current Chapter")
                Text("Faintly at the top while words play")
            }
        } header: {
            Text("Top of the Screen")
        }

        Section {
            Toggle(isOn: $contextWordsEnabled) {
                Text("Previous and Next Words")
                Text("Beside the word, readable only while paused")
            }
            Toggle(isOn: $enclosingMarksEnabled) {
                Text("Open Quotes and Parentheses")
                Text("Faintly above the word until they close")
            }
        } header: {
            Text("Around the Word")
        }
    }
}

// MARK: - Importing

struct ImportSettingsSection: View {
    @AppStorage(TextCleaningLevel.storageKey) private var textCleaningLevel = TextCleaningLevel.defaultValue.rawValue

    private var textCleaningEnabled: Binding<Bool> {
        Binding(
            get: { textCleaningLevel == TextCleaningLevel.standard.rawValue },
            set: { textCleaningLevel = $0 ? TextCleaningLevel.standard.rawValue : TextCleaningLevel.none.rawValue }
        )
    }

    var body: some View {
        Section {
            Toggle(isOn: textCleaningEnabled) {
                Text("Clean Up Text")
                Text("Removes page numbers, headers, footers, and common boilerplate")
            }
        } header: {
            Text("Importing")
        } footer: {
            Text("Applies to new imports. Documents already in your library don't change.")
        }
    }
}

// MARK: - About

struct AboutSection: View {
    @Binding var showWelcome: Bool

    var body: some View {
        Section {
            Button("Show Welcome Screen") {
                showWelcome = true
            }
            .tint(.primary)
            Link(destination: URL(string: "https://github.com/Cuzeth/Rapid-Serial-Visual-Presentation")!) {
                HStack {
                    Text("Source Code")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
        } footer: {
            Text(appVersionLabel)
        }
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "x.x"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "x"
        return "Strobe \(version) (\(build))"
    }
}
