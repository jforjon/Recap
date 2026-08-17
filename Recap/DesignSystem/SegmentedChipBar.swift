import SwiftUI

/// A horizontal pill-chip navigation bar used to switch between the "big parts"
/// of a detail screen (e.g. a recording's Infos/Transcript/Notes/Summary, or a
/// project's Recordings/Notes/Summary). The selected chip fills with the amber
/// accent; the rest use the neutral chip tokens.
struct SegmentedChipBar<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    let title: (Tab) -> String
    @Binding var selection: Tab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(tabs) { tab in
                    chip(tab)
                }
            }
        }
    }

    private func chip(_ tab: Tab) -> some View {
        let selected = tab == selection
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selection = tab }
        } label: {
            Text(title(tab))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? AppColors.accentText : AppColors.textSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    Capsule().fill(selected ? AppColors.accent : AppColors.chipFill)
                )
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Color.clear : AppColors.chipStroke,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}
