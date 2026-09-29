import SwiftUI

/// The share sheet: the shared text's title and opening lines with its
/// length, and Cancel and Add. Adding leaves the text for the app, which
/// puts it in the library the next time it's open.
struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        container
            .preferredColorScheme(.dark)
            .tint(StrobeTheme.accent)
            .animation(.easeInOut(duration: 0.2), value: model.phase)
            .alert("Couldn't Add to Strobe", isPresented: addErrorIsPresented) {
                Button("OK") { model.addError = nil }
            } message: {
                Text(model.addError ?? "")
            }
            .onChange(of: model.phase) { _, phase in
                if phase == .added {
                    AccessibilityNotification.Announcement("Added to Library").post()
                }
            }
    }

    private var addErrorIsPresented: Binding<Bool> {
        Binding(
            get: { model.addError != nil },
            set: { if !$0 { model.addError = nil } }
        )
    }

    // MARK: - Layout

    // iOS presents the extension as a sheet with a navigation bar; the Mac
    // shows it as a panel with its buttons along the bottom, like its other
    // share sheets.
    @ViewBuilder
    private var container: some View {
        #if os(iOS)
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { StrobeTheme.background.ignoresSafeArea() }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if model.phase == .ready {
                        wordCountLabel
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.bar)
                    }
                }
                .navigationTitle("Add to Strobe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        cancelButton
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        addButton
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            Text("Add to Strobe")
                .font(.headline)
                .padding(.vertical, 12)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 12) {
                if model.phase == .ready {
                    wordCountLabel
                }
                Spacer(minLength: 0)
                cancelButton
                addButton
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 480, height: 440)
        .background(StrobeTheme.background)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Finding the text\u{2026}")
                .foregroundStyle(.secondary)
        case .ready:
            preview
        case .nothingToRead:
            ContentUnavailableView {
                Label("No Text Found", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Strobe couldn\u{2019}t find anything to read in what you shared. For a web page, try sharing it from Safari.")
            }
        case .added:
            addedConfirmation
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $model.title)
                .font(StrobeTheme.displayFont(size: 24, relativeTo: .title2))
                .textFieldStyle(.plain)
                #if os(iOS)
                .submitLabel(.done)
                #endif
                .padding(.horizontal, 20)
                .padding(.top, 16)

            if let sourceName = model.sourceName {
                Text(sourceName)
                    .font(StrobeTheme.metadataFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }

            Divider()
                .padding(.horizontal, 20)
                .padding(.top, 12)

            ScrollView {
                Text(model.excerpt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
        }
    }

    private var addedConfirmation: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text("Added to Library")
                .font(.headline)
            Text("Open Strobe to start reading.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // Matches the count New Text shows under its editor.
    private var wordCountLabel: some View {
        Text(wordCountText)
            .font(StrobeTheme.metadataFont)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var wordCountText: String {
        let count = model.wordCount
        guard count != 1 else { return "1 word" }
        guard let wordsPerMinute = model.wordsPerMinute else {
            return "\(count.formatted()) words"
        }
        let minutes = ReadingTime.minutes(words: count, wordsPerMinute: wordsPerMinute)
        return "\(count.formatted()) words \u{00B7} about \(ReadingTime.label(minutes: minutes)) at \(wordsPerMinute) wpm"
    }

    // MARK: - Buttons

    // Controls stay neutral; the accent is kept for Add.
    private var cancelButton: some View {
        Button(model.phase == .nothingToRead ? "Done" : "Cancel") {
            model.cancel()
        }
        .tint(.primary)
        .keyboardShortcut(.cancelAction)
        .disabled(model.phase == .added)
    }

    @ViewBuilder
    private var addButton: some View {
        if model.phase != .nothingToRead {
            Button("Add") {
                model.add()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canAdd)
        }
    }
}
