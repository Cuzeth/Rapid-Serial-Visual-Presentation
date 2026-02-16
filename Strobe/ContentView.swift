import SwiftUI
import SwiftData
internal import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Document.dateAdded, order: .reverse) private var documents: [Document]

    @AppStorage("defaultWPM") private var defaultWPM: Int = 300
    @AppStorage(ReaderFont.storageKey) private var readerFontSelection = ReaderFont.defaultValue.rawValue
    @AppStorage(TextCleaningLevel.storageKey) private var textCleaningLevel = TextCleaningLevel.defaultValue.rawValue
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false

    @State private var isImporting = false
    @State private var isProcessingImport = false
    @State private var importFileName = ""
    @State private var importError: String?
    @State private var showSettings = false
    @State private var showTutorial = false

    // Grid layout definition
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    private var readerFont: ReaderFont {
        ReaderFont.resolve(readerFontSelection)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                StrobeTheme.Gradients.mainBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    customHeader
                    
                    if documents.isEmpty {
                        Spacer()
                        emptyState
                        Spacer()
                    } else {
                        documentGrid
                    }
                }

                // Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        importButton
                            .padding(.trailing, 24)
                            .padding(.bottom, 24)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(24)
            }
            .fullScreenCover(isPresented: $showTutorial) {
                TutorialView()
            }
            .onAppear {
                compactLegacyWordStorageIfNeeded()
                if !hasSeenTutorial {
                    showTutorial = true
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: DocumentImportPipeline.supportedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .overlay {
                if isProcessingImport {
                    importOverlay
                }
            }
            .alert("Error", isPresented: .init(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
        .preferredColorScheme(.dark) // Force dark mode for the theme
    }

    // MARK: - Custom Header

    private var customHeader: some View {
        HStack {
            Text("Strobe")
                .font(StrobeTheme.titleFont(size: 32))
                .foregroundStyle(StrobeTheme.textPrimary)

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(StrobeTheme.textSecondary)
                    .padding(10)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(
            StrobeTheme.background.opacity(0.8)
                .ignoresSafeArea()
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(StrobeTheme.accent.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(StrobeTheme.accent)
            }
            
            VStack(spacing: 8) {
                Text("Library Empty")
                    .font(StrobeTheme.titleFont(size: 24))
                    .foregroundStyle(StrobeTheme.textPrimary)
                
                Text("Tap the + button to import\na PDF or EPUB file")
                    .font(StrobeTheme.bodyFont(size: 16))
                    .foregroundStyle(StrobeTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Document Grid

    private var documentGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(documents) { document in
                    NavigationLink(destination: destination(for: document)) {
                        DocumentCard(document: document, readerFont: readerFont)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            modelContext.delete(document)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(24)
            // Add extra padding at bottom for FAB
            .padding(.bottom, 80) 
        }
    }

    private var importButton: some View {
        Button {
            isImporting = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(StrobeTheme.accent)
                .clipShape(Circle())
                .shadow(color: StrobeTheme.accent.opacity(0.4), radius: 10, x: 0, y: 5)
        }
        .disabled(isProcessingImport)
    }

    @ViewBuilder
    private func destination(for document: Document) -> some View {
        if document.chapters.isEmpty {
            ReaderView(document: document)
        } else {
            ChapterListView(document: document)
        }
    }

    // MARK: - Import Logic (Unchanged logic, just keeping it here)

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importDocument(from: url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func importDocument(from url: URL) {
        // Logic identical to original, just ensuring we don't break it
        guard !isProcessingImport else { return }

        guard url.startAccessingSecurityScopedResource() else {
            importError = "Cannot access this file."
            return
        }

        guard let bookmarkData = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            url.stopAccessingSecurityScopedResource()
            importError = "Could not save a reference to this file."
            return
        }

        isProcessingImport = true
        importFileName = url.lastPathComponent
        let fileName = url.lastPathComponent
        
        Task(priority: .userInitiated) {
            defer {
                url.stopAccessingSecurityScopedResource()
                isProcessingImport = false
                importFileName = ""
            }

            do {
                let cleaningLevel = TextCleaningLevel.resolve(textCleaningLevel)
                let importResult = try await Task.detached(priority: .userInitiated) {
                    let detectedType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                    return try DocumentImportPipeline.extractWordsAndChapters(
                        from: url,
                        detectedContentType: detectedType,
                        cleaningLevel: cleaningLevel
                    )
                }.value

                guard !importResult.words.isEmpty else {
                    throw DocumentImportError.noReadableText
                }

                let title = DocumentImportPipeline.resolveTitle(
                    metadataTitle: importResult.title,
                    fileName: fileName
                )

                let document = Document(
                    title: title,
                    fileName: fileName,
                    bookmarkData: bookmarkData,
                    words: importResult.words,
                    chapters: importResult.chapters,
                    wordsPerMinute: defaultWPM
                )
                modelContext.insert(document)
                try modelContext.save()
            } catch {
                if let localizedError = error as? LocalizedError,
                   let message = localizedError.errorDescription {
                    importError = message
                } else {
                    importError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Helpers

    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(documents[index])
        }
    }

    private func compactLegacyWordStorageIfNeeded() {
        var didCompact = false
        for document in documents where document.wordsBlob == nil && !document.words.isEmpty {
            document.compactWordStorageIfNeeded()
            didCompact = true
        }
        guard didCompact else { return }
        try? modelContext.save()
    }

    private var importOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text("Importing \(importFileName)...")
                    .font(readerFont.regularFont(size: 16))
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(StrobeTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Document Card Component

struct DocumentCard: View {
    let document: Document
    let readerFont: ReaderFont
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon / Cover placeholder
            ZStack {
                Circle()
                    .fill(StrobeTheme.accent.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(StrobeTheme.accent)
            }
            
            Spacer()
            
            Text(document.title)
                .font(StrobeTheme.titleFont(size: 18))
                .foregroundStyle(StrobeTheme.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.9)
                .multilineTextAlignment(.leading)
            
            HStack {
                Text("\(document.progressPercentage)%")
                    .foregroundStyle(StrobeTheme.accent)
                Spacer()
                Text("\(document.wordCount) words")
                    .foregroundStyle(StrobeTheme.textSecondary)
            }
            .font(StrobeTheme.bodyFont(size: 12))
        }
        .padding(16)
        .frame(height: 180)
        .background(StrobeTheme.Gradients.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

extension Document {
    var progressPercentage: Int {
        let total = max(1, wordCount)
        return Int((Double(currentWordIndex) / Double(total)) * 100)
    }
}
