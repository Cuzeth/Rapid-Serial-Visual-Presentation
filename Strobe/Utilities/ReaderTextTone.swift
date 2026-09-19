import SwiftUI

/// The available color tones for the RSVP reader display.
///
/// Each case pairs a word color with an ORP anchor color, so the anchor
/// letter stays distinguishable from the rest of the word in every tone.
nonisolated enum ReaderTextTone: String, CaseIterable, Identifiable {
    /// The UserDefaults key used to persist the tone selection.
    static let storageKey = "readerTextTone"
    static let defaultValue: ReaderTextTone = .bright

    case bright
    case soft
    case sepia
    case night

    var id: String { rawValue }

    /// Resolves a stored raw value to a tone case, falling back to the default.
    static func resolve(_ rawValue: String) -> ReaderTextTone {
        ReaderTextTone(rawValue: rawValue) ?? defaultValue
    }

    var displayName: String {
        switch self {
        case .bright: "Bright"
        case .soft: "Soft"
        case .sepia: "Sepia"
        case .night: "Night"
        }
    }

    var textRGB: UInt32 {
        switch self {
        case .bright: 0xFFFFFF
        case .soft: 0xB4B4B4
        case .sepia: 0xD6C2A1
        case .night: 0x9C8466
        }
    }

    var anchorRGB: UInt32 {
        switch self {
        case .bright: 0xFF453A
        case .soft: 0xC8554D
        case .sepia: 0xCC5A45
        case .night: 0xA8402F
        }
    }

    /// The color of the word being read.
    var textColor: Color { Self.color(textRGB) }

    /// The color of the ORP anchor letter and its guide line.
    var anchorColor: Color { Self.color(anchorRGB) }

    private static func color(_ rgb: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double(rgb >> 16 & 0xFF) / 255,
            green: Double(rgb >> 8 & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
