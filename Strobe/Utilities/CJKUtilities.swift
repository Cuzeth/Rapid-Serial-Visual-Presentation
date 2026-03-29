import Foundation

/// Shared CJK character detection utilities.
///
/// Single source of truth for Unicode range checks used by the tokenizer,
/// word complexity analyzer, word view, and text input view.
enum CJKUtilities {

    /// Returns `true` if the scalar is a CJK ideograph, kana, CJK punctuation,
    /// or fullwidth form — characters that belong to CJK text runs.
    nonisolated static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
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

    /// Returns `true` if the scalar is a CJK ideograph (Han character only,
    /// excluding kana, punctuation, and fullwidth forms).
    nonisolated static func isHanIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (v >= 0x4E00 && v <= 0x9FFF)
            || (v >= 0x3400 && v <= 0x4DBF)
            || (v >= 0xF900 && v <= 0xFAFF)
            || (v >= 0x20000 && v <= 0x2A6DF)
    }

    /// Returns `true` if the majority of characters in the string are CJK.
    nonisolated static func isCJKDominant(_ word: String) -> Bool {
        var cjkCount = 0
        var totalCount = 0
        for scalar in word.unicodeScalars {
            totalCount += 1
            if isCJK(scalar) { cjkCount += 1 }
        }
        return totalCount > 0 && cjkCount > totalCount / 2
    }
}
