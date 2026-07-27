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

/// Lightweight Markdown renderer for AI summaries: headings (`#`/`##`/`###`),
/// bullet lists (`-` / `*`) and paragraphs, with inline `**bold**` / `*italic*`.
/// Keeps the app's DM Sans type styles (inline emphasis renders as bold/italic of
/// the same font rather than swapping to the system font).
struct MarkdownText: View {
    let markdown: String

    private struct Line: Identifiable {
        let id = UUID()
        let kind: Kind
        let text: String
        enum Kind { case h1, h2, h3, bullet, paragraph }
    }

    private var lines: [Line] {
        markdown.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if line.hasPrefix("### ") { return Line(kind: .h3, text: String(line.dropFirst(4))) }
            if line.hasPrefix("## ")  { return Line(kind: .h2, text: String(line.dropFirst(3))) }
            if line.hasPrefix("# ")   { return Line(kind: .h1, text: String(line.dropFirst(2))) }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                return Line(kind: .bullet, text: String(line.dropFirst(2)))
            }
            return Line(kind: .paragraph, text: line)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            ForEach(lines) { line in
                switch line.kind {
                case .h1:
                    Text(inline(line.text)).font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary).padding(.top, Spacing.s1)
                case .h2:
                    Text(inline(line.text)).font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary).padding(.top, Spacing.s1)
                case .h3:
                    Text(inline(line.text)).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                        Text("•").foregroundStyle(AppColors.accent)
                        Text(inline(line.text)).appTextStyle(.body)
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .paragraph:
                    Text(inline(line.text)).appTextStyle(.body)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Parses inline `**bold**` / `*italic*` into presentation intents (not concrete
    /// fonts), so the surrounding `.appTextStyle` font is preserved.
    private func inline(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }
}
