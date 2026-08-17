import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

/// A Markdown file the share sheet can hand to Files, Mail, Notion, Obsidian —
/// anything that accepts a document. Exported as plain text so every target
/// accepts it, with a `.md` filename so the ones that render Markdown do.
struct MarkdownFile: Transferable {
    let text: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName { $0.filename }
    }
}

/// The Export tab shared by a recording and a project.
///
/// The caller owns the document: it rebuilds the Markdown from `options`
/// whenever they change, so this view stays a dumb renderer and neither detail
/// screen needs its own copy of the toggles or the share plumbing.
struct ExportTabView: View {
    @Binding var options: MarkdownExport.Options
    let filename: String
    let document: String

    /// Sections with nothing behind them are disabled rather than hidden, so the
    /// toggle list doesn't reshuffle as a recording gains a summary.
    let hasSummary: Bool
    let hasNotes: Bool
    let hasTranscript: Bool
    /// Only recordings made after timing capture shipped can be timestamped.
    let hasTimings: Bool

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("INCLUDE")
                .appTextStyle(.label)
                .foregroundStyle(AppColors.neutral600)

            VStack(spacing: 0) {
                toggle("Summary", isOn: $options.includeSummary, enabled: hasSummary)
                Divider().overlay(AppColors.separator)
                toggle("My notes", isOn: $options.includeNotes, enabled: hasNotes)
                Divider().overlay(AppColors.separator)
                toggle("Transcript", isOn: $options.includeTranscript, enabled: hasTranscript)
                // Nested under Transcript in meaning, so it goes away entirely
                // when there's no transcript to stamp rather than sitting there
                // disabled for two different reasons at once.
                if hasTranscript {
                    Divider().overlay(AppColors.separator)
                    toggle("Timestamps", isOn: $options.includeTimestamps,
                           enabled: hasTimings && options.includeTranscript)
                }
            }
            .padding(.horizontal, Spacing.md)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            if document.isEmpty {
                EmptyStateView(
                    icon: "square.and.arrow.up",
                    title: "Nothing selected",
                    message: "Turn on at least one section above to build an export."
                )
            } else {
                HStack(spacing: Spacing.s3) {
                    ShareLink(
                        item: MarkdownFile(text: document, filename: filename),
                        preview: SharePreview(filename)
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.appPrimarySmall)

                    Button {
                        UIPasteboard.general.string = document
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.appSecondarySmall)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle(_ title: String, isOn: Binding<Bool>, enabled: Bool) -> some View {
        // A section with nothing behind it reads as off, whatever the stored
        // preference is — an "on" switch next to "none yet" looks like a bug.
        // The preference itself is left alone, so the switch comes back on by
        // itself once the recording gains a summary or a note.
        let display = Binding(
            get: { enabled && isOn.wrappedValue },
            set: { isOn.wrappedValue = $0 }
        )
        return Toggle(isOn: display) {
            Text(enabled ? title : "\(title) — none yet")
                .appTextStyle(.body)
                .foregroundStyle(enabled ? AppColors.textPrimary : AppColors.neutral500)
        }
        .disabled(!enabled)
        .tint(AppColors.accentGraphic)
        .padding(.vertical, Spacing.s3)
    }
}
