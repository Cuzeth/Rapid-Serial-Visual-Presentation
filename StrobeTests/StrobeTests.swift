//
//  StrobeTests.swift
//  StrobeTests
//
//  Created by CZTH on 2/13/26.
//

import Testing
@testable import Strobe
internal import UniformTypeIdentifiers

struct StrobeTests {

    @Test func tokenizesSimpleLineBreakHyphenation() {
        let words = Tokenizer.tokenize("infor-\nmation and recov-\nery")
        #expect(words == ["information", "and", "recovery"])
    }

    @Test func preservesCompoundLineBreakHyphenation() {
        let words = Tokenizer.tokenize("one-in-a-\nlifetime")
        #expect(words == ["one-in-a-lifetime"])
    }

    @Test func dropsFalseCompoundTailHyphenation() {
        let words = Tokenizer.tokenize("once-in-a-life-\ntime")
        #expect(words == ["once-in-a-lifetime"])
    }

    @Test func normalizesSoftAndNonBreakingHyphens() {
        let words = Tokenizer.tokenize("hy\u{00AD}phen non\u{2011}breaking")
        #expect(words == ["hyphen", "non-breaking"])
    }

    @Test func resolvesSourceTypeFromExtension() {
        #expect(DocumentImportPipeline.resolveSourceType(for: URL(fileURLWithPath: "/tmp/book.pdf")) == .pdf)
        #expect(DocumentImportPipeline.resolveSourceType(for: URL(fileURLWithPath: "/tmp/book.epub")) == .epub)
        #expect(DocumentImportPipeline.resolveSourceType(for: URL(fileURLWithPath: "/tmp/book.txt")) == .unknown)
    }

    @Test func resolvesSourceTypeFromDetectedContentType() {
        let unknownPath = URL(fileURLWithPath: "/tmp/book.bin")
        #expect(DocumentImportPipeline.resolveSourceType(for: unknownPath, detectedContentType: .pdf) == .pdf)
        #expect(DocumentImportPipeline.resolveSourceType(for: unknownPath, detectedContentType: .epub) == .epub)
    }

    @Test func epubExtractionFailsForMissingFile() {
        do {
            _ = try DocumentImportPipeline.extractWordsAndChapters(
                from: URL(fileURLWithPath: "/tmp/nonexistent.epub"),
                detectedContentType: .epub
            )
            Issue.record("Expected EPUB extraction to throw an error for a missing file.")
        } catch let error as DocumentImportError {
            #expect(error == .epubExtractionFailed)
        } catch {
            // Any error is acceptable for a missing file
        }
    }

