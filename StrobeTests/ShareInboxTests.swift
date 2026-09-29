import Foundation
import Testing
@testable import Strobe

struct ShareInboxTests {

    /// An inbox in its own temporary folder, which doesn't exist until the
    /// first item is added.
    private func makeInbox() -> ShareInbox {
        ShareInbox(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareInboxTests-\(UUID().uuidString)", isDirectory: true))
    }

    private func item(_ title: String, sharedAt seconds: TimeInterval, source: SharedItem.Source = .text) -> SharedItem {
        SharedItem(
            source: source,
            title: title,
            text: "Some words to read.",
            sourceURL: source == .webPage ? URL(string: "https://example.com/\(title)") : nil,
            dateShared: Date(timeIntervalSince1970: seconds)
        )
    }

    // MARK: - Inbox

    @Test func anInboxThatWasNeverWrittenIsEmpty() {
        #expect(makeInbox().pendingItems().isEmpty)
    }

    @Test func itemsComeBackOldestShareFirst() throws {
        let inbox = makeInbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        let later = item("later", sharedAt: 2_000, source: .webPage)
        let earlier = item("earlier", sharedAt: 1_000)
        try inbox.add(later)
        try inbox.add(earlier)

        #expect(inbox.pendingItems() == [earlier, later])

        inbox.remove(earlier)
        #expect(inbox.pendingItems() == [later])
    }

    @Test func unreadableItemsAreDiscardedAndOtherFilesLeftAlone() throws {
        let inbox = makeInbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        let good = item("good", sharedAt: 1_000)
        try inbox.add(good)
        let broken = inbox.directory.appendingPathComponent("broken.json")
        try Data("not an item".utf8).write(to: broken)
        let unrelated = inbox.directory.appendingPathComponent("notes.txt")
        try Data("left alone".utf8).write(to: unrelated)

        #expect(inbox.pendingItems() == [good])
        #expect(!FileManager.default.fileExists(atPath: broken.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    // MARK: - Items from what was shared

    @Test func aPageBecomesAnArticleWithATidyTitle() throws {
        let shared = try #require(SharedItem(pageResults: [
            SharedItem.PageKey.title: "  The Quiet\n Revolution ",
            SharedItem.PageKey.text: "It started with a single page.",
            SharedItem.PageKey.url: "https://example.com/story",
            SharedItem.PageKey.isSelection: false,
        ]))
        #expect(shared.source == .webPage)
        #expect(shared.title == "The Quiet Revolution")
        #expect(shared.sourceURL == URL(string: "https://example.com/story"))
    }

    @Test func aSelectionOnAPageIsKeptAsChosen() throws {
        let shared = try #require(SharedItem(pageResults: [
            SharedItem.PageKey.text: "Just this paragraph.",
            SharedItem.PageKey.url: "https://example.com/story",
            SharedItem.PageKey.isSelection: true,
        ]))
        #expect(shared.source == .text)
        #expect(shared.title == "")
    }

    @Test func aPageWithoutWordsIsNothingToAdd() {
        #expect(SharedItem(pageResults: [SharedItem.PageKey.text: " \n\t "]) == nil)
        #expect(SharedItem(pageResults: [SharedItem.PageKey.title: "Only a title"]) == nil)
        #expect(SharedItem(text: "   ") == nil)
    }

    @Test func onlyWebAddressesAreKeptAsTheSource() {
        let local = SharedItem(pageResults: [
            SharedItem.PageKey.text: "Words.",
            SharedItem.PageKey.url: "file:///Users/someone/page.html",
        ])
        #expect(local?.sourceURL == nil)
    }

    @Test func findsAWebAddressWhenThatsAllTheTextHolds() {
        #expect(SharedItem.webURL(from: " https://example.com/a?b=1 \n") == URL(string: "https://example.com/a?b=1"))
        #expect(SharedItem.webURL(from: "HTTP://example.com") == URL(string: "HTTP://example.com"))
        #expect(SharedItem.webURL(from: "Read this: https://example.com") == nil)
        #expect(SharedItem.webURL(from: "mailto:someone@example.com") == nil)
        #expect(SharedItem.webURL(from: "https://") == nil)
    }

    @Test func aHeadingLineTitlesSharedText() {
        #expect(SharedItem.suggestedTitle(forText: "On Reading Fast\n\nMost people read about 250 words a minute.") == "On Reading Fast")
        #expect(SharedItem.suggestedTitle(forText: "\n  Why Read?  \nBecause.") == "Why Read?")
        #expect(SharedItem(text: "Chapter One\nIt was a cold morning.")?.title == "Chapter One")
    }

    @Test func proseAndSalutationsDontBecomeTitles() {
        // A single line has nothing after it to title.
        #expect(SharedItem.suggestedTitle(forText: "Just one line of text") == "")
        #expect(SharedItem.suggestedTitle(forText: "Hi Sam,\n\nThanks for the notes.") == "")
        #expect(SharedItem.suggestedTitle(forText: "This first line is a sentence.\nAnd a second.") == "")
        #expect(SharedItem.suggestedTitle(
            forText: "A first line that goes on for more words than any heading would ever need\nMore."
        ) == "")
    }

    // MARK: - Import

    @Test func articlesAreCleanedButChosenTextIsNot() {
        let text = "The article begins here.\n42\nAnd it goes on."
        let article = SharedItem(source: .webPage, title: "", text: text)
        let chosen = SharedItem(source: .text, title: "", text: text)

        #expect(ShareInboxImporter.readableText(of: article, cleaningLevel: .standard) == "The article begins here.\nAnd it goes on.")
        #expect(ShareInboxImporter.readableText(of: article, cleaningLevel: .none) == text)
        #expect(ShareInboxImporter.readableText(of: chosen, cleaningLevel: .standard) == text)
    }

    @Test func textWithoutWordsPreparesNothing() {
        #expect(TextImport.prepare(" \n\t ") == nil)
    }

    @MainActor
    @Test func aSharedPageKeepsItsAddressAndShareDate() throws {
        let prepared = try #require(TextImport.prepare("A few words to read."))
        #expect(prepared.wordCount == 5)
        let shared = Date(timeIntervalSince1970: 1_000)
        let document = TextImport.makeDocument(
            from: prepared,
            title: "  The Story ",
            fileName: "https://example.com/story",
            dateAdded: shared,
            wordsPerMinute: 420
        )
        #expect(document.title == "The Story")
        #expect(document.kind == .web)
        #expect(document.dateAdded == shared)
        #expect(document.wordsPerMinute == 420)
        #expect(document.readingWords == ["A", "few", "words", "to", "read."])
    }

    @MainActor
    @Test func untitledTextIsNamedForWhenItWasAdded() throws {
        let prepared = try #require(TextImport.prepare("Words."))
        let added = Date(timeIntervalSince1970: 1_000)
        let document = TextImport.makeDocument(from: prepared, title: " ", dateAdded: added, wordsPerMinute: 300)
        #expect(document.title == TextImport.untitledTitle(addedAt: added))
        #expect(document.title.hasPrefix("Text \u{2014} "))
        // Text stores its title as the file name.
        #expect(document.fileName == document.title)
        #expect(document.kind == .text)
    }

    @Test func webAddressesAreLabeledWeb() {
        #expect(DocumentKind(fileName: "https://example.com/paper.pdf") == .web)
        #expect(DocumentKind(fileName: "HTTP://example.com/book.epub") == .web)
        #expect(DocumentKind(fileName: "https notes.txt") == .text)
        #expect(DocumentKind.web.label == "WEB")
    }
}
