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

/// The selectable pill, defined once.
///
/// Filtering a list and navigating between sections are different jobs, but the
/// app has always drawn them as the same pill. The look therefore lives here
/// rather than being spelled out in both `FilterChip` and `SegmentedChipBar`,
/// where it had already drifted apart — 14/7 padding against 12/8, which is the
/// kind of difference nobody notices until the two sit on one screen.
struct ChipPill: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .appTextStyle(.smallMedium)
            .foregroundStyle(isSelected ? AppColors.accentText : AppColors.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isSelected ? AppColors.accent : AppColors.chipFill)
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.clear : AppColors.chipStroke, lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

/// Selectable filter pill (e.g. All / Projects / Recordings) — narrows what a
/// list shows. For switching between sections of a screen use
/// `SegmentedChipBar`, which draws the same pill.
struct FilterChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipPill(title: title, isSelected: isActive)
                .tapTargetPadding()
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
