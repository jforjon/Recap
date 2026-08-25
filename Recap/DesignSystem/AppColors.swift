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

/// One semantic status family: three shades of a single hue, named by the job
/// each does rather than by position on a ladder. Unlike `neutral*` / `blue*`
/// these do not interpolate — there is no meaningful value between two of them.
struct StatusColors {
    /// Foreground on dark — text, icons, glyphs.
    let light: Color
    /// The signature fill — dots, tints, filled controls.
    let `default`: Color
    /// Opaque border or tint background, quiet against charcoal.
    let dark: Color
}

/// Design tokens for the "recap — iOS dark UI" system: soft-charcoal surfaces, a
/// sapphire accent, and a cool-neutral text ramp. Dark-mode only (the app pins
/// `.preferredColorScheme(.dark)`), so tokens are single values rather than
/// light/dark pairs.
///
/// Two tiers, and they are not interchangeable:
///
/// * **Palette** (`neutral*`, `blue*`) — position on a lightness ladder, nothing
///   more. Named by number so a value can be repositioned without renaming.
///   Screens must not reference these directly.
/// * **Roles** (`background`, `textSecondary`, `accent`, …) — what a colour is
///   *for*. Every role is an alias onto a palette step. Screens use these.
///
/// The one deliberate exception is the hairlines, which are white at low alpha
/// rather than ramp steps: a hairline has to read against whatever it is drawn
/// on, and no single opaque value does that. `separator` composites to `#252629`
/// on `background`, `#2E3035` on `surface` and `#3E4147` on `surfaceElevated`.
enum AppColors {

    // MARK: - Neutral ramp (palette)
    //
    // One cool-grey hue on a ladder from near-white to the deepest charcoal,
    // eleven steps on round hundreds. Every step is load-bearing: each one has
    // a role pointing at it, and each value is a tone the app actually paints
    // with. The ramp was built by anchoring those shipping tones and filling
    // the void between them in OKLCH — before it existed nothing opaque sat
    // between L 33 and L 94, and every mid-grey was an opacity over Apple's
    // label white.
    //
    // The lightness spacing is deliberately uneven, in three places for three
    // reasons. 0 → 100 is only 2.4 because primary and bright text genuinely
    // are near-identical. 200 → 300 is a double-width 17.7: a step sat there
    // until nothing needed it, and dropping it was what let the dark end land
    // on round hundreds instead of a 950 half-step. And the bottom tightens to
    // 7.2, 4.7, 3.6 because dark UI needs finer discrimination between adjacent
    // surfaces than an accent hue does — which is also why the blue ramp,
    // spanning 68 points of lightness against this one's 80, stops at 900.
    //
    // A grey around L 77 goes back into the 200 → 300 gap if one is ever needed.
    static let neutral0    = Color(hex: "F5F5F7") // L 97.1
    static let neutral100  = Color(hex: "EDEDEF") // L 94.7
    static let neutral200  = Color(hex: "D0D0D3") // L 85.9
    static let neutral300  = Color(hex: "98989D") // L 68.2
    static let neutral400  = Color(hex: "7D7E83") // L 59.3
    static let neutral500  = Color(hex: "63646A") // L 50.5
    static let neutral600  = Color(hex: "4A4C52") // L 41.6
    static let neutral700  = Color(hex: "32353B") // L 32.8
    static let neutral800  = Color(hex: "212328") // L 25.6
    static let neutral900  = Color(hex: "17181B") // L 20.9
    static let neutral1000 = Color(hex: "0F1012") // L 17.3

    // MARK: - Blue ramp (palette)
    //
    // One hue (~267°) on an even lightness ladder, with chroma peaking at 600.
    // The four blues the app actually ships anchor 0/300/600/900; the rest are
    // interpolated between them in OKLCH.
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

    // MARK: - Surfaces
    static let backgroundDeep  = neutral1000 // canvas behind everything (iPad / edges)
    static let background      = neutral900  // screen background, bars & side panes
    static let surface         = neutral800  // cards & inputs
    static let surfaceElevated = neutral700  // menus / dialogs; also pressed rows

