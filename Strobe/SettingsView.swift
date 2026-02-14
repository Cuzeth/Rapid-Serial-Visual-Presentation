import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultWPM") private var defaultWPM: Int = 300
    @AppStorage("appearance") private var appearance: Int = 0
    @Environment(\.dismiss) private var dismiss

    @State private var wpmSliderValue: Double = 300

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(defaultWPM) WPM")
                            .font(.custom("JetBrainsMono-Regular", size: 14))
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
                        .font(.custom("JetBrainsMono-Regular", size: 12))
                } footer: {
                    Text("Applied to newly imported documents.")
                        .font(.custom("JetBrainsMono-Regular", size: 11))
                }

                Section {
                    Picker(selection: $appearance) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    } label: {
                        Text("Theme")
                            .font(.custom("JetBrainsMono-Regular", size: 16))
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Appearance")
                        .font(.custom("JetBrainsMono-Regular", size: 12))
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
            }
        }
    }
}
