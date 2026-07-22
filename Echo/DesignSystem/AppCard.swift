import SwiftUI

/// Bordered container used for list rows — mirrors .card in the web app.
struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
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
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }
}
