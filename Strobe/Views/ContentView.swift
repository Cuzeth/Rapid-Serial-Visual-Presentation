import SwiftUI
import SwiftData
internal import UniformTypeIdentifiers

/// The main library view displaying imported documents in a grid.
///
/// Handles document import (PDF/EPUB via the system file picker), plain text
/// entry, legacy word storage migration, and navigation to the reader or chapter list.
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
    @State private var showTextInput = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Grid layout definition — wider cards on iPad regular width
    private var columns: [GridItem] {
        let minWidth: CGFloat = horizontalSizeClass == .regular ? 200 : 160
        return [GridItem(.adaptive(minimum: minWidth), spacing: 16)]
    }

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
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    #if os(iOS)
                    // On iPad (regular width) the medium detent is too small;
                    // offer large only so settings fills the sheet properly.
                    .presentationDetents(horizontalSizeClass == .regular ? [.large] : [.medium, .large])
                    .presentationCornerRadius(24)
                    #endif
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
            .sheet(isPresented: $showTextInput) {
                TextInputView()
                    #if os(iOS)
                    .presentationDetents([.large])
                    .presentationCornerRadius(24)
                    #endif
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
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data = data as? Data,
                          let path = String(data: data, encoding: .utf8),
                          let url = URL(string: path) else { return }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "pdf" || ext == "epub" else { return }
                    Task { @MainActor in
                        importDocument(from: url)
                    }
                }
                return true
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
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(
            StrobeTheme.background.opacity(0.8)
                .ignoresSafeArea()
        )
    }

    private var emptyStateSubtitle: Text {
        #if os(macOS)
        Text("Click the + button to import\na PDF or EPUB, or enter text directly")
        #else
        Text("Tap the + button to import\na PDF or EPUB, or enter text directly")
        #endif
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
                
                emptyStateSubtitle
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
                    .buttonStyle(.plain)
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
            .frame(maxWidth: horizontalSizeClass == .regular ? 1024 : .infinity)
            .frame(maxWidth: .infinity)
        }
    }

    private var importButton: some View {
        Menu {
            Button {
                isImporting = true
            } label: {
                Label("Import File", systemImage: "doc.fill")
            }
            Button {
                showTextInput = true
            } label: {
                Label("Enter Text", systemImage: "text.cursor")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(StrobeTheme.accent)
                .clipShape(Circle())
                .shadow(color: StrobeTheme.accent.opacity(0.4), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
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

        let isSecurityScoped = url.startAccessingSecurityScopedResource()

        let bookmarkData: Data
        #if os(iOS)
        let bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
        #else
        let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
        #endif
        if let data = try? url.bookmarkData(
            options: bookmarkOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmarkData = data
        } else {
            bookmarkData = Data()
        }

        isProcessingImport = true
        importFileName = url.lastPathComponent
        let fileName = url.lastPathComponent
        
        Task(priority: .userInitiated) {
            defer {
                if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
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
                    complexityScores: importResult.complexityScores,
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

/// A grid card displaying a document's title, progress percentage, and word count.
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
        guard wordCount > 1 else { return currentWordIndex > 0 ? 100 : 0 }
        return Int((Double(currentWordIndex) / Double(wordCount - 1)) * 100)
    }
}
