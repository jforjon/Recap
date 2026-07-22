import SwiftUI

/// Bordered container used for list rows — 1:1 port of .card in components.css.
struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            content
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(AppColors.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

/// Small rounded label — 1:1 port of the .chip category pill in NoteCard.module.css.
struct AppChip: View {
    let text: String
    var dotColor: Color = AppColors.neutral600

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(text)
                .appTextStyle(.mono)
                .foregroundStyle(AppColors.neutral700)
        }
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, 2)
        .background(AppColors.chipBackground)
        .overlay(Capsule().strokeBorder(AppColors.chipBorder, lineWidth: 1))
        .clipShape(Capsule())
    }
}
