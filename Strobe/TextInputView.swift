import SwiftUI
import SwiftData

/// A sheet for typing or pasting plain text to add directly to the library.
struct TextInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("defaultWPM") private var defaultWPM: Int = 300

    @State private var title: String = ""
    @State private var inputText: String = ""
    @State private var saveError: String?
    @FocusState private var editorFocused: Bool

    /// Approximate word count for display — uses fast whitespace split, not full tokenizer.
    private var approximateWordCount: Int {
        inputText.split(whereSeparator: \.isWhitespace).count
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
                        }

                        TextEditor(text: $inputText)
                            .scrollContentBackground(.hidden)
                            .font(StrobeTheme.bodyFont(size: 16))
                            .foregroundStyle(StrobeTheme.textPrimary)
                            .tint(StrobeTheme.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .focused($editorFocused)
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
        .alert("Save Error", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
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

            Spacer()

            Text("New Text")
                .font(StrobeTheme.bodyFont(size: 18, bold: true))
                .foregroundStyle(StrobeTheme.textPrimary)

            Spacer()

            Button {
                save()
            } label: {
                Text("Add")
                    .font(StrobeTheme.bodyFont(size: 16, bold: true))
                    .foregroundStyle(canSave ? .white : StrobeTheme.textSecondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(canSave ? StrobeTheme.accent : StrobeTheme.surface)
                    .clipShape(Capsule())
            }
            .disabled(!canSave)
            .animation(.easeInOut(duration: 0.15), value: canSave)
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let words = Tokenizer.tokenize(trimmedText)
        guard !words.isEmpty else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

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
