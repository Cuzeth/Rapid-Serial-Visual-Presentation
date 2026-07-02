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

    @AppStorage(ReaderSettings.Keys.defaultWPM) private var defaultWPM: Int = ReaderSettings.Defaults.defaultWPM
    @AppStorage(TextCleaningLevel.storageKey) private var textCleaningLevel = TextCleaningLevel.defaultValue.rawValue
    @AppStorage(ReaderSettings.Keys.hasSeenTutorial) private var hasSeenTutorial = false
    @AppStorage(ReaderSettings.Keys.didCompactLegacyWordStorage) private var didCompactLegacyWordStorage = false
    @AppStorage(LibrarySortOrder.storageKey) private var librarySortOrderRaw = LibrarySortOrder.defaultValue.rawValue

    @State private var isImporting = false
    @State private var isProcessingImport = false
    @State private var importFileName = ""
    @State private var importTask: Task<Void, Never>?
    @State private var importError: String?
    @State private var persistenceError: String?
    @State private var showSettings = false
    @State private var showTutorial = false
    @State private var showTextInput = false
    @State private var documentPendingDeletion: Document?
    @State private var documentPendingRename: Document?
    @State private var renameText = ""
    @State private var searchText = ""
    @State private var isDropTargeted = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Grid layout definition — wider cards on iPad regular width
    private var columns: [GridItem] {
        let minWidth: CGFloat = horizontalSizeClass == .regular ? 200 : 160
        return [GridItem(.adaptive(minimum: minWidth), spacing: 16)]
    }

    private var sortOrder: LibrarySortOrder {
        LibrarySortOrder(rawValue: librarySortOrderRaw) ?? LibrarySortOrder.defaultValue
    }

    /// Documents re-sorted by the user's chosen order and filtered by the
    /// search query. The base `@Query` is already newest-first by date added.
    private var displayedDocuments: [Document] {
        var result = documents
        switch sortOrder {
        case .dateAdded:
            break
        case .lastRead:
            result.sort { ($0.lastReadDate ?? .distantPast) > ($1.lastReadDate ?? .distantPast) }
        case .title:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }
        return result.filter { $0.title.localizedCaseInsensitiveContains(query) }
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
                        searchBar
                        if displayedDocuments.isEmpty {
                            Spacer()
                            noSearchResults
                            Spacer()
                        } else {
                            documentGrid
                        }
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

                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(StrobeTheme.accent, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(StrobeTheme.accent.opacity(0.06))
                        )
                        .padding(8)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            #if os(iOS)
            // On macOS, settings open in the standard Settings window (Cmd+,)
            // via SettingsLink instead of a sheet.
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    // On iPad (regular width) the medium detent is too small;
                    // offer large only so settings fills the sheet properly.
                    .presentationDetents(horizontalSizeClass == .regular ? [.large] : [.medium, .large])
                    .presentationCornerRadius(24)
            }
            #endif
            .tutorialCover(isPresented: $showTutorial)
            .sheet(isPresented: $showTextInput) {
                TextInputView()
                    #if os(iOS)
                    .presentationDetents([.large])
                    .presentationCornerRadius(24)
                    #elseif os(macOS)
                    // Without a minimum frame the sheet sizes to the
                    // TextEditor's tiny ideal size — every other macOS sheet
                    // in the app sets one.
                    .frame(minWidth: 600, minHeight: 500)
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
            .alert("Couldn't Import File", isPresented: .init(isPresent: $importError)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .alert("Save Error", isPresented: .init(isPresent: $persistenceError)) {
                Button("OK") { persistenceError = nil }
            } message: {
                Text(persistenceError ?? "")
            }
            .alert(
                "Rename Document",
                isPresented: .init(isPresent: $documentPendingRename),
                presenting: documentPendingRename
            ) { doc in
                TextField("Title", text: $renameText)
                Button("Save") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        doc.title = trimmed
                        saveOrReport("Could not rename the document")
                    }
                    documentPendingRename = nil
                }
                Button("Cancel", role: .cancel) {
                    documentPendingRename = nil
                }
            }
            .alert(
                "Delete this document?",
                isPresented: .init(isPresent: $documentPendingDeletion),
                presenting: documentPendingDeletion
            ) { doc in
                Button("Delete", role: .destructive) {
                    modelContext.delete(doc)
                    // Surfaced because a silently failed save rolls the delete
                    // back — the document would reappear on next launch with
                    // no explanation.
                    saveOrReport("Could not delete the document")
                    documentPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    documentPendingDeletion = nil
                }
            } message: { doc in
                Text("\"\(doc.title)\" will be permanently removed from your library.")
            }
            .navigationDestination(for: Document.self) { document in
                if document.chapters.isEmpty {
                    ReaderView(document: document)
                } else {
                    ChapterListView(document: document)
                }
            }
            .navigationDestination(for: ReaderRoute.self) { route in
                ReaderView(document: route.document, startingWordIndex: route.startingWordIndex)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                guard let provider = providers.first else { return false }
                handleDrop(provider)
                return true
            }
        }
        .preferredColorScheme(.dark) // Force dark mode for the theme
    }

    // MARK: - Custom Header

    private var customHeader: some View {
        HStack(spacing: 12) {
            Text("Strobe")
                .font(StrobeTheme.titleFont(size: 32))
                .foregroundStyle(StrobeTheme.textPrimary)

            Spacer()

            if !documents.isEmpty {
                Menu {
                    Picker("Sort By", selection: $librarySortOrderRaw) {
                        ForEach(LibrarySortOrder.allCases) { order in
                            Text(order.displayName).tag(order.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(StrobeTheme.textSecondary)
                        .padding(11)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sort library")
                .accessibilityValue(sortOrder.displayName)
            }

            #if os(macOS)
            SettingsLink {
                settingsButtonLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            #else
            Button {
                showSettings = true
            } label: {
                settingsButtonLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            #endif
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(
            StrobeTheme.background
                .ignoresSafeArea()
        )
    }

    private var settingsButtonLabel: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 20))
            .foregroundStyle(StrobeTheme.textSecondary)
            .padding(10)
            .background(Color.white.opacity(0.05))
            .clipShape(Circle())
    }

    // MARK: - Search

    private var searchBar: some View {
        StrobeSearchBar(
            placeholder: "Search library",
            text: $searchText,
            font: StrobeTheme.bodyFont(size: 15)
        ) { field in
            field
                .tint(StrobeTheme.accent)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
        .frame(maxWidth: horizontalSizeClass == .regular ? 1024 : .infinity)
        .frame(maxWidth: .infinity)
    }

    private var noSearchResults: some View {
        VStack(spacing: 8) {
            Text("No Results")
                .font(StrobeTheme.titleFont(size: 24))
                .foregroundStyle(StrobeTheme.textPrimary)

            Text("No documents match \"\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                .font(StrobeTheme.bodyFont(size: 16))
                .foregroundStyle(StrobeTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
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
                ForEach(displayedDocuments) { document in
                    ZStack(alignment: .topTrailing) {
                        // Value-based so the destination isn't built until the
                        // user navigates — an eager `destination:` link would
                        // construct a ReaderView (and decode word blobs) for
                        // every visible card.
                        NavigationLink(value: document) {
                            DocumentCard(document: document)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            documentMenuItems(for: document)
                        }

                        // A sibling of the NavigationLink, not nested in its
                        // label — interactive controls inside link labels are
                        // unreliable outside Lists (the link's tap can win).
                        Menu {
                            documentMenuItems(for: document)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(StrobeTheme.textSecondary)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.05))
                                .clipShape(Circle())
                                // Keep the visible circle small but give the
                                // tap target the 44pt minimum.
                                .contentShape(Rectangle().inset(by: -7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Document options")
                        .padding(12)
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
        .accessibilityLabel("Add document")
        .accessibilityHint("Import a PDF or EPUB, or enter text")
    }

    private func beginRename(_ document: Document) {
        renameText = document.title
        documentPendingRename = document
    }

    /// Saves the model context, surfacing failures in the Save Error alert
    /// (mirrors `ReaderView.persistState` — `try?` here silently rolled the
    /// change back on next launch).
    private func saveOrReport(_ what: String) {
        do {
            try modelContext.save()
        } catch {
            persistenceError = "\(what): \(error.localizedDescription)"
        }
    }

    /// Shared menu content for a document, used by both the card's visible
    /// options menu and the long-press context menu so they can't diverge.
    @ViewBuilder
    private func documentMenuItems(for document: Document) -> some View {
        Button {
            beginRename(document)
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button(role: .destructive) {
            documentPendingDeletion = document
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

}

// MARK: - Library sort order

/// User-selectable sort orders for the library grid, persisted in UserDefaults.
enum LibrarySortOrder: String, CaseIterable, Identifiable {
    static let storageKey = "librarySortOrder"
    static let defaultValue: LibrarySortOrder = .dateAdded

    case dateAdded
    case lastRead
    case title

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dateAdded: "Recently Added"
        case .lastRead: "Recently Read"
        case .title: "Title"
        }
    }
}

// MARK: - Import Logic

extension ContentView {
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importDocument(from: url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    /// Imports a dropped file via `loadInPlaceFileRepresentation`. The raw
    /// `fileURL` item is unusable on iOS — it points into the source app's
    /// sandbox with no security scope, so opening it fails with a misleading
    /// "corrupted file" error. The in-place/copied representation is
    /// readable; the system reclaims copies when the handler returns, so
    /// they're cloned out first.
    private func handleDrop(_ provider: NSItemProvider) {
        let supported = DocumentImportPipeline.supportedContentTypes
        let typeID = provider.registeredTypeIdentifiers.first { id in
            guard let type = UTType(id) else { return false }
            return supported.contains { type.conforms(to: $0) }
        }

        guard let typeID else {
            // Load the URL just to name the file in the error message.
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                let name = (data as? Data)
                    .flatMap { String(data: $0, encoding: .utf8) }
                    .flatMap(URL.init(string:))?
                    .lastPathComponent
                Task { @MainActor in
                    if let name {
                        importError = "\"\(name)\" isn't a supported file type. Drop a PDF, EPUB, or text file."
                    } else {
                        importError = "That file isn't a supported type. Drop a PDF, EPUB, or text file."
                    }
                }
            }
            return
        }

        _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeID) { url, inPlace, _ in
            guard let url else {
                Task { @MainActor in
                    importError = "Couldn't read the dropped file."
                }
                return
            }
            if inPlace {
                Task { @MainActor in
                    importDocument(from: url)
                }
            } else {
                // The system deletes this copy when the handler returns —
                // clone it to our own temp location first.
                do {
                    let dir = FileManager.default.temporaryDirectory
                        .appendingPathComponent("drop_\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let copy = dir.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: copy)
                    Task { @MainActor in
                        importDocument(from: copy, deleteAfterImport: true)
                    }
                } catch {
                    Task { @MainActor in
                        importError = "Couldn't read the dropped file."
                    }
                }
            }
        }
    }

    private func importDocument(from url: URL, deleteAfterImport: Bool = false) {
        guard !isProcessingImport else {
            importError = "Another import is still in progress. Wait for it to finish or cancel it first."
            return
        }

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

        importTask = Task(priority: .userInitiated) {
            defer {
                if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
                if deleteAfterImport { try? FileManager.default.removeItem(at: url) }
                isProcessingImport = false
                importFileName = ""
                importTask = nil
            }

            do {
                let cleaningLevel = TextCleaningLevel.resolve(textCleaningLevel)
                let extraction = Task.detached(priority: .userInitiated) {
                    let detectedType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                    return try DocumentImportPipeline.extractWordsAndChapters(
                        from: url,
                        detectedContentType: detectedType,
                        cleaningLevel: cleaningLevel
                    )
                }
                // Detached tasks don't inherit cancellation — forward the
                // overlay's Cancel to the extraction work explicitly.
                let importResult = try await withTaskCancellationHandler {
                    try await extraction.value
                } onCancel: {
                    extraction.cancel()
                }
                try Task.checkCancellation()

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
            } catch is CancellationError {
                // User cancelled — no alert.
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

    private func compactLegacyWordStorageIfNeeded() {
        // One-time pass. Touching `wordsBlob`/`words` on every document
        // faults every row (and can pull external blobs) on the main thread —
        // without this flag, every launch paid that for an empty check.
        guard !didCompactLegacyWordStorage else { return }
        var didCompact = false
        for document in documents where document.wordsBlob == nil && !document.words.isEmpty {
            document.compactWordStorageIfNeeded()
            didCompact = true
        }
        if didCompact {
            do {
                try modelContext.save()
            } catch {
                // Leave the flag unset so the next launch retries.
                importError = "Could not migrate document storage: \(error.localizedDescription)"
                return
            }
        }
        didCompactLegacyWordStorage = true
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
                    .font(StrobeTheme.bodyFont(size: 16))
                    .foregroundStyle(.white)

                Button {
                    importTask?.cancel()
                } label: {
                    Text("Cancel")
                        .font(StrobeTheme.bodyFont(size: 15, bold: true))
                        .foregroundStyle(StrobeTheme.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Stops the import")
            }
            .padding(32)
            .background(StrobeTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Document Card Component

/// A grid card displaying a document's title, progress percentage, and word
/// count. The visible options menu is overlaid by the grid (outside the
/// NavigationLink label); the card leaves its top-trailing corner clear for it.
struct DocumentCard: View {
    let document: Document

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
            .accessibilityHidden(true)

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
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
            // Read the card as one element ("Title, 45%, 12,000 words")
            // instead of three fragments.
            .accessibilityElement(children: .combine)
        }
        .padding(16)
        // Minimum (not fixed) height: the card's fonts scale with Dynamic
        // Type, and a fixed 180pt truncated titles at accessibility sizes.
        .frame(minHeight: 180)
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
        Int(progress * 100)
    }
}
