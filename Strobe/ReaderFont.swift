import SwiftUI
import UIKit

/// The available font options for the RSVP reader display.
///
/// Each case maps to a bundled font with regular and bold weights.
/// Falls back to the system font if a custom font fails to load.
enum ReaderFont: String, CaseIterable, Identifiable {
    /// The UserDefaults key used to persist the font selection.
    static let storageKey = "readerFontSelection"
    static let defaultValue: ReaderFont = .fraunces

    case fraunces
    case inter
    case spaceGrotesk
    case ptSans
    case ptSerif
    case ptMono
    case jetBrainsMono

    var id: String { rawValue }

    /// Resolves a stored raw value to a font case, falling back to the default.
    static func resolve(_ rawValue: String) -> ReaderFont {
        ReaderFont(rawValue: rawValue) ?? defaultValue
    }

    var displayName: String {
        switch self {
        case .fraunces: "Fraunces"
        case .inter: "Inter"
        case .spaceGrotesk: "Space Grotesk"
        case .ptSans: "PT Sans"
        case .ptSerif: "PT Serif"
        case .ptMono: "PT Mono"
        case .jetBrainsMono: "JetBrains Mono"
        }
    }

    var regularPostScriptName: String {
        switch self {
        case .fraunces: "Fraunces-Regular"
        case .inter: "Inter-Regular"
        case .spaceGrotesk: "SpaceGrotesk-Light_Regular"
        case .ptSans: "PTSans-Regular"
        case .ptSerif: "PTSerif-Regular"
        case .ptMono: "PTMono-Regular"
        case .jetBrainsMono: "JetBrainsMono-Regular"
        }
    }

    var boldPostScriptName: String {
        switch self {
        case .fraunces: "Fraunces-Bold"
        case .inter: "Inter-Bold"
        case .spaceGrotesk: "SpaceGrotesk-Light_Bold"
        case .ptSans: "PTSans-Bold"
        case .ptSerif: "PTSerif-Bold"
        case .ptMono: "PTMono-Bold"
        case .jetBrainsMono: "JetBrainsMono-Bold"
        }
    }

    /// Returns a SwiftUI `Font` for the regular weight at the given size.
    func regularFont(size: CGFloat) -> Font {
        .custom(regularPostScriptName, size: size)
    }

    /// Returns a SwiftUI `Font` for the bold weight at the given size.
    func boldFont(size: CGFloat) -> Font {
        .custom(boldPostScriptName, size: size)
    }

    /// Returns a UIKit `UIFont`, with automatic fallback to the system font.
    func uiFont(size: CGFloat, bold: Bool = false) -> UIFont {
        let name = bold ? boldPostScriptName : regularPostScriptName
        if let custom = UIFont(name: name, size: size) {
            return custom
        }
        return .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}
