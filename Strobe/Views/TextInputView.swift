import SwiftUI
import SwiftData

/// A sheet for typing or pasting plain text to add directly to the library.
struct TextInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(ReaderSettings.Keys.defaultWPM) private var defaultWPM: Int = ReaderSettings.Defaults.defaultWPM

    @State private var title: String = ""
    @State private var inputText: String = ""
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var showDiscardConfirmation = false
    @State private var approximateWordCount = 0
    @State private var wordCountTask: Task<Void, Never>?
    @FocusState private var editorFocused: Bool

    /// Whether the user has typed anything worth protecting from accidental dismissal.
    private var hasUnsavedInput: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Recomputes the displayed word count, debounced and off the main actor.
    /// As a computed property this ran on every body evaluation — after
    /// pasting a book-length text, each keystroke in the *title* field
    /// re-scanned the whole text on the main thread.
    private func scheduleWordCount(for text: String) {
        wordCountTask?.cancel()
        wordCountTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let count = await Task.detached(priority: .utility) {
                Self.approximateWordCount(of: text)
            }.value
            guard !Task.isCancelled else { return }
            approximateWordCount = count
        }
    }

    /// Approximate word count for display.
    /// Counts CJK ideographs individually and whitespace-splits Latin text.
    nonisolated private static func approximateWordCount(of text: String) -> Int {
        var cjkCount = 0
        var latinBuffer = ""
        var latinWords = 0

        for scalar in text.unicodeScalars {
            let isCJK = CJKUtilities.isHanIdeograph(scalar)

            if isCJK {
                cjkCount += 1
                if !latinBuffer.isEmpty {
                    latinWords += latinBuffer.split(whereSeparator: \.isWhitespace).count
                    latinBuffer.removeAll(keepingCapacity: true)
                }
            } else {
                latinBuffer.unicodeScalars.append(scalar)
            }
        }

        if !latinBuffer.isEmpty {
            latinWords += latinBuffer.split(whereSeparator: \.isWhitespace).count
        }

        return cjkCount + latinWords
    }

    private var canSave: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            StrobeTheme.Gradients.mainBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                VStack(spacing: 12) {
                    // Title field
                    TextField("Title (optional)", text: $title)
                        .disabled(isSaving)
                        .font(StrobeTheme.bodyFont(size: 16))
                        .foregroundStyle(StrobeTheme.textPrimary)
                        .tint(StrobeTheme.accent)
                        .padding(16)
                        .background(StrobeTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )

                    // Text editor
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("Paste or type your text here…")
                                .font(StrobeTheme.bodyFont(size: 16))
                                .foregroundStyle(StrobeTheme.textSecondary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }

                        TextEditor(text: $inputText)
                            // Locked during save: the save uses a snapshot of
                            // the text, so edits made mid-save would be
                            // silently lost when the sheet dismisses.
                            .disabled(isSaving)
                            .scrollContentBackground(.hidden)
                            .font(StrobeTheme.bodyFont(size: 16))
                            .foregroundStyle(StrobeTheme.textPrimary)
                            .tint(StrobeTheme.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .focused($editorFocused)
                            .accessibilityLabel("Text content")
                            .accessibilityHint(inputText.isEmpty ? "Paste or type your text here" : "")
                    }
                    .frame(maxHeight: .infinity)
                    .background(StrobeTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(editorFocused ? StrobeTheme.accent.opacity(0.4) : Color.white.opacity(0.05), lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.15), value: editorFocused)

                    // Word count
                    HStack {
                        Spacer()
                        Text(approximateWordCount == 0 ? "No text" : approximateWordCount == 1 ? "1 word" : "\(approximateWordCount) words")
                            .font(StrobeTheme.bodyFont(size: 12))
                            .foregroundStyle(StrobeTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            editorFocused = true
        }
        .onChange(of: inputText) { _, newText in
            scheduleWordCount(for: newText)
        }
        .interactiveDismissDisabled(hasUnsavedInput || isSaving)
        .confirmationDialog(
            "Discard this text?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .alert("Save Error", isPresented: .init(isPresent: $saveError)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            CircleIconButton(systemImage: "xmark", iconSize: 16, padding: 10, accessibilityLabel: "Close") {
                if hasUnsavedInput {
                    showDiscardConfirmation = true
                } else {
                    dismiss()
                }
            }
            .disabled(isSaving)

            Spacer()

            Text("New Text")
                .font(StrobeTheme.bodyFont(size: 18, bold: true))
                .foregroundStyle(StrobeTheme.textPrimary)

            Spacer()

            Button {
                save()
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(isSaving ? "Adding…" : "Add")
                        .font(StrobeTheme.bodyFont(size: 16, bold: true))
                        .foregroundStyle(canSave ? Color.white : Color.white.opacity(0.5))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(canSave ? StrobeTheme.accent : StrobeTheme.accent.opacity(0.35))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave || isSaving)
            .animation(.easeInOut(duration: 0.15), value: canSave)
        }
    }

    // MARK: - Save

    private func save() {
        guard !isSaving else { return }
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true

        Task {
            defer { isSaving = false }

            // Tokenizing and complexity analysis (NLTagger) are expensive on
            // long pasted texts — run them off the main thread so the sheet
            // stays responsive.
            let (words, complexityScores) = await Task.detached(priority: .userInitiated) {
                let words = Tokenizer.tokenize(trimmedText)
                let scores = words.isEmpty ? [] : WordComplexityAnalyzer.analyzeComplexity(words)
                return (words, scores)
            }.value

            guard !words.isEmpty else {
                saveError = "No readable text found."
                return
            }

            let resolvedTitle: String
            if trimmedTitle.isEmpty {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                resolvedTitle = "Text — \(formatter.string(from: Date()))"
            } else {
                resolvedTitle = trimmedTitle
            }

            let document = Document(
                title: resolvedTitle,
                fileName: resolvedTitle,
                bookmarkData: Data(),
                words: words,
                complexityScores: complexityScores,
                wordsPerMinute: defaultWPM
            )
            modelContext.insert(document)
            do {
                try modelContext.save()
            } catch {
                modelContext.delete(document)
                saveError = "Could not save: \(error.localizedDescription)"
                return
            }

            dismiss()
        }
    }
}
