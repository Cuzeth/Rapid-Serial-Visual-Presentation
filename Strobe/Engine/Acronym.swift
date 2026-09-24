import Foundation

/// Timing for tokens that are read letter by letter rather than recognized by
/// their shape: `FBI`, `U.S.A.`, `PhD`, `B2B`, `XIV`.
///
/// An acronym is short, so smart timing gives it next to nothing, yet every
/// letter in it is a syllable of inner speech. ``RSVPEngine`` adds
/// ``additionalIntervals(at:in:)`` to the word's own display time so the
/// letter names after the first get their share.
nonisolated enum Acronym {

    /// The share of a base interval each letter name after the first adds. A
    /// base interval covers an average word of about a syllable and a half,
    /// so a letter name spoken in full is worth up to half an interval; a
    /// familiar acronym is partly recognized on sight, which halves that.
    static let additionalLetterWeight = 0.25

    /// Letter names beyond this many add no further time. A longer acronym is
    /// usually pronounced as a word (`UNESCO`, `NASDAQ`), with fewer syllables
    /// than letters.
    static let maximumTimedLetters = 4

    /// A part with more capitals than this is an ordinary word written in
    /// capitals (`CHAPTER`, `WARNING`), not an acronym.
    static let maximumCapitals = 6

    /// This many words in capitals in a row are a passage written in capitals
    /// — a heading, a title page, a shouted or legal sentence — not acronyms.
    static let capitalsRunLength = 3

    /// The display time the word at `index` needs beyond a single word's, in
    /// base intervals: 0 for an ordinary word, 0.25 for `UK`, 0.5 for `FBI`,
    /// 0.75 for `NASA`, `HTML`, and anything longer.
    ///
    /// A word in capitals can't be told from an acronym by itself (`STOP`,
    /// `NASA`), so its neighbours decide. Inside a passage in capitals —
    /// ``capitalsRunLength`` or more such words in a row — it adds nothing,
    /// unless commas, semicolons, or colons separate all of them, as in a
    /// list (`PNG, JPEG, GIF`). A lone or paired word in capitals is timed
    /// (`REST API`, `NO!`). An acronym with a lowercase letter (`CPUs`, `PhD`)
    /// is timed wherever it stands.
    static func additionalIntervals(at index: Int, in words: [String]) -> Double {
        guard words.indices.contains(index) else { return 0 }
        let shape = shape(of: words[index])
        guard shape.letters > 0 else { return 0 }
        if shape.isWrittenInCapitals, isInCapitalsPassage(at: index, in: words) { return 0 }
        return Double(min(shape.letters, maximumTimedLetters) - 1) * additionalLetterWeight
    }

    /// The number of letter names read out of `word`, or 0 when it is not an
    /// acronym. Ignores the surrounding words.
    ///
    /// The token is judged part by part, split at hyphens, dashes, and
    /// slashes. A part reads as letters when it has more capitals than
    /// lowercase letters (`FBI`, `PhD`, `iOS`, `mRNA`) or no letters at all
    /// (`19`), and as a word otherwise (`The`, `iPhone`, `funded`). The letter
    /// names of the parts read as letters are summed when one of those parts
    /// has a capital and the sum is at least 2: `NASA-funded` has 4, `TCP/IP`
    /// 5, `COVID-19` 6, `I/O` 2, and `X-ray`, `I`, and `1990-1995` none.
    ///
    /// Every capital and lowercase letter is a letter name, a run of digits is
    /// one (`B2B` has 3, `G20` 2), and so is an ampersand after a capital
    /// (`AT&T` has 4). Periods and edge punctuation are skipped: `U.S.A.` and
    /// `(USA),` have 3.
    ///
    /// - A final lowercase `s` is a plural, not a letter name: `CPUs` and
    ///   `PDFs` have 3, and `Ms`, a single letter, none.
    /// - Lowercase letters after an apostrophe are an ending (`NASA's` has 4).
    ///   A capital there marks a contraction or a name (`DON'T`, `O'NEILL`),
    ///   and the part reads as a word — so does `NASA'S`, whose `'S` can't be
    ///   told from the one in `IT'S`.
    /// - A part with more than ``maximumCapitals`` capitals reads as a word.
    /// - Roman numerals (`XIV`, `VIII`) count: they are decoded symbol by
    ///   symbol too. Lowercase abbreviations (`e.g.`, `a.m.`) don't: they are
    ///   frequent enough to be read whole.
    /// - Greek, Cyrillic, and Armenian capitals count like Latin ones (`США`,
    ///   `ΗΠΑ`). Other scripts count as caseless, so CJK and Arabic text never
    ///   counts, and neither do fullwidth capitals.
    static func letterCount(in word: String) -> Int {
        shape(of: word).letters
    }

    /// Whether `word` has a capital and no lowercase letter: `STOP`, `I`,
    /// `DON'T`, `U.S.A.`, `B2B`, `COVID-19`.
    static func isWrittenInCapitals(_ word: String) -> Bool {
        var hasCapital = false
        for scalar in word.unicodeScalars {
            switch letterCase(of: scalar) {
            case .capital: hasCapital = true
            case .lowercase: return false
            case .uncased: break
            }
        }
        return hasCapital
    }

    private struct Shape {
        var letters = 0
        var isWrittenInCapitals = false
    }

    private static func shape(of word: String) -> Shape {
        guard word.unicodeScalars.contains(where: { letterCase(of: $0) == .capital }) else {
            return Shape()
        }
        return scanShape(of: word)
    }

    /// Kept out of line so ``shape(of:)`` stays a bare scan for the words
    /// without a capital, which is most of them.
    @inline(never)
    private static func scanShape(of word: String) -> Shape {
        var letters = 0
        var hasCapitalInLetters = false
        var hasCapital = false
        var hasLowercase = false
        var part = Part()

        func finishPart() {
            guard let names = part.letterNames else { return }
            letters += names
            if part.capitals > 0 { hasCapitalInLetters = true }
        }

        for scalar in word.unicodeScalars {
            switch kind(of: scalar) {
            case .capital:
                hasCapital = true
                part.addCapital()
            case .lowercase:
                hasLowercase = true
                part.addLowercase(isPluralEnding: scalar == "s")
            case .digit:
                part.addDigit()
            case .ampersand:
                part.addAmpersand()
            case .apostrophe:
                part.addApostrophe()
            case .separator:
                finishPart()
                part = Part()
            case .other:
                break
            }
        }
        finishPart()

        return Shape(
            letters: hasCapitalInLetters && letters >= 2 ? letters : 0,
            isWrittenInCapitals: hasCapital && !hasLowercase
        )
    }

    /// The running counts for one part of a token.
    private struct Part {
        private(set) var capitals = 0
        private var lowercase = 0
        private var names = 0
        private var isInNumber = false
        private var isAfterApostrophe = false
        private var hasCapitalAfterApostrophe = false
        private var endsInPluralS = false

        mutating func addCapital() {
            guard !isAfterApostrophe else {
                hasCapitalAfterApostrophe = true
                return
            }
            capitals += 1
            names += 1
            isInNumber = false
            endsInPluralS = false
        }

        mutating func addLowercase(isPluralEnding: Bool) {
            guard !isAfterApostrophe else { return }
            lowercase += 1
            names += 1
            isInNumber = false
            endsInPluralS = isPluralEnding
        }

        mutating func addDigit() {
            if !isInNumber { names += 1 }
            isInNumber = true
            endsInPluralS = false
        }

        mutating func addAmpersand() {
            if capitals > 0 { names += 1 }
            isInNumber = false
            endsInPluralS = false
        }

        /// A leading apostrophe is an opening quote, not part of the word.
        mutating func addApostrophe() {
            if capitals + lowercase > 0 { isAfterApostrophe = true }
        }

        /// The part's letter names, or nil when it reads as a word.
        var letterNames: Int? {
            let plural = endsInPluralS ? 1 : 0
            let lowercase = lowercase - plural
            guard !hasCapitalAfterApostrophe,
                  capitals <= Acronym.maximumCapitals,
                  lowercase == 0 || capitals > lowercase else { return nil }
            return names - plural
        }
    }

    /// Whether the word at `index`, itself written in capitals, belongs to a
    /// passage in capitals. Looks no further than ``capitalsRunLength`` − 1
    /// words to either side.
    private static func isInCapitalsPassage(at index: Int, in words: [String]) -> Bool {
        let reach = capitalsRunLength - 1

        var first = index
        while first > 0, index - first < reach, isWrittenInCapitals(words[first - 1]) {
            first -= 1
        }
        var last = index
        while last + 1 < words.count, last - index < reach, isWrittenInCapitals(words[last + 1]) {
            last += 1
        }
        guard last - first + 1 >= capitalsRunLength else { return false }

        // A list separates every item from the next with a clause mark.
        return words[first..<last].contains { !PunctuationMarks.marks(in: $0).contains(.clause) }
    }

    private enum ScalarKind {
        case capital, lowercase, digit, ampersand, apostrophe, separator, other
    }

    @inline(__always)
    private static func kind(of scalar: Unicode.Scalar) -> ScalarKind {
        switch scalar {
        case "0"..."9":
            return .digit
        case "&":
            return .ampersand
        case "'", "\u{2019}":                     // ' ’
            return .apostrophe
        case "-", "/",
             "\u{2010}"..."\u{2015}":             // ‐ ‑ ‒ – — ―
            return .separator
        default:
            switch letterCase(of: scalar) {
            case .capital: return .capital
            case .lowercase: return .lowercase
            case .uncased: return .other
            }
        }
    }

    private enum LetterCase: UInt64 {
        case uncased, capital, lowercase
    }

    @inline(__always)
    private static func letterCase(of scalar: Unicode.Scalar) -> LetterCase {
        let value = scalar.value
        switch value {
        case 0x41...0x5A:
            return .capital
        case 0x61...0x7A:
            return .lowercase
        case 0x80..<0x2000:
            let bits = caseTable[Int(value / 32)] >> UInt64(value % 32 * 2) & 0b11
            return LetterCase(rawValue: bits) ?? .uncased
        default:
            return .uncased
        }
    }

    /// The case of every scalar below U+2000, two bits each, read from the
    /// Unicode general categories once so that no letter costs a property
    /// lookup during playback. Only the Latin, Greek, Cyrillic, and Armenian
    /// blocks and the Latin and Greek extensions are read; the scripts between
    /// them (Georgian, Cherokee) count as caseless.
    private static let caseTable: [UInt64] = {
        var table = [UInt64](repeating: 0, count: 0x2000 / 32)
        for value in [0x80..<0x590, 0x1E00..<0x2000].joined() {
            guard let scalar = Unicode.Scalar(UInt32(value)) else { continue }
            let letterCase: LetterCase
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .titlecaseLetter:
                letterCase = .capital
            case .lowercaseLetter:
                letterCase = .lowercase
            default:
                continue
            }
            table[value / 32] |= letterCase.rawValue << UInt64(value % 32 * 2)
        }
        return table
    }()
}
