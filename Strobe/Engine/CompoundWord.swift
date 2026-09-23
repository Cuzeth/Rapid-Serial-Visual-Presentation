import Foundation

/// Timing for tokens that join several words into one: `wedge-shaped`,
/// `state-of-the-art`, `1990–1995`, `and/or`, and number units such as
/// `2000 BCE`.
///
/// The tokenizer splits on whitespace and keeps number units whole, so a
/// compound takes a single word slot however many words it holds.
/// ``RSVPEngine`` adds ``additionalIntervals(for:)`` to the word's own
/// display time so the parts after the first get their share.
nonisolated enum CompoundWord {

    /// The share of a base interval each part after the first adds. A part
    /// costs less than a word of its own: it is taken in with the same glance
    /// as its neighbours, and smart timing already counts its letters.
    static let additionalPartWeight = 0.5

    /// Parts beyond this many add no further time, so a long chain of joiners
    /// (an ISBN, a file path) can't stall playback.
    static let maximumTimedParts = 4

    /// The display time `word` needs beyond a single word's, in base
    /// intervals: 0 for an ordinary word, 0.5 for `wedge-shaped`, 1.5 for
    /// `state-of-the-art` and anything longer.
    static func additionalIntervals(for word: String) -> Double {
        let parts = min(partCount(in: word), maximumTimedParts)
        return Double(parts - 1) * additionalPartWeight
    }

    /// The number of parts in `word` that each take a word's worth of
    /// reading, never less than 1.
    ///
    /// Parts are separated by a single hyphen, en dash, or slash, or by the
    /// space inside a number unit (`2000 BCE`, `10:30 PM`).
    ///
    /// - A part counts only when it holds two or more letters or digits, so
    ///   the prefix letter of `x-ray`, `e-mail`, and `T-shirt`, a stutter
    ///   (`w-w-what`), and the `a` of `one-in-a-lifetime` add nothing.
    /// - Every other mark belongs to the part it touches: `(wedge-shaped),`
    ///   and `U.S.-based` have two parts, and the `'n'` of `rock-'n'-roll` is
    ///   a one-letter part.
    /// - A leading or trailing joiner separates nothing (`-prefix`, `word-`).
    /// - Two or more joiners in a row are a dash or a URL's `//`, not a joint:
    ///   `well--maybe` is one part. An em dash never joins either — a token
    ///   fused by a dash holds separate words, which ``PunctuationMarks``
    ///   times as a dash pause.
    static func partCount(in word: String) -> Int {
        // 0xE2 leads the UTF-8 encoding of U+2010–U+2013.
        guard word.utf8.contains(where: { $0 == 0x2D || $0 == 0x2F || $0 == 0x20 || $0 == 0xE2 }) else {
            return 1
        }
        return scanParts(in: word)
    }

    /// Kept out of line so ``partCount(in:)`` stays a bare byte scan for the
    /// words without a joiner, which is nearly all of them.
    @inline(never)
    private static func scanParts(in word: String) -> Int {
        var parts = 0
        var wordCharacters = 0
        var joinerRun = 0
        for scalar in word.unicodeScalars {
            if isJoiner(scalar) {
                joinerRun += 1
                continue
            }
            if joinerRun == 1 {
                if wordCharacters >= 2 { parts += 1 }
                wordCharacters = 0
            }
            joinerRun = 0
            if isWordCharacter(scalar) { wordCharacters += 1 }
        }
        if wordCharacters >= 2 { parts += 1 }

        return max(1, parts)
    }

    @inline(__always)
    private static func isJoiner(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "-", "/", " ",
             "\u{2010}", "\u{2011}",              // ‐ hyphen, non-breaking hyphen
             "\u{2012}", "\u{2013}":              // ‒ figure dash, – en dash
            return true
        default:
            return false
        }
    }

    @inline(__always)
    private static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9":
            return true
        // The rest of ASCII and the General Punctuation block (curly quotes,
        // dashes, the ellipsis) hold no letters or digits, and are common
        // enough that skipping their property lookups matters during playback.
        case "\u{0}"..."\u{7F}", "\u{2000}"..."\u{206F}":
            return false
        default:
            return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
        }
    }
}
