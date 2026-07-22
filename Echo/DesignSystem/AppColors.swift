import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// A color that resolves differently in light vs dark mode — the Swift
    /// equivalent of the web app's @media (prefers-color-scheme) token pairs.
    static func dynamic(light: String, dark: String) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }

}

/// 1:1 port of app/styles/tokens.css — same hex values, same dark/light pairing.
enum AppColors {
    // Neutrals (dark value first in tokens.css :root, light value from the media override)
    static let neutral0   = Color.dynamic(light: "#FFFFFF", dark: "#0A0A0A")
    static let neutral100 = Color.dynamic(light: "#FAFAFA", dark: "#111111")
    static let neutral200 = Color.dynamic(light: "#F5F5F5", dark: "#1A1A1A")
    static let neutral300 = Color.dynamic(light: "#E5E5E5", dark: "#242424")
    static let neutral400 = Color.dynamic(light: "#D4D4D4", dark: "#2E2E2E")
    static let neutral500 = Color.dynamic(light: "#A3A3A3", dark: "#525252")
    static let neutral600 = Color.dynamic(light: "#737373", dark: "#737373")
    static let neutral700 = Color.dynamic(light: "#525252", dark: "#A3A3A3")
    static let neutral800 = Color.dynamic(light: "#262626", dark: "#D4D4D4")
    static let neutral900 = Color.dynamic(light: "#0A0A0A", dark: "#F5F5F5")

    // Semantic
    static let success100 = Color.dynamic(light: "#F0FDF4", dark: "#062012")
    static let success500 = Color.dynamic(light: "#16A34A", dark: "#22C55E")
    static let success900 = Color.dynamic(light: "#14532D", dark: "#6EE7A8")

    static let info100 = Color.dynamic(light: "#EFF6FF", dark: "#060F25")
    static let info500 = Color.dynamic(light: "#2563EB", dark: "#3B82F6")
    static let info900 = Color.dynamic(light: "#1E3A5F", dark: "#93C5FD")

    static let warning100 = Color.dynamic(light: "#FFFBEB", dark: "#1C1100")
    static let warning500 = Color.dynamic(light: "#D97706", dark: "#F59E0B")
    static let warning900 = Color.dynamic(light: "#78350F", dark: "#FCD34D")

    static let error100 = Color.dynamic(light: "#FEF2F2", dark: "#1C0808")
    static let error400 = Color.dynamic(light: "#F87171", dark: "#FCA5A5")
    static let error500 = Color.dynamic(light: "#DC2626", dark: "#EF4444")
    static let error900 = Color.dynamic(light: "#7F1D1D", dark: "#FCA5A5")

    // Category dots
    static let categoryTalk     = Color.dynamic(light: "#3B82F6", dark: "#93C5FD")
    static let categoryTraining = Color.dynamic(light: "#16A34A", dark: "#86EFAC")
    static let categoryPanel    = Color.dynamic(light: "#D97706", dark: "#FCD34D")

    // Chip (pill) fill/border — rgba(white/black, low alpha) per mode
    static let chipBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.02)
            : UIColor.black.withAlphaComponent(0.04)
    })

    static let chipBorder = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.13)
            : UIColor.black.withAlphaComponent(0.12)
    })

    // card-bg / card-border resolve to *different* neutral steps per mode in tokens.css,
    // so they're defined directly rather than derived from the neutral scale above.
    static let cardBackground = Color.dynamic(light: "#FAFAFA", dark: "#1A1A1A") // light: neutral-100, dark: neutral-200
    static let cardBorder = Color.dynamic(light: "#E5E5E5", dark: "#2E2E2E")     // light: neutral-300, dark: neutral-400
}
