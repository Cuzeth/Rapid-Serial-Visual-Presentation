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

}
