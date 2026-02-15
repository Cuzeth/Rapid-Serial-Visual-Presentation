import Foundation
import os

nonisolated(unsafe) private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.abdeen.strobe",
    category: "TextCleaner"
)

/// Controls the level of text cleaning applied during import.
enum TextCleaningLevel: String, CaseIterable, Identifiable {
    static let storageKey = "textCleaningLevel"
    static let defaultValue: TextCleaningLevel = .standard

    case none
    case standard

    var id: String { rawValue }

    static func resolve(_ rawValue: String) -> TextCleaningLevel {
        TextCleaningLevel(rawValue: rawValue) ?? defaultValue
    }

    var displayName: String {
        switch self {
        case .none: "Off"
        case .standard: "Standard"
        }
    }

    var description: String {
        switch self {
        case .none: "Import text exactly as extracted."
        case .standard: "Removes page numbers, headers, footers, and common boilerplate."
        }
    }
}

// MARK: - Rule-based text cleaning engine

enum TextCleaner {

    /// Why a line was removed — logged for debugging.
    private enum RemovalReason: String {
        case repeatedHeader = "repeated header/footer"
        case pageNumber = "standalone page number"
        case pageOfPattern = "page-of pattern"
        case tocLeader = "TOC leader line"
        case isbn = "ISBN"
        case copyright = "copyright notice"
        case navigation = "navigation text"
        case publisher = "publisher boilerplate"
    }

    /// Cleans an array of page-level or section-level text strings.
    /// Cross-page analysis detects repeated headers/footers, then per-page rules strip boilerplate.
    nonisolated static func cleanPages(_ pages: [String], level: TextCleaningLevel) -> [String] {
        guard level != .none else {
            logger.debug("Text cleaning: OFF")
            return pages
        }

        logger.info("Text cleaning: \(level.rawValue) — processing \(pages.count) pages")

        let repeatedPatterns = detectRepeatedPatterns(in: pages)
        if !repeatedPatterns.isEmpty {
            logger.info("Detected \(repeatedPatterns.count) repeated header/footer pattern(s)")
            for pattern in repeatedPatterns {
                logger.debug("  repeated pattern: \"\(pattern)\"")
            }
        }

        var totalRemoved = 0
        let result = pages.enumerated().map { (pageIndex, page) -> String in
            let (cleaned, removedCount) = cleanPage(page, repeatedPatterns: repeatedPatterns, pageIndex: pageIndex)
            totalRemoved += removedCount
            return cleaned
        }

        logger.info("Text cleaning complete — removed \(totalRemoved) line(s) across \(pages.count) page(s)")
        return result
    }

    /// Cleans a single text block (no cross-page analysis).
    nonisolated static func cleanText(_ text: String, level: TextCleaningLevel) -> String {
        guard level != .none else { return text }
        let (cleaned, _) = cleanPage(text, repeatedPatterns: [], pageIndex: nil)
        return cleaned
    }

    // MARK: - Cross-page repeated pattern detection

    /// Finds lines that appear (after digit-normalization) across many pages.
    /// These are almost certainly headers or footers.
    nonisolated private static func detectRepeatedPatterns(in pages: [String]) -> Set<String> {
        guard pages.count >= 3 else { return [] }

        var lineCounts: [String: Int] = [:]

        for page in pages {
            let lines = page.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard lines.count >= 3 else { continue }

            // Check first 2 and last 2 lines — typical header/footer positions
            let candidates = Array(lines.prefix(2)) + Array(lines.suffix(2))
            var seenThisPage = Set<String>()

            for line in candidates {
                let normalized = normalizeForComparison(line)
                guard normalized.count >= 2,
                      seenThisPage.insert(normalized).inserted else { continue }
                lineCounts[normalized, default: 0] += 1
            }
        }

        let threshold = max(3, pages.count / 2)
        return Set(lineCounts.filter { $0.value >= threshold }.keys)
    }

