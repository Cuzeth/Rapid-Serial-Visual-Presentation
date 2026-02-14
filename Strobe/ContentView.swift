import SwiftUI
import SwiftData
internal import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Document.dateAdded, order: .reverse) private var documents: [Document]

    @State private var isImporting = false
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
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
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
            Text("Tap + to import a PDF")
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
            importPDF(from: url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func importPDF(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Cannot access this file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let bookmarkData = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            importError = "Could not save a reference to this file."
            return
        }

        let words = PDFTextExtractor.extractWords(from: url)
        guard !words.isEmpty else {
            importError = "Could not extract text from this PDF. It may be image-only."
            return
        }

        let title = url.deletingPathExtension().lastPathComponent
        let document = Document(
            title: title,
            fileName: url.lastPathComponent,
            bookmarkData: bookmarkData,
            words: words
        )
        modelContext.insert(document)
    }

    // MARK: - Delete

    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(documents[index])
        }
    }
}
