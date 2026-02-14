import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultWPM") private var defaultWPM: Int = 300
    @AppStorage("fontSize") private var fontSize: Int = 40
    @AppStorage("appearance") private var appearance: Int = 0
    @AppStorage("smartTimingEnabled") private var smartTimingEnabled: Bool = false
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var wpmSliderValue: Double = 300
    @State private var fontSizeSliderValue: Double = 40

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(defaultWPM) WPM")
                            .font(readerFont.regularFont(size: 14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(8)

                        Slider(
                            value: $wpmSliderValue,
                            in: 100...1000,
                            step: 10
                        )
                        .tint(.red)
                        .onChange(of: wpmSliderValue) { _, newValue in
                            let snapped = Int(newValue)
                            if snapped != defaultWPM {
                                defaultWPM = snapped
                                HapticManager.shared.wpmChanged()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Default WPM")
                        .font(readerFont.regularFont(size: 12))
                } footer: {
                    Text("Applied to newly imported documents.")
                        .font(readerFont.regularFont(size: 11))
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(fontSize) pt")
                            .font(readerFont.regularFont(size: 14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(8)

                        Slider(
                            value: $fontSizeSliderValue,
                            in: 24...72,
                            step: 2
                        )
                        .tint(.red)
                        .onChange(of: fontSizeSliderValue) { _, newValue in
                            let snapped = Int(newValue)
                            if snapped != fontSize {
                                fontSize = snapped
                                HapticManager.shared.wpmChanged()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Text Size")
                        .font(readerFont.regularFont(size: 12))
                } footer: {
                    Text("Size of words during reading.")
                        .font(readerFont.regularFont(size: 11))
                }

                Section {
                    Picker(selection: $appearance) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    } label: {
                        Text("Theme")
                            .font(readerFont.regularFont(size: 16))
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Appearance")
                        .font(readerFont.regularFont(size: 12))
                }

                Section {
                    Picker("Reading Font", selection: $readerFontSelection) {
                        ForEach(ReaderFont.allCases) { fontOption in
                            Text(fontOption.displayName)
                                .font(fontOption.regularFont(size: 16))
                                .tag(fontOption.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Font")
                        .font(readerFont.regularFont(size: 12))
                } footer: {
                    Text("Available: Inter, PT Sans, PT Serif, PT Mono, JetBrains Mono.")
                        .font(readerFont.regularFont(size: 11))
                }

                Section {
                    Toggle(isOn: $smartTimingEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Smart Time Adjustments")
                                .font(readerFont.regularFont(size: 16))
                            Text("Longer words stay on screen slightly longer.")
                                .font(readerFont.regularFont(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.red)
                } header: {
                    Text("Reading")
                        .font(readerFont.regularFont(size: 12))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                wpmSliderValue = Double(defaultWPM)
                fontSizeSliderValue = Double(fontSize)
            }
        }
    }
}
