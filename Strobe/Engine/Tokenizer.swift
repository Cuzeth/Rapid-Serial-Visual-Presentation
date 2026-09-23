import Foundation
import NaturalLanguage

/// Splits raw text into discrete words for RSVP display.
///
/// Handles whitespace splitting, soft-hyphen removal (U+00AD),
/// non-breaking-hyphen normalization (U+2011 → ASCII hyphen),
/// line-break hyphenation merging, splitting of dash-joined words
/// (`elements—stone` → `elements—`, `stone`), joining of number units
/// (`2000 BCE`, `AD 79`, `10:30 PM`), and standalone punctuation attachment.
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
    ///   - startsBlock: Whether `text` begins a new paragraph, heading, or
    ///     other block. A number unit never joins across the start of a
    ///     block, so the first word of `text` stays apart from the last word
    ///     already in `output`.
    nonisolated static func appendTokenizedText(
        _ text: String,
        into output: inout [String],
        carry: inout String?,
        startsBlock: Bool = false
    ) {
        // Words before this index belong to an earlier block.
        let firstOpener = startsBlock ? output.count : 0
        var tokenBuffer = String()
        tokenBuffer.reserveCapacity(32)
        var cjkBuffer = String()
        cjkBuffer.reserveCapacity(64)

        for scalar in text.unicodeScalars {
            if CJKUtilities.isCJK(scalar) {
                // Flush any pending Latin token before switching to CJK
                if !tokenBuffer.isEmpty {
                    appendSplittingAtDashes(tokenBuffer, firstOpener: firstOpener, into: &output, carry: &carry)
                    tokenBuffer.removeAll(keepingCapacity: true)
                }
                // A hyphenated Latin fragment can't merge with CJK — emit it
                // now, or it would be appended *after* the CJK words that
                // follow it, reordering the text.
                if let pending = carry {
                    output.append(pending)
                    carry = nil
                }
                cjkBuffer.unicodeScalars.append(scalar)
                continue
            }

            // Non-CJK character: flush any pending CJK buffer
            if !cjkBuffer.isEmpty {
                flushCJKBuffer(&cjkBuffer, into: &output)
            }

            if scalar.properties.isWhitespace {
                appendSplittingAtDashes(tokenBuffer, firstOpener: firstOpener, into: &output, carry: &carry)
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
        appendSplittingAtDashes(tokenBuffer, firstOpener: firstOpener, into: &output, carry: &carry)
    }

    // MARK: - Private

    /// Short words that typically appear as joiners in compound-hyphenated
    /// expressions (e.g. "one-in-a-lifetime"). When the last segment before
    /// a line-break hyphen matches one of these, the hyphen is preserved.
    nonisolated private static let compoundJoiners: Set<String> = [
        "a", "an", "and", "at", "by", "for", "in", "of", "on", "or", "the", "to"
    ]

    /// Returns `true` for a letter or digit — a scalar that makes a token
    /// readable rather than punctuation.
    nonisolated private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }

    /// Returns `true` when a token contains at least one letter or digit,
    /// meaning it is a real word rather than isolated punctuation like `'` or `.`.
    nonisolated private static func isReadableWord(_ token: String) -> Bool {
        token.unicodeScalars.contains(where: isWordScalar)
    }

    /// Returns `true` for the em dash (U+2014) and horizontal bar (U+2015),
    /// which separate words even when written without surrounding spaces.
    nonisolated private static func isWordBreakingDash(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x2014 || scalar.value == 0x2015
    }

    /// Returns `true` for scalars that can form a dash run: the ASCII hyphen,
    /// the en dash (U+2013), and the word-breaking dashes.
    nonisolated private static func isDashRunScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x002D || scalar.value == 0x2013 || isWordBreakingDash(scalar)
    }

    /// Returns `true` for marks that can close a quotation or bracket,
    /// including straight quotes, which may also open one.
    nonisolated private static func isClosingMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .closePunctuation, .finalPunctuation:
            return true
        default:
            return scalar == "\"" || scalar == "'"
        }
    }

    /// Returns `true` when a token ends with a single hyphen that may be a
    /// line-break hyphenation. A hyphen that ends a longer dash run
    /// (`word--`) is a dash, never a fragment to merge with the next token.
    nonisolated private static func endsWithLineBreakHyphen(_ token: String) -> Bool {
        var trailing = token.unicodeScalars.reversed().makeIterator()
        guard trailing.next() == "-" else { return false }
        guard let previous = trailing.next() else { return true }
        return !isDashRunScalar(previous)
    }

    /// Splits a whitespace-delimited token at dashes that join two words
    /// (`elements—stone,` → `elements—`, `stone,`) and processes each piece
    /// as its own token. The dash stays on the preceding word, together with
    /// any closing quotes or brackets that directly follow it.
    ///
    /// A dash run is a word boundary when it contains an em dash (U+2014) or
    /// horizontal bar (U+2015), or when it is two or more hyphens or en
    /// dashes long (`word--word`). A single hyphen or en dash never splits,
    /// so compounds and ranges (`wedge-shaped`, `1990–1995`) stay whole.
    /// A run with no letter or digit before it (`—Hello`) or after it
    /// (`wait—”`) has no second word to separate and is left in place.
    nonisolated private static func appendSplittingAtDashes(
        _ token: String,
        firstOpener: Int,
        into output: inout [String],
        carry: inout String?
    ) {
        guard token.unicodeScalars.contains(where: isDashRunScalar) else {
            appendBufferedToken(token, firstOpener: firstOpener, into: &output, carry: &carry)
            return
        }

        let scalars = Array(token.unicodeScalars)
        var pieceStart = 0
        var pieceIsReadable = false
        var index = 0

        func appendPiece(upTo end: Int) {
            var piece = String()
            piece.unicodeScalars.append(contentsOf: scalars[pieceStart..<end])
            appendBufferedToken(
                piece, canCarry: end == scalars.count, firstOpener: firstOpener, into: &output, carry: &carry
            )
        }

        while index < scalars.count {
            guard isDashRunScalar(scalars[index]) else {
                if isWordScalar(scalars[index]) { pieceIsReadable = true }
                index += 1
                continue
            }

            var end = index
            var isBoundary = false
            while end < scalars.count, isDashRunScalar(scalars[end]) {
                if isWordBreakingDash(scalars[end]) { isBoundary = true }
                end += 1
            }
            if end - index >= 2 { isBoundary = true }

            guard isBoundary, pieceIsReadable else {
                index = end
                continue
            }

            // Closing marks (and any dashes after them) stay with the dash:
            // `thought—”—she` → `thought—”—`, `she`. A mark directly before a
            // letter or digit opens the next word instead: `said—"Hello"`.
            while end < scalars.count {
                if isDashRunScalar(scalars[end]) {
                    end += 1
                } else if isClosingMark(scalars[end]),
                          end + 1 == scalars.count || !isWordScalar(scalars[end + 1]) {
                    end += 1
                } else {
                    break
                }
            }

            guard scalars[end...].contains(where: isWordScalar) else { break }

            appendPiece(upTo: end)
            pieceStart = end
            pieceIsReadable = false
            index = end
        }

        appendPiece(upTo: scalars.count)
    }

    /// Processes a completed token: merges it with a carried hyphenated
    /// prefix, attaches standalone punctuation to the previous word, joins it
    /// to the previous word as a number unit, or appends it as a new word.
    ///
    /// `canCarry` is `false` for a piece cut from the middle of a token: text
    /// follows it directly, so a trailing hyphen there is not a line break.
    /// Words in `output` before `firstOpener` never open a number unit.
    nonisolated private static func appendBufferedToken(
        _ token: String,
        canCarry: Bool = true,
        firstOpener: Int,
        into output: inout [String],
        carry: inout String?
    ) {
        guard !token.isEmpty else { return }

        // Punctuation-only tokens (e.g. a stray period or apostrophe)
        // get glued onto the previous word rather than becoming their own word.
        if !isReadableWord(token) {
            if let pending = carry {
                // Punctuation can't continue a hyphenated fragment — flush
                // the fragment with the punctuation attached instead of
                // silently dropping the token when output is empty.
                output.append(pending + token)
                carry = nil
            } else if !output.isEmpty {
                output[output.count - 1].append(token)
            }
            return
        }

        if var pending = carry {
            if shouldMerge(pending: pending, with: token) {
                pending = merge(pending: pending, with: token)
                if canCarry, endsWithLineBreakHyphen(pending) {
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

        if canCarry, endsWithLineBreakHyphen(token) {
            carry = token
        } else if !joinUnit(token, canCarry: canCarry, firstOpener: firstOpener, into: &output, carry: &carry) {
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

    // MARK: - Number units

    /// Era designators that follow a year (`2000 BCE`, `44 B.C.`), without
    /// the final period of the dotted forms.
    ///
    /// Undotted designators join in uppercase only — `ad`, `ah`, and `ce` are
    /// words, and `bc` is shorthand for "because". Lowercase `bce` joins too:
    /// it means nothing else, and small caps often reach the text lowercase.
    nonisolated private static let eraDesignators: Set<String> = [
        "BCE", "BC", "CE", "AD", "AH", "bce",
        "B.C.E", "B.C", "C.E", "A.D", "A.H", "b.c.e", "b.c", "c.e", "a.d", "a.h"
    ]

    /// Era designators that precede a year (`AD 79`).
    nonisolated private static let leadingEraDesignators: Set<String> = [
        "AD", "AH", "A.D.", "A.H.", "a.d.", "a.h."
    ]

    /// Designators that follow a 12-hour clock time (`10:30 PM`), without
    /// the final period of the dotted forms. Undotted lowercase forms are left
    /// out: `am` is a word (`I am`, German `am`), and `pm` alone would join
    /// only one end of `9 am to 5 pm`.
    nonisolated private static let meridiemDesignators: Set<String> = [
        "AM", "PM", "A.M", "P.M", "a.m", "p.m"
    ]

    /// The most digits a number can have and still join as a year
    /// (`250,000 BCE`); longer numbers are counts, not dates.
    nonisolated private static let maximumYearDigits = 6

    /// First bytes a unit's second half can start with: an ASCII digit or the
    /// first letter of a designator. Checked before anything else, so most
    /// tokens leave the unit check after one byte.
    nonisolated private static let unitCloserInitials: [Bool] = {
        var table = [Bool](repeating: false, count: 256)
        for digit in UInt8(ascii: "0")...UInt8(ascii: "9") {
            table[Int(digit)] = true
        }
        for designator in eraDesignators.union(leadingEraDesignators).union(meridiemDesignators) {
            if let first = designator.utf8.first { table[Int(first)] = true }
        }
        return table
    }()

    /// The first half of a number unit.
    nonisolated private enum UnitOpener {
        /// A numeral that reads as a year, a 12-hour clock time, or either
        /// (`10`).
        case numeral(isYear: Bool, isClock: Bool)
        /// An era designator that precedes its year (`AD`).
        case era
    }

    /// Joins `token` onto the previous word when the two are read as one
    /// unit: a year and its era (`2000 BCE`, `AD 79`) or a 12-hour clock time
    /// and its meridiem (`10:30 PM`). The halves are joined by a plain space.
    ///
    /// The first half may open with brackets or quotes but must end with its
    /// numeral or designator — `2000.` or `2000,` closes a clause, so nothing
    /// joins across it. The second half must start with its designator or
    /// numeral and keeps its trailing punctuation (`(2000 BCE),`). The
    /// previous word is read back from `output`, so a unit split across
    /// streamed chunks still joins.
    ///
    /// - Returns: `false` when there is no unit, leaving `output` untouched.
    nonisolated private static func joinUnit(
        _ token: String,
        canCarry: Bool,
        firstOpener: Int,
        into output: inout [String],
        carry: inout String?
    ) -> Bool {
        guard let first = token.utf8.first, unitCloserInitials[Int(first)], output.count > firstOpener,
              let opener = output.last, let kind = unitOpener(opener) else { return false }

        if let unit = joinedUnit(opener, kind, token) {
            output[output.count - 1] = unit
            return true
        }

        // `27 BCE–14 CE`: an en dash ties the designator to the first half of
        // the next unit. A hyphen doesn't — `AH-64` is a helicopter.
        let scalars = token.unicodeScalars
        guard let dash = scalars.firstIndex(of: "\u{2013}") else { return false }
        let nextStart = scalars.index(after: dash)
        let next = String(scalars[nextStart...])
        guard unitOpener(next) != nil,
              let unit = joinedUnit(opener, kind, String(scalars[..<nextStart])) else { return false }

        output[output.count - 1] = unit
        appendBufferedToken(next, canCarry: canCarry, firstOpener: firstOpener, into: &output, carry: &carry)
        return true
    }

    /// Classifies `word` as the first half of a number unit, or returns `nil`
    /// when it can't be one. Only opening brackets, quotes, and `~` may come
    /// before the numeral or designator, and nothing after it.
    nonisolated private static func unitOpener(_ word: String) -> UnitOpener? {
        let utf8 = word.utf8
        guard let last = utf8.last else { return nil }
        switch last {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            break
        case UInt8(ascii: "s"):
            guard let previous = utf8.dropLast().last,
                  (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(previous) else { return nil }
        case UInt8(ascii: "D"), UInt8(ascii: "H"), UInt8(ascii: "."):
            let core = word.unicodeScalars.drop(while: canPrecedeUnit)
            guard core.dropFirst(4).isEmpty, leadingEraDesignators.contains(String(core)) else { return nil }
            return .era
        default:
            return nil
        }

        let core = word.unicodeScalars.drop(while: canPrecedeUnit)
        let isYear = isYearNumeral(core)
        let isClock = isClockNumeral(core)
        return isYear || isClock ? .numeral(isYear: isYear, isClock: isClock) : nil
    }

    /// Returns `opener` and `closer` joined into one word, or `nil` when
    /// `closer` doesn't complete the unit `opener` starts.
    nonisolated private static func joinedUnit(_ opener: String, _ kind: UnitOpener, _ closer: String) -> String? {
        var core = closer.unicodeScalars[...]
        while let last = core.last, canFollowUnit(last) {
            core.removeLast()
        }

        let isUnit: Bool
        switch kind {
        case .era:
            isUnit = isYearNumeral(core)
        case .numeral(let isYear, let isClock):
            let designator = String(core)
            isUnit = (isYear && eraDesignators.contains(designator))
                || (isClock && meridiemDesignators.contains(designator))
        }
        return isUnit ? opener + " " + closer : nil
    }

    /// Returns `true` for marks that can come before the first half of a
    /// unit: opening brackets and quotes, and `~` (approximately).
    nonisolated private static func canPrecedeUnit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .openPunctuation, .initialPunctuation:
            return true
        default:
            return scalar == "\"" || scalar == "'" || scalar == "~"
        }
    }

    /// Returns `true` for marks that can come after the second half of a
    /// unit: any punctuation but `%`, which makes the number a percentage
    /// (`AD 50%`).
    nonisolated private static func canFollowUnit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return scalar != "%"
        default:
            return false
        }
    }

    nonisolated private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar)
    }

    /// Returns `true` for a year numeral: a number, a range of two
    /// (`2000–1500`), or a plural (`400s`).
    nonisolated private static func isYearNumeral(_ scalars: Substring.UnicodeScalarView) -> Bool {
        var scalars = scalars
        if scalars.last == "s" {
            scalars.removeLast()
        }
        guard let dash = scalars.firstIndex(where: { $0 == "-" || $0 == "\u{2013}" }) else {
            return isYearNumber(scalars)
        }
        return isYearNumber(scalars[..<dash]) && isYearNumber(scalars[scalars.index(after: dash)...])
    }

    /// Returns `true` for up to `maximumYearDigits` digits, optionally
    /// grouped in thousands by commas (`10,000`).
    nonisolated private static func isYearNumber(_ scalars: Substring.UnicodeScalarView) -> Bool {
        var digits = 0
        var groupLength = 0
        var isGrouped = false
        for scalar in scalars {
            if isASCIIDigit(scalar) {
                digits += 1
                groupLength += 1
            } else if scalar == ",", groupLength > 0, groupLength <= 3, !isGrouped || groupLength == 3 {
                isGrouped = true
                groupLength = 0
            } else {
                return false
            }
        }
        return (1...maximumYearDigits).contains(digits) && (!isGrouped || groupLength == 3)
    }

    /// Returns `true` for a 12-hour clock time: an hour from 1 to 12,
    /// optionally with minutes (`10`, `10:30`, `9.05`).
    nonisolated private static func isClockNumeral(_ scalars: Substring.UnicodeScalarView) -> Bool {
        var hour = 0
        var hourDigits = 0
        var minute = 0
        var minuteDigits: Int?
        for scalar in scalars {
            if isASCIIDigit(scalar) {
                let value = Int(scalar.value) - 48
                if let digits = minuteDigits {
                    guard digits < 2 else { return false }
                    minute = minute * 10 + value
                    minuteDigits = digits + 1
                } else {
                    guard hourDigits < 2 else { return false }
                    hour = hour * 10 + value
                    hourDigits += 1
                }
            } else if scalar == ":" || scalar == ".", minuteDigits == nil {
                minuteDigits = 0
            } else {
                return false
            }
        }
        guard (1...12).contains(hour) else { return false }
        return minuteDigits.map { $0 == 2 && minute < 60 } ?? true
    }

    // MARK: - CJK support

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
