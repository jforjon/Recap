import SwiftUI

/// Custom font accessors — bundled DM Sans / Roboto Mono statics registered via UIAppFonts.
enum AppFont {
    static func sans(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "DMSans-Medium" : "DMSans-Regular", size: size)
    }

    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "RobotoMono-Medium" : "RobotoMono-Regular", size: size)
    }
}

/// A named text style bundling font + tracking, mirroring the .text-* classes
/// in globals.css (each pairs a font-size/line-height/letter-spacing/weight).
struct AppTextStyle {
    let font: Font
    let tracking: CGFloat

    static let display = AppTextStyle(font: AppFont.sans(32, medium: true), tracking: 32 * -0.04)
    static let title    = AppTextStyle(font: AppFont.sans(24, medium: true), tracking: 24 * -0.03)
    static let heading  = AppTextStyle(font: AppFont.sans(20, medium: true), tracking: 20 * -0.02)
    static let body     = AppTextStyle(font: AppFont.sans(16), tracking: 16 * -0.01)
    static let bodyMedium = AppTextStyle(font: AppFont.sans(16, medium: true), tracking: 16 * -0.01)
    static let small    = AppTextStyle(font: AppFont.sans(14), tracking: 14 * -0.005)
    /// Uppercase label — apply `.textCase(.uppercase)` alongside this at the call site.
    static let label    = AppTextStyle(font: AppFont.sans(12, medium: true), tracking: 12 * 0.07)
    static let mono     = AppTextStyle(font: AppFont.mono(12), tracking: 0)
    static let monoMedium = AppTextStyle(font: AppFont.mono(12, medium: true), tracking: 0)
}

extension View {
    func appTextStyle(_ style: AppTextStyle) -> some View {
        self.font(style.font).tracking(style.tracking)
    }
}
