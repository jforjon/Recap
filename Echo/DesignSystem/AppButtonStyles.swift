import SwiftUI

/// Filled, high-emphasis action — mirrors .btn--primary in the web app.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md + 2)
            .background(Color.primary)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Outlined, low-emphasis action — mirrors .btn--ghost in the web app.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md + 2)
            .foregroundStyle(Color.primary)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(AppColor.borderStrong, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var appPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var appSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
