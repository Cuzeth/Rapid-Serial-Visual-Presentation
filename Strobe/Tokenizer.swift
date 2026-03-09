import Foundation
import NaturalLanguage

/// Splits raw text into discrete words for RSVP display.
///
/// Handles whitespace splitting, soft-hyphen removal (U+00AD),
/// non-breaking-hyphen normalization (U+2011 → ASCII hyphen),
/// line-break hyphenation merging, and standalone punctuation attachment.
///
/// For CJK text (Chinese, Japanese, Korean), uses `NLTokenizer` for
/// word segmentation since these scripts don't use spaces between words.
/// Mixed CJK/Latin text is handled automatically at the character level.
enum Tokenizer {

    /// Tokenizes a complete text string into an array of words.
    /// - Parameter text: The raw text to tokenize.
    /// - Returns: An array of display-ready word tokens.
    nonisolated static func tokenize(_ text: String) -> [String] {
        var result: [String] = []
        var carry: String?
        appendTokenizedText(text, into: &result, carry: &carry)
        if let carry, !carry.isEmpty {
            result.append(carry)
        }
        return result
    }

    /// Tokenizes text and appends the resulting words to an existing array.
    ///
    /// Supports streaming across multiple text chunks by carrying forward
    /// a trailing hyphenated word fragment between calls.
    ///
    /// CJK characters are accumulated into a separate buffer and segmented
    /// using `NLTokenizer` when a non-CJK boundary is reached. This gives
    /// automatic mixed-language support within the same text.
    ///
    /// - Parameters:
    ///   - text: The raw text to tokenize.
    ///   - output: The array to append words into.
    ///   - carry: A partial word ending with a hyphen from the previous chunk,
    ///     or `nil` if no carry-over exists. Updated in place.
    nonisolated static func appendTokenizedText(
        _ text: String,
        into output: inout [String],
        carry: inout String?
    ) {
        var tokenBuffer = String()
        tokenBuffer.reserveCapacity(32)
        var cjkBuffer = String()
        cjkBuffer.reserveCapacity(64)

        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                // Flush any pending Latin token before switching to CJK
                if !tokenBuffer.isEmpty {
                    appendBufferedToken(tokenBuffer, into: &output, carry: &carry)
                    tokenBuffer.removeAll(keepingCapacity: true)
                }
                cjkBuffer.unicodeScalars.append(scalar)
                continue
            }

            // Non-CJK character: flush any pending CJK buffer
            if !cjkBuffer.isEmpty {
                flushCJKBuffer(&cjkBuffer, into: &output)
            }

            if scalar.properties.isWhitespace {
                appendBufferedToken(tokenBuffer, into: &output, carry: &carry)
                tokenBuffer.removeAll(keepingCapacity: true)
                continue
            }

            // Strip soft hyphens (invisible break hints).
            if scalar.value == 0x00AD {
                continue
            }

