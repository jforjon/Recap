import SwiftUI

/// A horizontal pill-chip navigation bar used to switch between the "big parts"
/// of a detail screen (e.g. a recording's Infos/Transcript/Notes/Summary, or a
/// project's Recordings/Notes/Summary).
///
/// Draws `ChipPill`, the same pill `FilterChip` uses — the two differ in what
/// they do, not how they look. What this adds is the horizontal scroll (four
/// tabs do not fit an iPhone) and the animated selection change.
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
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { selection = tab }
        } label: {
            ChipPill(title: title(tab), isSelected: tab == selection)
        }
        .buttonStyle(.plain)
    }
}
