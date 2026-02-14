import SwiftUI
import SwiftData
internal import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Document.dateAdded, order: .reverse) private var documents: [Document]

    @State private var isImporting = false
    @State private var isProcessingImport = false
    @State private var importFileName = ""
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty {
                    emptyState
                } else {
                    documentList
                }
            }
            .navigationTitle("Strobe")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isImporting = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(isProcessingImport)
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
            .alert("Import Error", isPresented: .init(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No documents yet")
                .font(.custom("JetBrainsMono-Regular", size: 18))
                .foregroundStyle(.secondary)
            Text("Tap + to import a PDF or EPUB")
                .font(.custom("JetBrainsMono-Regular", size: 14))
                .foregroundStyle(.secondary.opacity(0.7))
        }
    }

    // MARK: - Document list

    private var documentList: some View {
        List {
            ForEach(documents) { document in
                NavigationLink(destination: ReaderView(document: document)) {
                    DocumentRow(document: document)
                }
            }
            .onDelete(perform: deleteDocuments)
        }
    }

    // MARK: - Import

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

        let title = url.deletingPathExtension().lastPathComponent

        Task(priority: .userInitiated) {
            defer {
                url.stopAccessingSecurityScopedResource()
                isProcessingImport = false
                importFileName = ""
            }

            do {
                let words = try await Task.detached(priority: .userInitiated) {
                    let detectedType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                    return try DocumentImportPipeline.extractWords(from: url, detectedContentType: detectedType)
                }.value

                guard !words.isEmpty else {
                    throw DocumentImportError.noReadableText
                }

                let document = Document(
                    title: title,
                    fileName: url.lastPathComponent,
                    bookmarkData: bookmarkData,
                    words: words
                )
                modelContext.insert(document)
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

    // MARK: - Delete

    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(documents[index])
        }
    }

    private var importOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)

                Text("Importing \(importFileName)")
                    .font(.custom("JetBrainsMono-Regular", size: 14))
                    .lineLimit(1)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()
        }
    }
}
