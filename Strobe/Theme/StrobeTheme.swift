import SwiftUI

struct StrobeTheme {
    static let background = Color(hex: "050505") // Deep, almost black
    static let surface = Color(hex: "121212") // Slightly lighter for cards/sheets
    static let accent = Color(hex: "FF3B30") // Vibrant Red/Orange - "Strobe Red"
    static let textPrimary = Color(hex: "FAFAFA") // Off-white
    static let textSecondary = Color(hex: "A0A0A0") // Grey

    struct Gradients {
        static let mainBackground = LinearGradient(
            colors: [Color(hex: "050505"), Color(hex: "0A0A0A")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let card = LinearGradient(
            colors: [Color(hex: "1A1A1A"), Color(hex: "121212")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Typography
    
    static func titleFont(size: CGFloat) -> Font {
        .custom("Fraunces-Bold", size: size)
    }
    
    static func bodyFont(size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "SpaceGrotesk-Light_Bold" : "SpaceGrotesk-Light_Regular", size: size)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct StrobeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
