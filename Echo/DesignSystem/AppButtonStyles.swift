import SwiftUI

/// Filled, high-emphasis action — 1:1 port of .btn.btn--primary in components.css.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appTextStyle(.body)
            .frame(maxWidth: .infinity, minHeight: 44) // HIG touch target; web's 4px padding alone is too thin for iOS
            .padding(.vertical, Spacing.s1)
            .padding(.horizontal, Spacing.s6)
            .background(AppColors.neutral900)
            .foregroundStyle(AppColors.neutral0)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Outlined, low-emphasis action — 1:1 port of .btn.btn--ghost in components.css.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appTextStyle(.body)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, Spacing.s1)
            .padding(.horizontal, Spacing.s6)
            .foregroundStyle(AppColors.neutral900)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(AppColors.neutral900, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Compact filled button — port of .btn--sm.
struct SmallPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appTextStyle(.small)
            .frame(minHeight: 36)
            .padding(.vertical, Spacing.s1)
            .padding(.horizontal, Spacing.s4)
            .background(AppColors.neutral900)
            .foregroundStyle(AppColors.neutral0)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Icon-only tap target — port of .btn-icon (40x40, transparent, hover -> neutral200).
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppColors.neutral600)
            .frame(width: Spacing.s10, height: Spacing.s10)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(configuration.isPressed ? AppColors.neutral200 : Color.clear)
            )
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var appPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var appSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == SmallPrimaryButtonStyle {
    static var appPrimarySmall: SmallPrimaryButtonStyle { SmallPrimaryButtonStyle() }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var appIcon: IconButtonStyle { IconButtonStyle() }
}
