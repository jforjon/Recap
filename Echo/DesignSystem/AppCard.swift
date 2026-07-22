import SwiftUI

/// Bordered container used for list rows — mirrors .card in the web app.
struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            content
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(AppColor.cardBackground)
        )
    }
}

/// Small rounded label — mirrors the .chip category pill in the web app.
struct AppChip: View {
    let text: String
    var dotColor: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption.monospaced())
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 2)
        .background(
            Capsule().strokeBorder(AppColor.border, lineWidth: 1)
        )
    }
}
