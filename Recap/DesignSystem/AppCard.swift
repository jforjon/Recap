import SwiftUI

/// Soft-charcoal surface used for list rows and grouped panels.
struct AppCard<Content: View>: View {
    var padding: CGFloat = Spacing.s3 + 1 // 13, matches the design's row padding
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(AppColors.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// Selectable filter pill (e.g. All / Projects / Recordings). Active = amber fill.
struct FilterChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? AppColors.accentText : AppColors.labelWhite.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isActive ? AppColors.accent : AppColors.chipFill)
                .overlay(
                    Capsule().strokeBorder(isActive ? Color.clear : AppColors.chipStroke, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Category / status pill. The fill, border and text are tinted from `dotColor`
/// (translucent fill + border, solid dot), matching the design's category chips.
struct AppChip: View {
    let text: String
    var dotColor: Color = AppColors.categoryNote

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(text)
                .appTextStyle(.mono)
                .foregroundStyle(dotColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(dotColor.opacity(0.12))
        .overlay(Capsule().strokeBorder(dotColor.opacity(0.25), lineWidth: 1))
        .clipShape(Capsule())
    }
}