            // Normalize non-breaking hyphens to standard ASCII hyphen.
            if scalar.value == 0x2011 {
                tokenBuffer.append("-")
            } else {
                tokenBuffer.unicodeScalars.append(scalar)
            }
        }

        // Flush remaining buffers
        if !cjkBuffer.isEmpty {
            flushCJKBuffer(&cjkBuffer, into: &output)
        }
        appendBufferedToken(tokenBuffer, into: &output, carry: &carry)
    }

    // MARK: - Private

    /// Short words that typically appear as joiners in compound-hyphenated
    /// expressions (e.g. "one-in-a-lifetime"). When the last segment before
    /// a line-break hyphen matches one of these, the hyphen is preserved.
    nonisolated private static let compoundJoiners: Set<String> = [
        "a", "an", "and", "at", "by", "for", "in", "of", "on", "or", "the", "to"
    ]

    /// Returns `true` when a token contains at least one letter or digit,
    /// meaning it is a real word rather than isolated punctuation like `'` or `.`.
    nonisolated private static func isReadableWord(_ token: String) -> Bool {
        token.unicodeScalars.contains { $0.properties.isAlphabetic || $0.properties.numericType != nil }
    }

    /// Processes a completed whitespace-delimited token: merges it with
    /// a carried hyphenated prefix, attaches standalone punctuation to
    /// the previous word, or appends it as a new word.
    nonisolated private static func appendBufferedToken(
        _ token: String,
        into output: inout [String],
        carry: inout String?
    ) {
        guard !token.isEmpty else { return }

        // Punctuation-only tokens (e.g. a stray period or apostrophe)
        // get glued onto the previous word rather than becoming their own word.
        if !isReadableWord(token) {
            if !output.isEmpty {
                output[output.count - 1].append(token)
            }
            return
        }

        if var pending = carry {
            if shouldMerge(pending: pending, with: token) {
                pending = merge(pending: pending, with: token)
                if pending.hasSuffix("-") {
                    carry = pending
                } else {
                    output.append(pending)
                    carry = nil
                }
                return
            }

            output.append(pending)
            carry = nil
        }

        if token.hasSuffix("-") {
            carry = token
        } else {
            output.append(token)
        }
    }

    /// Determines whether a pending hyphenated fragment should merge with the next token.
    /// Merging happens when the pending word ends with `-` and the next token starts lowercase
    /// (indicating a line-break hyphenation rather than a sentence-initial word).
    nonisolated private static func shouldMerge(pending: String, with nextToken: String) -> Bool {
        guard pending.hasSuffix("-"),
              let nextFirst = nextToken.first,
              nextFirst.isLowercase else {
            return false
        }
        return true
    }

    /// Merges a hyphenated prefix with the following token, either preserving
    /// or removing the hyphen based on compound-word heuristics.
    nonisolated private static func merge(pending: String, with nextToken: String) -> String {
        let stem = String(pending.dropLast())
        if shouldPreserveHyphen(stem: stem) {
            return stem + "-" + nextToken
        }
        return stem + nextToken
    }

    /// Decides whether a hyphen at the end of `stem` is part of a genuine
    /// compound word (e.g. "one-in-a-") rather than a line-break artifact.
    ///
    /// Heuristics:
    /// - The stem must already contain at least one internal hyphen.
    /// - The last segment is a known compound joiner or very short (≤2 chars).
    /// - For triple-or-more-segment compounds, segments up to 3 chars are allowed.
    nonisolated private static func shouldPreserveHyphen(stem: String) -> Bool {
        guard stem.contains("-") else { return false }

        let segments = stem.split(separator: "-")
        guard let last = segments.last else { return false }
        let lastSegment = last.lowercased()

        if compoundJoiners.contains(lastSegment) || lastSegment.count <= 2 {
            return true
        }

        if segments.count >= 3 && lastSegment.count <= 3 {
            return true
        }

        return false
    }

    // MARK: - CJK support

    /// Returns `true` if the scalar is a CJK ideograph, CJK punctuation,
    /// or fullwidth form — characters that belong to CJK text runs.
    nonisolated private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        // CJK Unified Ideographs
        if v >= 0x4E00 && v <= 0x9FFF { return true }
        // CJK Extension A
        if v >= 0x3400 && v <= 0x4DBF { return true }
        // CJK Compatibility Ideographs
        if v >= 0xF900 && v <= 0xFAFF { return true }
        // CJK Unified Ideographs Extension B
        if v >= 0x20000 && v <= 0x2A6DF { return true }
        // CJK punctuation and symbols (。、「」etc.)
        if v >= 0x3000 && v <= 0x303F { return true }
        // Fullwidth forms (！？，etc.)
        if v >= 0xFF00 && v <= 0xFFEF { return true }
        // Bopomofo
        if v >= 0x3100 && v <= 0x312F { return true }
        // Hiragana + Katakana (for Japanese mixed text)
        if v >= 0x3040 && v <= 0x30FF { return true }
        return false
    }

    /// Segments a buffer of CJK text into words using `NLTokenizer`
    /// and appends them to the output. CJK punctuation is attached
    /// to the preceding word.
    nonisolated private static func flushCJKBuffer(
        _ buffer: inout String,
        into output: inout [String]
    ) {
        guard !buffer.isEmpty else { return }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = buffer

        var lastEnd = buffer.startIndex

        tokenizer.enumerateTokens(in: buffer.startIndex..<buffer.endIndex) { range, _ in
            // Attach any skipped punctuation between tokens to the previous word
            if range.lowerBound > lastEnd {
                let skipped = String(buffer[lastEnd..<range.lowerBound])
                if !output.isEmpty {
                    output[output.count - 1].append(skipped)
                }
            }

            let token = String(buffer[range])
            output.append(token)
            lastEnd = range.upperBound
            return true
        }

        // Attach any trailing punctuation after the last token
        if lastEnd < buffer.endIndex {
            let trailing = String(buffer[lastEnd..<buffer.endIndex])
            if !output.isEmpty {
                output[output.count - 1].append(trailing)
            } else {
                output.append(trailing)
            }
        }

        buffer.removeAll(keepingCapacity: true)
    }
}
