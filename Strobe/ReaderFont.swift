import SwiftUI
import UIKit

enum ReaderFont: String, CaseIterable, Identifiable {
    static let storageKey = "readerFontSelection"
    static let defaultValue: ReaderFont = .inter

    case inter
    case ptSans
    case ptSerif
    case ptMono
    case jetBrainsMono

    var id: String { rawValue }

    static func resolve(_ rawValue: String) -> ReaderFont {
        ReaderFont(rawValue: rawValue) ?? defaultValue
    }

    var displayName: String {
        switch self {
        case .inter: "Inter"
        case .ptSans: "PT Sans"
        case .ptSerif: "PT Serif"
        case .ptMono: "PT Mono"
        case .jetBrainsMono: "JetBrains Mono"
        }
    }

    var regularPostScriptName: String {
        switch self {
        case .inter: "Inter-Regular"
        case .ptSans: "PTSans-Regular"
        case .ptSerif: "PTSerif-Regular"
        case .ptMono: "PTMono-Regular"
        case .jetBrainsMono: "JetBrainsMono-Regular"
        }
    }

    var boldPostScriptName: String {
        switch self {
        case .inter: "Inter-Bold"
        case .ptSans: "PTSans-Bold"
        case .ptSerif: "PTSerif-Bold"
        case .ptMono: "PTMono-Bold"
        case .jetBrainsMono: "JetBrainsMono-Bold"
        }
    }

    func regularFont(size: CGFloat) -> Font {
        .custom(regularPostScriptName, size: size)
    }

    func boldFont(size: CGFloat) -> Font {
        .custom(boldPostScriptName, size: size)
    }

    func uiFont(size: CGFloat, bold: Bool = false) -> UIFont {
        let name = bold ? boldPostScriptName : regularPostScriptName
        if let custom = UIFont(name: name, size: size) {
            return custom
        }
        return .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}