    // MARK: - Hairlines (pure white, low alpha — see the type comment)
    static let separator       = Color.white.opacity(0.06)
    static let separatorStrong = Color.white.opacity(0.10)

    // MARK: - Text
    static let textPrimary   = neutral0
    static let textBright    = neutral100
    static let textMuted     = neutral200
    static let textSecondary = neutral300
    static let textTertiary  = neutral400
    static let textFaint     = neutral500
    static let textDisabled  = neutral600

    // MARK: - Category accents
    static let categoryTalk     = Color(hex: "E9B44C") // gold
    static let categoryTraining = Color(hex: "E97C5E") // coral
    static let categoryPanel    = Color(hex: "C9A0DC") // lavender
    static let categoryNote     = neutral400           // neutral "Note" / "Other"

    // MARK: - Generic chip (filters / language)
    static let chipFill   = Color.white.opacity(0.07)
    static let chipStroke = Color.white.opacity(0.09)

    // MARK: - Component tokens
    static let cardBackground = surface
    static let cardBorder     = separator
    static let chipBackground = chipFill
    static let chipBorder     = chipStroke

    // MARK: - Status (semantic families)
    //
    // Four hues, three shades each, split by role rather than by position —
    // these are not a ramp and don't interpolate. The split is the one the
    // destructive reds already used, generalised:
    //
    //   light    foreground on dark — text, icons, glyphs
    //   default  the signature fill — dots, tints, filled controls
    //   dark     opaque border / tint background, quiet on charcoal
    //
    // The families sit at different lightnesses because their hues peak at
    // different lightnesses: red tops out at L 63, amber at L 77. Forcing them
    // onto one lightness would mean either a washed red or a mustard warning —
    // the gamut is the constraint, not a preference.
    //
    // Green and blue are the exception, and deliberately so. Both peak far too
    // light to use there (green at L 89, blue-cyan at L 80), which reads as
    // highlighter rather than status, so `success` and `info` are capped at
    // L 66 and L 64 and take a richer, deeper colour instead of a brighter one.
    //
    // `light` and `dark` are derived from each `default` by the transform the
    // shipping destructive trio already described (L +4.4 / chroma ×0.83, and
    // L 39.4 absolute / chroma ×0.41), clamped into sRGB. The destructive
    // values below are the originals, kept exactly.
    static let destructive = StatusColors(
        light:   Color(hex: "FF6961"),
        default: Color(hex: "FF453A"),
        dark:    Color(hex: "6F2F2E")
    )
    /// The app's former brand amber, now purely semantic — a warning must not
    /// read as the accent, and with the accent gone blue it no longer can.
    static let warning = StatusColors(
        light:   Color(hex: "F6B470"),
        default: Color(hex: "F0A24A"),
        dark:    Color(hex: "5B4023")
    )
    static let success = StatusColors(
        light:   Color(hex: "57B770"),
        default: Color(hex: "28AD57"),
        dark:    Color(hex: "285032")
    )
    /// Ocean blue at H 235. Info wants to be blue and blue is already the brand,
    /// so the separation from the sapphire accent is carried by lightness and
    /// chroma as much as by the 32° of hue: `info.default` is 12 L points
    /// lighter and far less chromatic than `accent`. The pair to watch is
    /// `info.light` against `accentGraphic` — both mid-light blues, 32° apart.
    static let info = StatusColors(
        light:   Color(hex: "51A4D0"),
        default: Color(hex: "2597CD"),
        dark:    Color(hex: "294B5E")
    )
}

/// `Color.recap*` token accessors, sourced from `AppColors` so there's a single
/// source of truth.
extension Color {
    static let recapSurface        = AppColors.surface         // neutral800
    static let recapSurfacePressed = AppColors.surfaceElevated // neutral700 (pressed row highlight)
    /// The *foreground* accent — every `recapAccent` call site is a glyph, a label
    /// or a tint, never a fill behind text.
    static let recapAccent         = AppColors.accentGraphic   // blue300
    static let recapTextPrimary    = AppColors.textPrimary     // neutral0
}
