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
}

/// Design tokens for the "recap — iOS dark UI" system: soft-charcoal surfaces, a
/// warm amber accent, and Apple's slightly-cool label white for text. Dark-mode
/// only (the app pins `.preferredColorScheme(.dark)`), so tokens are single
/// values rather than light/dark pairs.
enum AppColors {
    /// Apple's label white (rgba 235,235,245) — text opacities are taken from this.
    private static let label = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255)

    // MARK: - Brand / accent
    static let accent       = Color(hex: "F0A24A")   // warm amber
    static let accentText   = Color(hex: "2A1503")   // text/icon on the accent fill
    static let accentSoft    = Color(hex: "F0A24A").opacity(0.14)
    static let accentBorder  = Color(hex: "F0A24A").opacity(0.40)

    // MARK: - Surfaces (charcoal ramp)
    static let backgroundDeep  = Color(hex: "0F1012") // canvas behind everything
    static let background      = Color(hex: "17181B") // screen background
    static let contentColumn   = Color(hex: "1B1C20") // iPad content pane
    static let bar             = Color(hex: "1D1E22") // sidebar & bottom bars
    static let surface         = Color(hex: "212328") // cards & inputs
    static let composerField   = Color(hex: "282B31") // note composer input
    static let surfaceElevated = Color(hex: "32353B") // menus / dialogs (glass base)

    // MARK: - Hairlines (pure white, low alpha)
    static let separator       = Color.white.opacity(0.06)
    static let separatorStrong = Color.white.opacity(0.10)

    // MARK: - Text
    static let textPrimary   = Color(hex: "F5F5F7")
    static let textBright    = Color(hex: "EDEDEF")
    static let textSecondary = label.opacity(0.60)
    static let textTertiary  = label.opacity(0.45)
    static let textFaint     = label.opacity(0.35)

    // MARK: - Destructive
    static let destructive     = Color(hex: "FF453A") // fills / dots
    static let destructiveText = Color(hex: "FF6961") // text / icons

    // MARK: - Category accents
    static let categoryTalk     = Color(hex: "E9B44C") // gold
    static let categoryTraining = Color(hex: "E97C5E") // coral
    static let categoryPanel    = Color(hex: "C9A0DC") // lavender
    static let categoryNote     = label.opacity(0.45)  // neutral "Note" / "Other"

    // MARK: - Generic chip (filters / language)
    static let chipFill   = Color.white.opacity(0.07)
    static let chipStroke = Color.white.opacity(0.09)

    // MARK: - Component tokens
    static let cardBackground = surface
    static let cardBorder     = separator
    static let chipBackground = chipFill
    static let chipBorder     = chipStroke

    // MARK: - Status (kept for existing call sites)
    static let success500 = Color(hex: "5FE3BE")
    static let warning500 = accent
    static let error500   = destructive

    /// Apple's label white, exposed for opacity-derived text/icon tints.
    static let labelWhite = label

    // MARK: - Back-compat neutral scale
    // The prior grayscale scale is remapped onto the new design roles so existing
    // screen code (which references neutralX for text, dividers and surfaces)
    // adopts the charcoal/amber system automatically.
    static let neutral0   = textPrimary          // bright text / on-dark
    static let neutral100 = background            // screen background
    static let neutral200 = surface               // card / row surface
    static let neutral300 = separator             // dividers
    static let neutral400 = label.opacity(0.30)
    static let neutral500 = textTertiary          // muted metadata
    static let neutral600 = textSecondary         // secondary text / labels
    static let neutral700 = textBright            // chip / control text
    static let neutral800 = textPrimary           // primary text
    static let neutral900 = textPrimary           // strongest text
}

/// `Color.echo*` token accessors, sourced from `AppColors` so there's a single
/// source of truth. Opacity-derived tints (e.g. `.recapLabel.opacity(0.45)`) are
/// applied at the call site.
extension Color {
    static let recapSurface        = AppColors.surface        // #212328
    static let recapSurfacePressed = AppColors.composerField  // #282B31
    static let recapAccent         = AppColors.accent         // #F0A24A
    static let recapTextPrimary    = AppColors.textPrimary    // #F5F5F7
    static let recapLabel          = AppColors.labelWhite     // #EBEBF5 (use with .opacity)
}