    @Test func unknownExtractionTypeThrowsUnsupportedTypeError() {
        do {
            _ = try DocumentImportPipeline.extractWordsAndChapters(
                from: URL(fileURLWithPath: "/tmp/book.txt")
            )
            Issue.record("Expected unknown type to throw unsupported-file-type error.")
        } catch let error as DocumentImportError {
            #expect(error == .unsupportedFileType)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Standalone punctuation filtering

    @Test func attachesStandalonePunctuationToPreviousWord() {
        let words = Tokenizer.tokenize("hello ' world . end")
        #expect(words == ["hello'", "world.", "end"])
    }

    @Test func keepsPunctuationAttachedToWords() {
        let words = Tokenizer.tokenize("don't end. \"hello\"")
        #expect(words == ["don't", "end.", "\"hello\""])
    }

    @Test func attachesMultipleIsolatedPunctuationToPreviousWord() {
        let words = Tokenizer.tokenize("word ... — – word2")
        #expect(words == ["word...—–", "word2"])
    }

    // MARK: - Tabular data cleaning

    @Test func detectsTabularDataLines() {
        let input = "12.5  34  67.8  90.1\nThis is a normal sentence.\n$100  $200  $300  $400"
        let cleaned = TextCleaner.cleanText(input, level: .standard)
        #expect(cleaned.contains("normal sentence"))
        #expect(!cleaned.contains("12.5"))
        #expect(!cleaned.contains("$100"))
    }

    @Test func preservesNormalTextWithSomeNumbers() {
        let input = "Chapter 3 describes 42 experiments in detail"
        let cleaned = TextCleaner.cleanText(input, level: .standard)
        #expect(cleaned.contains("42 experiments"))
    }

    // MARK: - Smart timing

    @Test func smartTimingMultiplierIncreasesForLongWords() {
        let short = RSVPEngine.smartTimingMultiplier(for: "cat")
        let long = RSVPEngine.smartTimingMultiplier(for: "characteristically")
        #expect(long > short)
    }

    @Test func smartTimingMultiplierAccountsForTerminalPunctuation() {
        let plain = RSVPEngine.smartTimingMultiplier(for: "reading")
        let punctuated = RSVPEngine.smartTimingMultiplier(for: "reading.")
        #expect(punctuated > plain)
    }

    // MARK: - Sentence pause

    @Test func sentencePauseDetectsFullStops() {
        #expect(RSVPEngine.endsWithSentencePunctuation("end."))
        #expect(RSVPEngine.endsWithSentencePunctuation("what?"))
        #expect(RSVPEngine.endsWithSentencePunctuation("wow!"))
    }

    @Test func sentencePauseIgnoresNonSentencePunctuation() {
        #expect(!RSVPEngine.endsWithSentencePunctuation("hello,"))
        #expect(!RSVPEngine.endsWithSentencePunctuation("word"))
        #expect(!RSVPEngine.endsWithSentencePunctuation("semi;"))
    }

    // MARK: - RSVPEngine playback

    @Test func enginePlayAndPause() {
        let engine = RSVPEngine(words: ["one", "two", "three"])
        #expect(!engine.isPlaying)
        engine.play()
        #expect(engine.isPlaying)
        engine.pause()
        #expect(!engine.isPlaying)
    }

    @Test func engineSeekClampsToValidRange() {
        let engine = RSVPEngine(words: ["a", "b", "c", "d"])
        engine.seek(to: 100)
        #expect(engine.currentIndex == 3)
        engine.seek(to: -5)
        #expect(engine.currentIndex == 0)
    }

    @Test func engineScrubReturnsHitBoundary() {
        let engine = RSVPEngine(words: ["a", "b", "c"])
        engine.seek(to: 2)
        let hitEnd = engine.scrub(by: 1)
        #expect(hitEnd)
        #expect(engine.currentIndex == 2)
    }

    @Test func engineProgressCalculation() {
        let engine = RSVPEngine(words: ["a", "b", "c", "d", "e"])
        #expect(engine.progress == 0)
        engine.seek(to: 2)
        #expect(engine.progress == 0.5)
        engine.seek(to: 4)
        #expect(engine.progress == 1.0)
    }

    @Test func engineIsAtEnd() {
        let engine = RSVPEngine(words: ["a", "b"])
        #expect(!engine.isAtEnd)
        engine.seek(to: 1)
        #expect(engine.isAtEnd)
    }

    @Test func engineRestart() {
        let engine = RSVPEngine(words: ["a", "b", "c"])
        engine.seek(to: 2)
        engine.restart()
        #expect(engine.currentIndex == 0)
    }

    @Test func engineDoesNotPlayWhenAtEnd() {
        let engine = RSVPEngine(words: ["a", "b"])
        engine.seek(to: 1)
        engine.play()
        #expect(!engine.isPlaying)
    }

    @Test func engineSingleWordProgress() {
        let engine = RSVPEngine(words: ["only"])
        #expect(engine.progress == 0)
        #expect(engine.isAtEnd)
    }

    // MARK: - WordStorage round-trip

    @Test func wordStorageEncodeDecodeRoundTrip() {
        let words = ["Hello", "world", "test", "café", "naïve"]
        let encoded = WordStorage.encode(words)
        let decoded = WordStorage.decode(encoded)
        #expect(decoded == words)
    }

    @Test func wordStorageEmptyArray() {
        let encoded = WordStorage.encode([])
        let decoded = WordStorage.decode(encoded)
        #expect(decoded == [""])
    }

    // MARK: - Text cleaning patterns

    @Test func removesStandalonePageNumbers() {
        let cleaned = TextCleaner.cleanText("42\nSome real text here.\n- 7 -", level: .standard)
        #expect(!cleaned.contains("42"))
        #expect(!cleaned.contains("- 7 -"))
        #expect(cleaned.contains("real text"))
    }

    @Test func removesPageOfPatterns() {
        let cleaned = TextCleaner.cleanText("Page 5 of 100\nContent here.\npage 12", level: .standard)
        #expect(!cleaned.contains("Page 5"))
        #expect(!cleaned.contains("page 12"))
        #expect(cleaned.contains("Content here"))
    }

    @Test func removesISBNLines() {
        let cleaned = TextCleaner.cleanText("ISBN 978-0-123456-78-9\nActual content.", level: .standard)
        #expect(!cleaned.contains("ISBN"))
        #expect(cleaned.contains("Actual content"))
    }

    @Test func removesCopyrightNotices() {
        let cleaned = TextCleaner.cleanText("© 2024 Author Name\nAll rights reserved.\nReal text.", level: .standard)
        #expect(!cleaned.contains("©"))
        #expect(!cleaned.contains("All rights reserved"))
        #expect(cleaned.contains("Real text"))
    }

    @Test func removesNavigationText() {
        let cleaned = TextCleaner.cleanText("Next Chapter\nParagraph content.\nTable of Contents", level: .standard)
        #expect(!cleaned.lowercased().contains("next chapter"))
        #expect(!cleaned.lowercased().contains("table of contents"))
        #expect(cleaned.contains("Paragraph content"))
    }

    @Test func removesPublisherBoilerplate() {
        let cleaned = TextCleaner.cleanText("Published by Penguin\nFirst edition 2023\nStory begins here.", level: .standard)
        #expect(!cleaned.contains("Published by"))
        #expect(!cleaned.contains("First edition"))
        #expect(cleaned.contains("Story begins"))
    }

    @Test func removesTocLeaderLines() {
        let cleaned = TextCleaner.cleanText("Chapter 1 ......... 15\nActual paragraph.", level: .standard)
        #expect(!cleaned.contains("......"))
        #expect(cleaned.contains("Actual paragraph"))
    }

    @Test func cleaningLevelNonePreservesEverything() {
        let input = "Page 5\n42\nISBN 978-0-123456-78-9\nReal text."
        let cleaned = TextCleaner.cleanText(input, level: .none)
        #expect(cleaned == input)
    }

    // MARK: - Title resolution

    @Test func resolveTitlePrefersMetadata() {
        let title = DocumentImportPipeline.resolveTitle(metadataTitle: "My Book", fileName: "ugly_file-name.pdf")
        #expect(title == "My Book")
    }

    @Test func resolveTitleFallsBackToCleanedFileName() {
        let title = DocumentImportPipeline.resolveTitle(metadataTitle: nil, fileName: "my_cool-book.pdf")
        #expect(title == "My Cool Book")
    }

    @Test func resolveTitleHandlesEmptyMetadata() {
        let title = DocumentImportPipeline.resolveTitle(metadataTitle: "  ", fileName: "fallback.epub")
        #expect(title == "Fallback")
    }

}