    /// Strips digits and collapses whitespace so "Page 1" and "Page 247" produce the same key.
    nonisolated private static func normalizeForComparison(_ line: String) -> String {
        line.unicodeScalars
            .filter { !CharacterSet.decimalDigits.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Per-page cleaning

    nonisolated private static func cleanPage(
        _ text: String,
        repeatedPatterns: Set<String>,
        pageIndex: Int?
    ) -> (cleaned: String, removedCount: Int) {
        let lines = text.components(separatedBy: .newlines)
        var removedCount = 0

        let cleaned = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Preserve blank lines (paragraph breaks)
            guard !trimmed.isEmpty else { return line }

            func remove(_ reason: RemovalReason) -> String? {
                removedCount += 1
                if let pageIndex {
                    logger.debug("  [page \(pageIndex)] \(reason.rawValue): \"\(trimmed)\"")
                } else {
                    logger.debug("  \(reason.rawValue): \"\(trimmed)\"")
                }
                return nil
            }

            // 1. Repeated header/footer patterns
            if !repeatedPatterns.isEmpty {
                let normalized = normalizeForComparison(trimmed)
                if repeatedPatterns.contains(normalized) { return remove(.repeatedHeader) }
            }

            // 2. Standalone page numbers: "42", "- 3 -", "[ 15 ]"
            if isStandalonePageNumber(trimmed) { return remove(.pageNumber) }

            // 3. "Page X of Y" patterns
            if isPageOfPattern(trimmed) { return remove(.pageOfPattern) }

            // 4. TOC leader lines: "Chapter 1 ......... 15"
            if isTOCLeaderLine(trimmed) { return remove(.tocLeader) }

            // 5. ISBN lines
            if isISBN(trimmed) { return remove(.isbn) }

            // 6. Copyright notices
            if isCopyrightNotice(trimmed) { return remove(.copyright) }

            // 7. Navigation boilerplate
            if isNavigationText(trimmed) { return remove(.navigation) }

            // 8. Publisher boilerplate
            if isPublisherBoilerplate(trimmed) { return remove(.publisher) }

            return line
        }

        return (cleaned.joined(separator: "\n"), removedCount)
    }

    // MARK: - Pattern matchers

    /// Lines that are just a number, optionally wrapped in dashes, brackets, or parens.
    nonisolated private static func isStandalonePageNumber(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: CharacterSet(charactersIn: "-[]() "))
        return !stripped.isEmpty && stripped.allSatisfy(\.isNumber) && stripped.count <= 5
    }

    /// "Page 3 of 100", "page 3", "p. 42", "3 / 100", "- 3 -"
    nonisolated private static func isPageOfPattern(_ line: String) -> Bool {
        let patterns = [
            #"^[Pp]age\s+\d+(\s+(of|/)\s+\d+)?$"#,
            #"^[Pp]\.\s*\d+$"#,
            #"^\d+\s*/\s*\d+$"#,
            #"^-\s*\d+\s*-$"#
        ]
        return patterns.contains { line.range(of: $0, options: .regularExpression) != nil }
    }

    /// "Chapter 1 ......... 15" — lines with dot leaders ending in a number.
    nonisolated private static func isTOCLeaderLine(_ line: String) -> Bool {
        line.range(of: #"\.{3,}\s*\d+\s*$"#, options: .regularExpression) != nil
    }

    /// "ISBN 978-0-123456-78-9", "ISBN-13: ..."
    nonisolated private static func isISBN(_ line: String) -> Bool {
        line.range(of: #"ISBN[\s:\-]*[\d\-]{10,}"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Lines starting with © or "Copyright", or containing "All rights reserved".
    nonisolated private static func isCopyrightNotice(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasPrefix("©") || lower.hasPrefix("\u{00A9}") { return true }
        if lower.hasPrefix("copyright") { return true }
        if lower.contains("all rights reserved") { return true }
        return false
    }

    /// Short navigation strings that appear as standalone lines.
    nonisolated private static func isNavigationText(_ line: String) -> Bool {
        let navPhrases: Set<String> = [
            "next", "previous", "prev", "back", "forward",
            "next chapter", "previous chapter",
            "next page", "previous page",
            "back to top", "return to top",
            "continue reading", "skip to content",
            "table of contents"
        ]
        return navPhrases.contains(line.lowercased())
    }

    /// "Printed in...", "Published by...", "First edition..."
    nonisolated private static func isPublisherBoilerplate(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasPrefix("printed in") { return true }
        if lower.hasPrefix("published by") { return true }
        if lower.hasPrefix("first published") { return true }
        if lower.range(of: #"^first\s+(edition|printing)"#, options: .regularExpression) != nil { return true }
        return false
    }
}
