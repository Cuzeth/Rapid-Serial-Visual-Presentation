import SwiftUI
import SwiftData

/// A sheet for typing or pasting plain text to add directly to the library:
/// a title, the text, and a running word count with its reading time.
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
        sheetContainer
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

    @ViewBuilder
    private var sheetContainer: some View {
        #if os(iOS)
        NavigationStack {
            editor
                .navigationTitle("New Text")
                .navigationBarTitleDisplayMode(.inline)
        }
        #else
        editor
            .frame(minWidth: 560, minHeight: 460)
        #endif
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $title)
                .font(StrobeTheme.displayFont(size: 26, relativeTo: .title2))
                .textFieldStyle(.plain)
                .disabled(isSaving)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)
                #if os(iOS)
                .submitLabel(.next)
                #endif
                .onSubmit {
                    editorFocused = true
                }

            Divider()
                .padding(.horizontal, 20)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $inputText)
                    // Locked during save: the save uses a snapshot of the
                    // text, so edits made mid-save would be silently lost
                    // when the sheet dismisses.
                    .disabled(isSaving)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .accessibilityLabel("Text")

                if inputText.isEmpty {
                    emptyEditorPrompt
                        .padding(.horizontal, 20)
                        .padding(.top, Self.promptTopInset)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background { StrobeTheme.background.ignoresSafeArea() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .toolbar {
            toolbarContent
        }
    }

    /// Lines the prompt up with the editor's first line of text, which the
    /// platform text views inset by different amounts.
    private static var promptTopInset: CGFloat {
        #if os(macOS)
        8
        #else
        16
        #endif
    }

    private var emptyEditorPrompt: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Type or paste the text you want to read.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            PasteButton(payloadType: String.self) { strings in
                let pasted = strings.joined(separator: "\n\n")
                guard !pasted.isEmpty else { return }
                inputText = pasted
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleAndIcon)
            .disabled(isSaving)
        }
    }

    private var footer: some View {
        HStack {
            Text(wordCountLabel)
                .font(StrobeTheme.metadataFont)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var wordCountLabel: String {
        switch approximateWordCount {
        case 0:
            return "No text yet"
        case 1:
            return "1 word"
        default:
            let minutes = ReadingTime.minutes(words: approximateWordCount, wordsPerMinute: defaultWPM)
            return "\(approximateWordCount.formatted()) words · about \(ReadingTime.label(minutes: minutes)) at \(defaultWPM) wpm"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if hasUnsavedInput {
                    showDiscardConfirmation = true
                } else {
                    dismiss()
                }
            }
            .tint(.primary)
            .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Add") {
                    save()
                }
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
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

            // Tokenizing, complexity analysis (NLTagger), and storage-blob
            // encoding are expensive on long pasted texts — run them off the
            // main thread so the sheet stays responsive.
            let (wordCount, wordsBlob, complexityBlob) = await Task.detached(priority: .userInitiated) {
                () -> (Int, Data, Data?) in
                let words = Tokenizer.tokenize(trimmedText)
                guard !words.isEmpty else { return (0, Data(), nil) }
                let scores = WordComplexityAnalyzer.analyzeComplexity(words)
                return (
                    words.count,
                    WordStorage.encode(words),
                    scores.isEmpty ? nil : ComplexityStorage.encode(scores)
                )
            }.value

            guard wordCount > 0 else {
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
                wordsBlob: wordsBlob,
                wordCount: wordCount,
                complexityBlob: complexityBlob,
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
