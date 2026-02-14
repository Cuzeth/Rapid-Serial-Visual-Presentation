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
        let words = PDFTextExtractor.tokenize("infor-\nmation and recov-\nery")
        #expect(words == ["information", "and", "recovery"])
    }

    @Test func preservesCompoundLineBreakHyphenation() {
        let words = PDFTextExtractor.tokenize("one-in-a-\nlifetime")
        #expect(words == ["one-in-a-lifetime"])
    }

    @Test func dropsFalseCompoundTailHyphenation() {
        let words = PDFTextExtractor.tokenize("once-in-a-life-\ntime")
        #expect(words == ["once-in-a-lifetime"])
    }

    @Test func normalizesSoftAndNonBreakingHyphens() {
        let words = PDFTextExtractor.tokenize("hy\u{00AD}phen non\u{2011}breaking")
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

    @Test func epubExtractionIsStubbed() {
        do {
            _ = try DocumentImportPipeline.extractWordsAndChapters(
                from: URL(fileURLWithPath: "/tmp/book.epub"),
                detectedContentType: .epub
            )
            Issue.record("Expected EPUB extraction to throw a not-implemented error.")
        } catch let error as DocumentImportError {
            #expect(error == .epubParsingNotImplemented)
        } catch {
            Issue.record("Unexpected error type: \(error)")
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

}
