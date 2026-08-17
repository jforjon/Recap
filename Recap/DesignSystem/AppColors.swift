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
/// sapphire accent, and Apple's slightly-cool label white for text. Dark-mode
/// only (the app pins `.preferredColorScheme(.dark)`), so tokens are single
/// values rather than light/dark pairs.
enum AppColors {
    /// Apple's label white (rgba 235,235,245) — text opacities are taken from this.
    private static let label = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255)

    // MARK: - Blue ramp (palette)
    //
    // One hue (~267°) on an even lightness ladder, with chroma peaking at 600.
    // The four blues the app actually ships anchor 0/300/600/900; the rest are
    // interpolated between them in OKLCH. This tier carries no meaning — it is
    // named by position so it can be repositioned without renaming. Screens
    // should use the semantic accents below, not these.
    static let blue0   = Color(hex: "EAF0FF")
    static let blue100 = Color(hex: "C6D6FD")
    static let blue200 = Color(hex: "A2BBFA")
    static let blue300 = Color(hex: "7FA0F5")
    static let blue400 = Color(hex: "638AEC")
    static let blue500 = Color(hex: "4773E2")
    static let blue600 = Color(hex: "2A5BD7")
    static let blue700 = Color(hex: "2E4A9E")
    static let blue800 = Color(hex: "2B3968")
    static let blue900 = Color(hex: "242835")

    // MARK: - Brand / accent (sapphire)
    //
    // The accent has two roles and they are not interchangeable. `accent` is a
    // *fill* only, and only ever behind `accentText`; against the charcoal
    // background it doesn't carry enough contrast to be read as text or as an
    // icon. Anywhere the accent is the foreground — labels, glyphs, tints,
    // carets, the waveform — use `accentGraphic`.
    static let accent        = blue600  // fill: primary buttons, selected chip
    static let accentText    = blue0    // label/icon sitting on that fill
    static let accentGraphic = blue300  // accent as foreground on dark

    /// The soft accent wash behind selected rows and icon badges. Opaque rather
    /// than an alpha overlay: it is `blue300` at 12% pre-flattened over
    /// `background`, which is what both call sites sit on.
    static let accentTint = blue900

    // MARK: - Surfaces (charcoal ramp — 4 tones)
    static let backgroundDeep  = Color(hex: "0F1012") // canvas behind everything (iPad / edges)
    static let background      = Color(hex: "17181B") // screen background, bars & side panes
    static let surface         = Color(hex: "212328") // cards & inputs
    static let surfaceElevated = Color(hex: "32353B") // menus / dialogs; also pressed rows

    // MARK: - Hairlines (pure white, low alpha)
    static let separator       = Color.white.opacity(0.06)
    static let separatorStrong = Color.white.opacity(0.10)

    // MARK: - Text
    static let textPrimary   = Color(hex: "F5F5F7")
    static let textBright    = Color(hex: "EDEDEF")
    static let textSecondary = label.opacity(0.60)
    static let textTertiary  = label.opacity(0.45)
    static let textFaint     = label.opacity(0.35)

    // MARK: - Destructive (3 reds)
    static let destructiveText = Color(hex: "FF6961") // light — text / icons
    static let destructive     = Color(hex: "FF453A") // base — fills / dots / tints
    static let destructiveDeep = Color(hex: "6F2F2E") // dark — borders / tint bg (opaque)

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
    /// The app's former brand amber, now purely semantic — a warning must not
    /// read as the accent, and with the accent gone blue it no longer can.
    static let warning500 = Color(hex: "F0A24A")
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
    static let recapSurfacePressed = AppColors.surfaceElevated // #32353B (pressed row highlight)
    /// The *foreground* accent — every `recapAccent` call site is a glyph, a label
    /// or a tint, never a fill behind text.
    static let recapAccent         = AppColors.accentGraphic  // #7FA0F5
    static let recapTextPrimary    = AppColors.textPrimary    // #F5F5F7
    static let recapLabel          = AppColors.labelWhite     // #EBEBF5 (use with .opacity)
}
