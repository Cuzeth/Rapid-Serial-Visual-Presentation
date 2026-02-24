import SwiftUI

/// App settings sheet for configuring reading speed, font, text size, and behavior.
struct SettingsView: View {
    @AppStorage("defaultWPM") private var defaultWPM: Int = 300
    @AppStorage("fontSize") private var fontSize: Int = 40
    @AppStorage("smartTimingEnabled") private var smartTimingEnabled: Bool = false
    @AppStorage("sentencePauseEnabled") private var sentencePauseEnabled: Bool = false
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue
    @AppStorage(TextCleaningLevel.storageKey) private var textCleaningLevel = TextCleaningLevel.defaultValue.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var wpmSliderValue: Double = 300
    @State private var fontSizeSliderValue: Double = 40

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
    }

    private var currentCleaningLevel: TextCleaningLevel {
        TextCleaningLevel.resolve(textCleaningLevel)
    }

    var body: some View {
        ZStack {
            StrobeTheme.Gradients.mainBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(readerFont.boldFont(size: 24))
                        .foregroundStyle(StrobeTheme.textPrimary)
                    
                    Spacer()
                    
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
                }
                .padding(24)

                ScrollView {
                    VStack(spacing: 24) {
                        // Reading Speed
                        settingCard(title: "Default Speed") {
                            VStack(spacing: 16) {
                                HStack {
                                    Text("\(defaultWPM)")
                                        .font(readerFont.boldFont(size: 32))
                                        .foregroundStyle(StrobeTheme.accent)
                                    Text("WPM")
                                        .font(readerFont.regularFont(size: 16))
                                        .foregroundStyle(StrobeTheme.textSecondary)
                                        .padding(.bottom, 6)
                                    Spacer()
                                }
                                
                                Slider(value: $wpmSliderValue, in: 100...1000, step: 10)
                                    .tint(StrobeTheme.accent)
                                    .onChange(of: wpmSliderValue) { _, newValue in
                                        let snapped = Int(newValue)
                                        if snapped != defaultWPM {
                                            defaultWPM = snapped
                                            HapticManager.shared.wpmChanged()
                                        }
                                    }
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
                                
                                Slider(value: $fontSizeSliderValue, in: 24...72, step: 2)
                                    .tint(StrobeTheme.accent)
                                    .onChange(of: fontSizeSliderValue) { _, newValue in
                                        let snapped = Int(newValue)
                                        if snapped != fontSize {
                                            fontSize = snapped
                                            HapticManager.shared.wpmChanged()
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

                        // Behavior
                        settingCard(title: "Reading Behavior") {
                            VStack(spacing: 16) {
                                Toggle(isOn: $smartTimingEnabled) {
                                    VStack(alignment: .leading) {
                                        Text("Smart Timing")
                                            .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                            .foregroundStyle(StrobeTheme.textPrimary)
                                        Text("Adjusts speed based on word length")
                                            .font(StrobeTheme.bodyFont(size: 12))
                                            .foregroundStyle(StrobeTheme.textSecondary)
                                    }
                                }
                                .tint(StrobeTheme.accent)

                                Divider().background(StrobeTheme.surface)

                                Toggle(isOn: $sentencePauseEnabled) {
                                    VStack(alignment: .leading) {
                                        Text("Sentence Pauses")
                                            .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                            .foregroundStyle(StrobeTheme.textPrimary)
                                        Text("Pauses at punctuation")
                                            .font(StrobeTheme.bodyFont(size: 12))
                                            .foregroundStyle(StrobeTheme.textSecondary)
                                    }
                                }
                                .tint(StrobeTheme.accent)
                            }
                        }
                        
                        // Text Cleaning
                        settingCard(title: "Text Processing") {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("Cleaning", selection: $textCleaningLevel) {
                                    ForEach(TextCleaningLevel.allCases) { level in
                                        Text(level.displayName).tag(level.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                
                                Text(currentCleaningLevel.description)
                                    .font(StrobeTheme.bodyFont(size: 12))
                                    .foregroundStyle(StrobeTheme.textSecondary)
                            }
                        }

                        // Support
                        Link(destination: URL(string: "https://buymeacoffee.com/cuzeth")!) {
                            HStack(spacing: 10) {
                                Image(systemName: "cup.and.heat.waves.fill")
                                    .font(.system(size: 16))
                                Text("Buy Me a Coffee")
                                    .font(StrobeTheme.bodyFont(size: 16, bold: true))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(16)
                            .background(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), lineWidth: 1)
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
                }
            }
        }
        .onAppear {
            wpmSliderValue = Double(defaultWPM)
            fontSizeSliderValue = Double(fontSize)
        }
    }

    // MARK: - Components

    private func settingCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(readerFont.boldFont(size: 14))
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
                .font(fontOption.regularFont(size: 14))
                .foregroundStyle(isSelected ? .white : StrobeTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? StrobeTheme.accent : StrobeTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.clear : StrobeTheme.textSecondary.opacity(0.2), lineWidth: 1)
                )
        }
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "x.x"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "x"
        return "Strobe v\(version) (\(build))"
    }
}
