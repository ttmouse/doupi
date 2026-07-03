import SwiftUI

/// Design tokens for Doupi Viewer — warm paper background, green accent.
extension Color {

    // MARK: - Backgrounds
    static let appBackground = Color(hex: "#f3f2ee")
    static let appInfoBg     = Color(hex: "#e8e6e1")
    static let appDropBg     = Color(hex: "#f0efe9")

    // MARK: - Accent
    static let appAccent       = Color(hex: "#7BC043")
    static let appAccentDeep   = Color(hex: "#4A7A23")
    static let appAccentDimmed = Color(hex: "#7BC043").opacity(0.15)

    // MARK: - Foreground & border
    static let appText   = Color(hex: "#1d1d1f")
    static let appMuted  = Color(hex: "#8a8885")
    static let appBorder = Color(hex: "#d9d6d1")

    // MARK: - Convenience initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Font helpers

extension Font {
    static let appTitle = Font.system(size: 15, weight: .medium, design: .default)
    static let appBody  = Font.system(size: 13, weight: .regular, design: .default)
    static let appSmall = Font.system(size: 11, weight: .regular, design: .default)
    static let appCode  = Font.system(size: 14, weight: .regular, design: .monospaced)
}
