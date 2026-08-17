import SwiftUI

/// The two pill geometries, defined once.
///
/// Every style below composes one of these instead of spelling out its own type,
/// height and padding, so a primary and a secondary of the same size are
/// guaranteed to match and can differ only in fill and stroke. They previously
/// each carried their own numbers and had drifted apart — the small pair sat at
/// 14pt/36pt against 16pt/40pt, which is visible the moment two of them sit side
/// by side.
private enum PillSize {
    /// Stretches to the width it's given — forms, sheets, full-width actions.
    case regular
    /// Hugs its label — action rows where several buttons sit side by side.
    case small

    var minHeight: CGFloat { self == .regular ? 44 : 40 }
    var verticalPadding: CGFloat { self == .regular ? Spacing.s2 : 0 }
    var horizontalPadding: CGFloat { self == .regular ? Spacing.s6 : Spacing.s5 }
    var fillsWidth: Bool { self == .regular }
}

private struct PillBox: ViewModifier {
    let size: PillSize

    func body(content: Content) -> some View {
        content
            // Both sizes share one type style: a small button is a tighter box,
            // not a quieter label.
            .appTextStyle(.bodyMedium)
            .frame(maxWidth: size.fillsWidth ? .infinity : nil, minHeight: size.minHeight)
            .padding(.vertical, size.verticalPadding)
            .padding(.horizontal, size.horizontalPadding)
    }
}

private extension View {
    func pillBox(_ size: PillSize) -> some View { modifier(PillBox(size: size)) }
}

/// Filled sapphire pill — the primary, high-emphasis action.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pillBox(.regular)
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
            .pillBox(.regular)
            .foregroundStyle(AppColors.textPrimary)
            .background(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Outlined destructive pill — delete / sign-out style actions.
struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pillBox(.regular)
            .foregroundStyle(AppColors.destructiveText)
            .background(Capsule().strokeBorder(AppColors.destructiveDeep, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Compact filled sapphire pill.
struct SmallPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pillBox(.small)
            .background(AppColors.accent)
            .foregroundStyle(AppColors.accentText)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Compact outlined pill.
struct SmallSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pillBox(.small)
            .foregroundStyle(AppColors.textPrimary)
            .background(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Compact outlined destructive pill — the in-tab delete actions.
///
/// Without this, a destructive action sitting next to a small pill had to either
/// borrow `.appSecondarySmall` (which paints it neutral, hiding what it does) or
/// fall back to a bare tinted label, leaving two different button shapes in one
/// row.
struct SmallDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pillBox(.small)
            .foregroundStyle(AppColors.destructiveText)
            .background(Capsule().strokeBorder(AppColors.destructiveDeep, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
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

/// A row for an overlay `Menu`, guaranteeing the icon and label share one color.
///
/// In a SwiftUI menu the title is drawn in the system label color (or red for a
/// `.destructive` role) while the icon follows the ambient `tint` — and the app
/// pins an amber accent tint on the navigation stack, which otherwise leaves menu
/// icons amber against white labels. Pinning the tint to the label color here
/// keeps every menu item consistent by default: normal items are label-on-label,
/// destructive items are red-on-red.
struct AppMenuButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
        .tint(role == .destructive ? AppColors.destructive : AppColors.textPrimary)
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

extension ButtonStyle where Self == SmallDestructiveButtonStyle {
    static var appDestructiveSmall: SmallDestructiveButtonStyle { SmallDestructiveButtonStyle() }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var appIcon: IconButtonStyle { IconButtonStyle() }
}
