import Foundation
import Testing
@testable import Strobe

struct ContinueReadingTests {

    private let documentID = UUID(uuidString: "5A1F1D00-0000-4000-8000-000000000012")!

    // MARK: - Links

    @Test func readerLinksRoundTrip() {
        let link = AppLink.reader(documentID: documentID)
        #expect(link.url.absoluteString == "strobe://read?document=5A1F1D00-0000-4000-8000-000000000012")
        #expect(AppLink(url: link.url) == link)
    }

    @Test func libraryLinkRoundTrips() {
        #expect(AppLink.library.url.absoluteString == "strobe://library")
        #expect(AppLink(url: AppLink.library.url) == .library)
    }

    @Test func schemeAndHostIgnoreCase() {
        #expect(AppLink(url: URL(string: "STROBE://Library")!) == .library)
        #expect(
            AppLink(url: URL(string: "Strobe://READ?document=5A1F1D00-0000-4000-8000-000000000012")!)
                == .reader(documentID: documentID)
        )
    }

    @Test func rejectsOtherAndMalformedLinks() {
        #expect(AppLink(url: URL(string: "https://example.com/read?document=5A1F1D00-0000-4000-8000-000000000012")!) == nil)
        #expect(AppLink(url: URL(string: "strobe://read")!) == nil)
        #expect(AppLink(url: URL(string: "strobe://read?document=not-a-uuid")!) == nil)
        #expect(AppLink(url: URL(string: "strobe://settings")!) == nil)
    }

    // MARK: - Snapshot storage

    @Test func snapshotRoundTripsThroughDefaults() throws {
        let suiteName = "ContinueReadingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(ContinueReadingSnapshot.load(from: defaults) == nil)

        let snapshot = ContinueReadingSnapshot(
            item: ContinueReadingSnapshot.Item(
                id: documentID,
                title: "Pride and Prejudice",
                fileName: "Pride and Prejudice.epub",
                progress: 0.42,
                chapterTitle: "Chapter 12",
                remainingMinutes: 185
            ),
            libraryIsEmpty: false
        )
        snapshot.save(to: defaults)
        #expect(ContinueReadingSnapshot.load(from: defaults) == snapshot)
    }

    @Test func unreadableSnapshotLoadsAsNothing() throws {
        let suiteName = "ContinueReadingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data("not json".utf8), forKey: ContinueReadingSnapshot.storageKey)
        #expect(ContinueReadingSnapshot.load(from: defaults) == nil)
    }

    @Test func statusPercentages() {
        #expect(ReadingStatus.new.percent == 0)
        #expect(ReadingStatus.inProgress(percent: 42).percent == 42)
        #expect(ReadingStatus.finished.percent == 100)
    }

    // MARK: - Up next

    @MainActor
    private func makeDocument(
        _ title: String,
        wordCount: Int = 101,
        position: Int = 0,
        lastRead: TimeInterval? = nil,
        added: TimeInterval = 0
    ) -> Document {
        let document = Document(
            title: title,
            fileName: "\(title).epub",
            bookmarkData: Data(),
            words: Array(repeating: "word", count: wordCount),
            currentWordIndex: position
        )
        document.lastReadDate = lastRead.map(Date.init(timeIntervalSince1970:))
        document.dateAdded = Date(timeIntervalSince1970: added)
        return document
    }

    @MainActor
    @Test func upNextIsTheMostRecentlyReadDocumentInProgress() {
        let older = makeDocument("Older", position: 50, lastRead: 100)
        let newer = makeDocument("Newer", position: 10, lastRead: 200)
        let finished = makeDocument("Finished", position: 100, lastRead: 300)
        let unstarted = makeDocument("Unstarted", added: 400)
        let library = [older, newer, finished, unstarted]

        #expect(Document.mostRecentlyRead(in: library) === newer)
        #expect(Document.upNext(in: library) === newer)
    }

    @MainActor
    @Test func upNextFallsBackToTheNewestUnstartedDocument() {
        let finished = makeDocument("Finished", position: 100, lastRead: 300)
        let olderUnstarted = makeDocument("Older", added: 100)
        let newerUnstarted = makeDocument("Newer", added: 200)
        let library = [finished, newerUnstarted, olderUnstarted]

        #expect(Document.mostRecentlyRead(in: library) == nil)
        #expect(Document.upNext(in: library) === newerUnstarted)
    }

    @MainActor
    @Test func nothingIsUpNextOnceEverythingIsRead() {
        #expect(Document.upNext(in: []) == nil)
        #expect(Document.upNext(in: [makeDocument("Finished", position: 100, lastRead: 300)]) == nil)
    }

    @MainActor
    @Test func snapshotDescribesTheDocumentUpNext() throws {
        let document = makeDocument("Moby-Dick", wordCount: 1001, position: 400, lastRead: 100)
        document.wordsPerMinute = 300
        document.chapters = [
            Chapter(title: "Loomings", wordIndex: 0),
            Chapter(title: "The Carpet-Bag", wordIndex: 300),
            Chapter(title: "The Spouter-Inn", wordIndex: 600),
        ]

        let snapshot = ContinueReadingSnapshot(documents: [document])
        #expect(!snapshot.libraryIsEmpty)
        let item = try #require(snapshot.item)
        #expect(item.id == document.id)
        #expect(item.title == "Moby-Dick")
        #expect(item.kind == .epub)
        #expect(item.status == .inProgress(percent: 40))
        #expect(item.chapterTitle == "The Carpet-Bag")
        // 600 words after the resume position, at 300 words per minute.
        #expect(item.remainingMinutes == 2)
        #expect(item.link == .reader(documentID: document.id))
    }

    @MainActor
    @Test func emptySnapshotsTellAnEmptyLibraryFromAReadOne() {
        let empty = ContinueReadingSnapshot(documents: [])
        #expect(empty.item == nil)
        #expect(empty.libraryIsEmpty)

        let allRead = ContinueReadingSnapshot(documents: [makeDocument("Finished", position: 100, lastRead: 300)])
        #expect(allRead.item == nil)
        #expect(!allRead.libraryIsEmpty)
    }

    // MARK: - Shortcuts

    @MainActor
    @Test func documentEntityCarriesProgress() {
        let document = makeDocument("Moby-Dick", wordCount: 1001, position: 400, lastRead: 100)
        document.wordsPerMinute = 300

        let entity = DocumentEntity(document: document)
        #expect(entity.id == document.id)
        #expect(entity.title == "Moby-Dick")
        #expect(entity.percentRead == 40)
        #expect(entity.minutesLeft == 2)
        #expect(entity.statusLine.hasPrefix("40% · "))
        #expect(entity.symbolName == "book.closed")
    }

    @MainActor
    @Test func finishedDocumentEntityHasNothingLeft() {
        let entity = DocumentEntity(document: makeDocument("Done", position: 100, lastRead: 100))
        #expect(entity.percentRead == 100)
        #expect(entity.minutesLeft == 0)
        #expect(entity.statusLine == "Finished")
    }

    // MARK: - Routing

    @MainActor
    @Test func routerHandsOverEachRequestOnce() {
        let router = AppRouter()
        #expect(router.takePendingLink() == nil)

        router.open(.reader(documentID: documentID))
        router.open(.library)
        // The latest request wins.
        #expect(router.takePendingLink() == .library)
        #expect(router.takePendingLink() == nil)
    }

    @MainActor
    @Test func routerIgnoresAReaderThatLeavesAfterItsReplacementAppears() {
        let router = AppRouter()
        let other = UUID()

        router.readerDidAppear(documentID: documentID)
        router.readerDidAppear(documentID: other)
        router.readerDidDisappear(documentID: documentID)
        #expect(router.openReaderDocumentID == other)

        router.readerDidDisappear(documentID: other)
        #expect(router.openReaderDocumentID == nil)
    }
}
