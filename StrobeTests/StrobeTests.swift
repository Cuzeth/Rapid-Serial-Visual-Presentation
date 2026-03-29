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

    @Test func sentencePauseDetectsPunctuationInsideDelimiters() {
        #expect(RSVPEngine.endsWithSentencePunctuation("home.\""))
        #expect(RSVPEngine.endsWithSentencePunctuation("laughed?\""))
        #expect(RSVPEngine.endsWithSentencePunctuation("fun!)"))
        #expect(RSVPEngine.endsWithSentencePunctuation("pages.)"))
        #expect(RSVPEngine.endsWithSentencePunctuation("done.\u{201D}"))  // "
        #expect(RSVPEngine.endsWithSentencePunctuation("end.])"))
        #expect(!RSVPEngine.endsWithSentencePunctuation("said,\""))
        #expect(!RSVPEngine.endsWithSentencePunctuation("(word)"))
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
        #expect(engine.progress == 1.0)
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
        #expect(decoded == [])
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

    // MARK: - Chinese / CJK tokenization

    @Test func tokenizesChineseTextIntoWords() {
        let words = Tokenizer.tokenize("今天天气很好")
        // NLTokenizer should segment this into multiple words, not one blob
        #expect(words.count > 1)
        // Rejoining should give back the original text
        #expect(words.joined() == "今天天气很好")
    }

    @Test func tokenizesMixedChineseEnglish() {
        let words = Tokenizer.tokenize("Hello 世界 is great")
        #expect(words.contains("Hello"))
        #expect(words.contains("is"))
        #expect(words.contains("great"))
        // 世界 should appear as a token (possibly with punctuation attached)
        #expect(words.contains(where: { $0.contains("世界") }))
    }

    @Test func attachesChinesePunctuationToPrecedingWord() {
        let words = Tokenizer.tokenize("你好。世界")
        // The 。 should be attached to the word before it, not standalone
        #expect(words.contains(where: { $0.hasSuffix("。") }))
        #expect(!words.contains("。"))
    }

    @Test func detectsChineseSentencePunctuation() {
        #expect(RSVPEngine.endsWithSentencePunctuation("好。"))
        #expect(RSVPEngine.endsWithSentencePunctuation("吗？"))
        #expect(RSVPEngine.endsWithSentencePunctuation("啊！"))
    }

    @Test func chineseSentencePauseIgnoresComma() {
        #expect(!RSVPEngine.endsWithSentencePunctuation("好，"))
    }

    // MARK: - Arabic support

    @Test func tokenizesArabicText() {
        let words = Tokenizer.tokenize("مرحبا بالعالم")
        #expect(words == ["مرحبا", "بالعالم"])
    }

    @Test func detectsArabicSentencePunctuation() {
        #expect(RSVPEngine.endsWithSentencePunctuation("ماذا؟"))
        #expect(RSVPEngine.endsWithSentencePunctuation("نعم۔"))
    }

    @Test func arabicSentencePauseIgnoresComma() {
        #expect(!RSVPEngine.endsWithSentencePunctuation("مرحبا،"))
    }

    // MARK: - Complexity timing

    @Test func complexityMultiplierAtMidpointIsUnity() {
        let multiplier = RSVPEngine.complexityMultiplier(score: 0.5, intensity: 1.0)
        #expect(multiplier == 1.0)
    }

    @Test func complexityMultiplierSpeedsUpSimpleWords() {
        let multiplier = RSVPEngine.complexityMultiplier(score: 0.0, intensity: 1.0)
        #expect(multiplier < 1.0)
    }

    @Test func complexityMultiplierSlowsComplexWords() {
        let multiplier = RSVPEngine.complexityMultiplier(score: 1.0, intensity: 1.0)
        #expect(multiplier > 1.0)
    }

    @Test func complexityMultiplierAtZeroIntensityIsUnity() {
        let low = RSVPEngine.complexityMultiplier(score: 0.0, intensity: 0.0)
        let high = RSVPEngine.complexityMultiplier(score: 1.0, intensity: 0.0)
        #expect(low == 1.0)
        #expect(high == 1.0)
    }

    @Test func complexityAnalyzerProducesCorrectCount() {
        let words = ["the", "quick", "brown", "fox"]
        let scores = WordComplexityAnalyzer.analyzeComplexity(words)
        #expect(scores.count == words.count)
    }

    @Test func complexityAnalyzerScoresCommonWordsLow() {
        let scores = WordComplexityAnalyzer.analyzeComplexity(["the", "is", "and", "epistemological"])
        // Common words should score lower than a rare, long word
        #expect(scores[0] < scores[3])
        #expect(scores[1] < scores[3])
        #expect(scores[2] < scores[3])
    }

    @Test func complexityAnalyzerHandlesEmptyInput() {
        let scores = WordComplexityAnalyzer.analyzeComplexity([])
        #expect(scores.isEmpty)
    }

    @Test func complexityStorageRoundTrip() {
        let scores: [Float] = [0.1, 0.5, 0.9, 0.0, 1.0]
        let encoded = ComplexityStorage.encode(scores)
        let decoded = ComplexityStorage.decode(encoded)
        #expect(decoded == scores)
    }

    @Test func complexityStorageEmptyArray() {
        let encoded = ComplexityStorage.encode([])
        let decoded = ComplexityStorage.decode(encoded)
        #expect(decoded.isEmpty)
    }

    // MARK: - Mixed language (CJK + Latin)

    @Test func tokenizesChineseWithLatinInterspersed() {
        // Common pattern: Chinese text with English brand names / tech terms
        let words = Tokenizer.tokenize("我在使用iPhone阅读")
        #expect(words.count >= 2)
        // All original text should be preserved
        #expect(words.joined() == "我在使用iPhone阅读")
    }

    // MARK: - ZIP security

    @Test func zipExtractorRejectsPathTraversal() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Build a minimal ZIP with a path-traversal entry: "../../evil.txt"
        let zipData = buildMinimalZIP(name: "../../evil.txt", content: Data("pwned".utf8))
        let zipURL = tempDir.appendingPathComponent("malicious.zip")
        try zipData.write(to: zipURL)

        let extractDir = tempDir.appendingPathComponent("extracted")
        try ZIPExtractor.extract(zipAt: zipURL, to: extractDir)

        // The file should NOT exist outside the extraction directory
        let escapedFile = tempDir.appendingPathComponent("evil.txt")
        #expect(!FileManager.default.fileExists(atPath: escapedFile.path))
    }

    @Test func zipInflateCapsDecompressionBuffer() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Build a ZIP whose uncompressed-size header claims ~200 MB (exceeds 100 MB cap).
        // The actual content is tiny, but the header tricks the allocator.
        let content = Data("hello".utf8)
        var zip = Data()
        let name = Data("bomb.txt".utf8)

        // Local file header
        zip.append(contentsOf: withUnsafeBytes(of: UInt32(0x04034b50).littleEndian) { Data($0) })
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(20).littleEndian) { Data($0) })   // version
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) })    // flags
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(8).littleEndian) { Data($0) })    // compression: deflate
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) })    // mod time
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) })    // mod date
        zip.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })    // crc32
        zip.append(contentsOf: withUnsafeBytes(of: UInt32(content.count).littleEndian) { Data($0) })  // compressed size
        zip.append(contentsOf: withUnsafeBytes(of: UInt32(200_000_000).littleEndian) { Data($0) })    // uncompressed: 200 MB
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(name.count).littleEndian) { Data($0) })
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) })    // extra length
        zip.append(name)
        zip.append(content)

        let zipURL = tempDir.appendingPathComponent("bomb.zip")
        try zip.write(to: zipURL)

        let extractDir = tempDir.appendingPathComponent("extracted")
        try ZIPExtractor.extract(zipAt: zipURL, to: extractDir)

        // The file should NOT be extracted (inflate returns nil due to cap)
        let extractedFile = extractDir.appendingPathComponent("bomb.txt")
        #expect(!FileManager.default.fileExists(atPath: extractedFile.path))
    }

    // MARK: - PDF error propagation

    @Test func pdfExtractionThrowsForInvalidFile() {
        do {
            _ = try DocumentImportPipeline.extractWordsAndChapters(
                from: URL(fileURLWithPath: "/tmp/nonexistent.pdf"),
                detectedContentType: .pdf
            )
            Issue.record("Expected PDF extraction to throw an error for a missing file.")
        } catch let error as DocumentImportError {
            #expect(error == .pdfLoadFailed)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - CJK utilities

    @Test func cjkUtilitiesDetectsAllRanges() {
        // CJK Unified Ideographs
        #expect(CJKUtilities.isCJK(Unicode.Scalar(0x4E00)!))
        // CJK Extension A
        #expect(CJKUtilities.isCJK(Unicode.Scalar(0x3400)!))
        // CJK Compatibility
        #expect(CJKUtilities.isCJK(Unicode.Scalar(0xF900)!))
        // CJK Extension B
        #expect(CJKUtilities.isCJK(Unicode.Scalar(0x20000)!))
        // CJK punctuation
        #expect(CJKUtilities.isCJK(Unicode.Scalar(0x3001)!))  // 、
        // Fullwidth forms
        #expect(CJKUtilities.isCJK(Unicode.Scalar(0xFF01)!))  // ！
        // Bopomofo
        #expect(CJKUtilities.isCJK(Unicode.Scalar(0x3105)!))
        // Hiragana
        #expect(CJKUtilities.isCJK(Unicode.Scalar(0x3042)!))  // あ
        // Katakana
        #expect(CJKUtilities.isCJK(Unicode.Scalar(0x30A2)!))  // ア
        // Latin should NOT match
        #expect(!CJKUtilities.isCJK(Unicode.Scalar(0x0041)!)) // A
    }

    @Test func cjkUtilitiesHanIdeographExcludesKana() {
        // Han ideograph should match
        #expect(CJKUtilities.isHanIdeograph(Unicode.Scalar(0x4E00)!))
        // Hiragana should NOT match isHanIdeograph
        #expect(!CJKUtilities.isHanIdeograph(Unicode.Scalar(0x3042)!))
        // Fullwidth should NOT match isHanIdeograph
        #expect(!CJKUtilities.isHanIdeograph(Unicode.Scalar(0xFF01)!))
    }

    @Test func cjkUtilitiesIsCJKDominant() {
        #expect(CJKUtilities.isCJKDominant("你好世界"))
        #expect(!CJKUtilities.isCJKDominant("Hello World"))
        #expect(CJKUtilities.isCJKDominant("你好世界ab"))  // 4/6 CJK > 50%
    }

    // MARK: - ComplexityStorage alignment safety

    @Test func complexityStorageHandlesRoundTrip() {
        let scores: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0, 0.123456]
        let encoded = ComplexityStorage.encode(scores)
        let decoded = ComplexityStorage.decode(encoded)
        #expect(decoded == scores)
    }

    @Test func complexityStorageDecodesSubsetOfData() {
        // Verify decode handles data that's not an exact multiple of Float size
        let scores: [Float] = [0.1, 0.2, 0.3]
        var encoded = ComplexityStorage.encode(scores)
        encoded.append(contentsOf: [0xFF, 0xFF]) // extra trailing bytes
        let decoded = ComplexityStorage.decode(encoded)
        #expect(decoded == scores) // should ignore trailing partial float
    }

    // MARK: - HTML entity resolution

    @Test func resolvesNamedHTMLEntities() {
        let input = "Hello&nbsp;World&amp;Co &lt;tag&gt; &quot;quoted&quot; &apos;apos&apos;"
        let result = EPUBTextExtractor.resolveHTMLEntities(input)
        #expect(result == "Hello World&Co <tag> \"quoted\" 'apos'")
    }

    @Test func resolvesTypographicEntities() {
        let input = "word&mdash;word&ndash;word&hellip;more"
        let result = EPUBTextExtractor.resolveHTMLEntities(input)
        #expect(result == "word\u{2014}word\u{2013}word\u{2026}more")
    }

    @Test func resolvesQuoteEntities() {
        let input = "&lsquo;single&rsquo; &ldquo;double&rdquo;"
        let result = EPUBTextExtractor.resolveHTMLEntities(input)
        #expect(result == "\u{2018}single\u{2019} \u{201C}double\u{201D}")
    }

    @Test func resolvesDecimalNumericEntities() {
        // &#65; = 'A', &#8212; = em dash
        let input = "&#65; &#8212; &#169;"
        let result = EPUBTextExtractor.resolveHTMLEntities(input)
        #expect(result == "A \u{2014} \u{00A9}")
    }

    @Test func resolvesHexNumericEntities() {
        // &#x41; = 'A', &#x2014; = em dash, &#x1F600; = grinning face emoji
        let input = "&#x41; &#x2014; &#x1F600;"
        let result = EPUBTextExtractor.resolveHTMLEntities(input)
        #expect(result == "A \u{2014} \u{1F600}")
    }

    @Test func numericEntityWithMissingSemicolonEmitsLiteral() {
        // No semicolon — should emit the literal '&' and continue
        let input = "&#65 next"
        let result = EPUBTextExtractor.resolveHTMLEntities(input)
        #expect(result == "&#65 next")
    }

    @Test func numericEntityWithEmptyDigitsEmitsLiteral() {
        // &#; has no digits — should pass through
        let input = "&#; text"
        let result = EPUBTextExtractor.resolveHTMLEntities(input)
        #expect(result == "&#; text")
    }

    @Test func numericEntityWithInvalidCodePointEmitsLiteral() {
        // 0xFFFFFF is not a valid Unicode scalar
        let input = "&#xFFFFFF; text"
        let result = EPUBTextExtractor.resolveHTMLEntities(input)
        #expect(result == "&#xFFFFFF; text")
    }

    @Test func mixedNamedAndNumericEntities() {
        let input = "&amp;&#38;&#x26;"  // all three ways to encode '&'
        let result = EPUBTextExtractor.resolveHTMLEntities(input)
        #expect(result == "&&&")
    }

    @Test func textWithNoEntitiesPassesThrough() {
        let input = "Plain text with no entities at all."
        let result = EPUBTextExtractor.resolveHTMLEntities(input)
        #expect(result == input)
    }

    // MARK: - ZIP test helpers

    /// Builds a minimal valid ZIP archive containing a single stored (uncompressed) entry.
    private func buildMinimalZIP(name: String, content: Data) -> Data {
        let nameData = Data(name.utf8)
        var zip = Data()

        // Local file header
        zip.append(contentsOf: withUnsafeBytes(of: UInt32(0x04034b50).littleEndian) { Data($0) })  // signature
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(20).littleEndian) { Data($0) })          // version needed
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) })           // flags
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) })           // compression (stored)
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) })           // mod time
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) })           // mod date
        zip.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })           // crc32
        zip.append(contentsOf: withUnsafeBytes(of: UInt32(content.count).littleEndian) { Data($0) }) // compressed size
        zip.append(contentsOf: withUnsafeBytes(of: UInt32(content.count).littleEndian) { Data($0) }) // uncompressed size
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(nameData.count).littleEndian) { Data($0) }) // name length
        zip.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) })           // extra length
        zip.append(nameData)
        zip.append(content)

        return zip
    }
}
