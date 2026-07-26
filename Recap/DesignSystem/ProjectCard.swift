import SwiftUI

// MARK: - Pressed state plumbing

/// Lets `ProjectCard` own its container (so it renders standalone in previews and
/// lists) while still reacting to press state supplied by `ProjectCardButtonStyle`.
private struct ProjectCardPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var projectCardPressed: Bool {
        get { self[ProjectCardPressedKey.self] }
        set { self[ProjectCardPressedKey.self] = newValue }
    }
}

/// Button style for interactive project rows: injects the pressed state that
/// `ProjectCard` reads to swap its container fill.
///
///     Button { select(project) } label: {
///         ProjectCard(name: p.name, recordingCount: r, noteCount: n, isSelected: p.id == selectedID)
///     }
///     .buttonStyle(.projectCard)
struct ProjectCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.projectCardPressed, configuration.isPressed)
    }
}

extension ButtonStyle where Self == ProjectCardButtonStyle {
    static var projectCard: ProjectCardButtonStyle { ProjectCardButtonStyle() }
}

// MARK: - Project card

/// Tappable project row: folder tile, name, and a monospaced counts line.
/// Used in the Projects list and the iPad sidebar. Dark-mode only.
struct ProjectCard: View {
    let name: String
    let recordingCount: Int
    let noteCount: Int
    var isSelected: Bool = false

    @Environment(\.projectCardPressed) private var isPressed

    private let tileSize: CGFloat = 42
    private let containerRadius: CGFloat = 20

    var body: some View {
        HStack(spacing: 12) {
            iconTile
            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(.system(.callout, design: .default).weight(.semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.recapTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(countsText)
                    .font(.system(.caption, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.recapLabel.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.recapLabel.opacity(0.30))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isPressed ? Color.recapSurfacePressed : Color.recapSurface)
        .overlay(
            RoundedRectangle(cornerRadius: containerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: containerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: containerRadius, style: .continuous))
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isSelected ? Color.recapAccent.opacity(0.14) : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.recapAccent.opacity(0.28) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .frame(width: tileSize, height: tileSize)
            .overlay(
                Image(systemName: "folder")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? Color.recapAccent : Color.recapLabel.opacity(0.60))
            )
    }

    private var countsText: String {
        let r = "\(recordingCount) \(recordingCount == 1 ? "RECORDING" : "RECORDINGS")"
        let n = "\(noteCount) \(noteCount == 1 ? "NOTE" : "NOTES")"
        return "\(r) · \(n)"
    }
}

// MARK: - New project (creation) row

/// Dashed "New project" row matching `ProjectCard`'s geometry.
struct NewProjectCard: View {
    private let tileSize: CGFloat = 42
    private let containerRadius: CGFloat = 20

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4]))
                .frame(width: tileSize, height: tileSize)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.recapLabel.opacity(0.45))
                )

            Text("New project")
                .font(.system(.callout, design: .default).weight(.regular))
                .foregroundStyle(Color.recapLabel.opacity(0.45))

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: containerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
        .clipShape(RoundedRectangle(cornerRadius: containerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: containerRadius, style: .continuous))
    }
}

#Preview("Project cards") {
    VStack(spacing: 10) {
        ProjectCard(name: "Onboarding research", recordingCount: 3, noteCount: 7, isSelected: true)
        ProjectCard(name: "Summit 2026 — a very long project name that truncates", recordingCount: 1, noteCount: 1)
        NewProjectCard()
    }
    .padding(16)
    .frame(maxWidth: 420)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(hex: "17181B"))
    .preferredColorScheme(.dark)
}
