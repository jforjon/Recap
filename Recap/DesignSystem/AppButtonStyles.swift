import SwiftUI

/// Filled amber pill — the primary, high-emphasis action.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appTextStyle(.bodyMedium)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, Spacing.s2)
            .padding(.horizontal, Spacing.s6)
            .background(AppColors.accent)
            .foregroundStyle(AppColors.accentText)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Outlined pill — low-emphasis secondary action.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appTextStyle(.body)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, Spacing.s2)
            .padding(.horizontal, Spacing.s6)
            .foregroundStyle(AppColors.textPrimary)
            .background(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Outlined destructive pill — delete / sign-out style actions.
struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appTextStyle(.bodyMedium)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, Spacing.s2)
            .padding(.horizontal, Spacing.s6)
            .foregroundStyle(AppColors.destructiveText)
            .background(Capsule().strokeBorder(AppColors.destructive.opacity(0.35), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Compact outlined pill that hugs its label width.
struct SmallSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appTextStyle(.bodyMedium)
            .frame(minHeight: 40)
            .padding(.horizontal, Spacing.s6)
            .foregroundStyle(AppColors.textPrimary)
            .background(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Compact filled amber pill.
struct SmallPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appTextStyle(.small)
            .frame(minHeight: 36)
            .padding(.vertical, Spacing.s1)
            .padding(.horizontal, Spacing.s4)
            .background(AppColors.accent)
            .foregroundStyle(AppColors.accentText)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Round, icon-only tap target with a subtle glass fill.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppColors.textBright.opacity(0.85))
            .frame(width: 44, height: 44)
            .background(
                Circle().fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.07))
            )
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var appPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var appSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    static var appDestructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}

extension ButtonStyle where Self == SmallPrimaryButtonStyle {
    static var appPrimarySmall: SmallPrimaryButtonStyle { SmallPrimaryButtonStyle() }
}

extension ButtonStyle where Self == SmallSecondaryButtonStyle {
    static var appSecondarySmall: SmallSecondaryButtonStyle { SmallSecondaryButtonStyle() }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var appIcon: IconButtonStyle { IconButtonStyle() }
}
