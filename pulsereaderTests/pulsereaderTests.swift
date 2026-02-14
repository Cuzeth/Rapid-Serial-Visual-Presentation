//
//  strobeTests.swift
//  strobeTests
//
//  Created by CZTH on 2/13/26.
//

import Testing
@testable import strobe

struct strobeTests {

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

}
