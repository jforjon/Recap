import Foundation

/// Builds a Markdown document out of a recording or a whole project.
///
/// Markdown because it is the one format that pastes usefully into everything
/// the strong use cases need — Notion, Obsidian, Bear, Craft, a GitHub issue,
/// an email — while staying readable as plain text if it lands somewhere that
/// doesn't render it.
enum MarkdownExport {

    /// Which sections to include. Transcripts dominate the output by length, so
    /// being able to drop them is the difference between a shareable write-up and
    /// a wall of text.
    struct Options: Equatable {
        var includeSummary = true
        var includeNotes = true
        var includeTranscript = false
        /// Marks each paragraph with its position in the recording, so an
        /// exported transcript can be read alongside the audio — "what did she
        /// say about pricing twenty minutes in" becomes answerable.
        var includeTimestamps = true
    }

    // MARK: - A single recording

    static func document(
        for note: Note,
        personalNotes: [PersonalNote],
        options: Options
    ) -> String {
        var out = ["# \(note.title)"]

        var meta = ["- **Date:** \(formatShortDate(note.createdAt))"]
        if let category = note.category {
            meta.append("- **Category:** \(category.displayText)")
        }
        if let event = trimmed(note.eventName) {
            meta.append("- **Event:** \(event)")
        }
        if let speaker = trimmed(note.speakerContext) {
            meta.append("- **Speaker & context:** \(speaker)")
        }
        out.append(meta.joined(separator: "\n"))

        if options.includeSummary, let summary = trimmed(note.summary) {
            out.append("## Summary\n\n\(summary)")
        }
        if options.includeNotes, let notes = bulletedNotes(personalNotes) {
            out.append("## My notes\n\n\(notes)")
        }
        if options.includeTranscript, let transcript = transcriptBody(note, options: options) {
            out.append("## Transcript\n\n\(transcript)")
        }

        return out.joined(separator: "\n\n")
    }

    /// The transcript as readable paragraphs rather than one unbroken block.
    ///
    /// Prefers the real pause-based breaks from the segment timings, and adds a
    /// timecode to each. Falls back to sentence grouping for recordings made
    /// before timings were captured — those can't be timestamped, but they can
    /// at least be paragraphed.
    private static func transcriptBody(_ note: Note, options: Options) -> String? {
        let segments = note.transcriptSegments ?? []

        if !segments.isEmpty {
            return segments.paragraphs().map { paragraph in
                let body = paragraph.map(\.text).joined(separator: " ")
                guard options.includeTimestamps, let start = paragraph.first?.start else {
                    return body
                }
                return "**[\(formatTimecode(start))]** \(body)"
            }.joined(separator: "\n\n")
        }

        guard let transcript = trimmed(note.transcript) else { return nil }
        let paragraphs = TranscriptFormatting.paragraphs(from: transcript)
        return paragraphs.isEmpty ? transcript : paragraphs.joined(separator: "\n\n")
    }

    // MARK: - A whole project

    static func document(
        for project: Project,
        recordings: [Note],
        projectNotes: [PersonalNote],
        notesByRecording: [UUID: [PersonalNote]],
        options: Options
    ) -> String {
        var out = ["# \(project.name)"]

        let count = recordings.count
        out.append("_\(count) recording\(count == 1 ? "" : "s") · exported \(formatShortDate(isoNow()))_")

        if options.includeSummary, let summary = trimmed(project.notes) {
            out.append("## Project summary\n\n\(summary)")
        }
        if options.includeNotes, let notes = bulletedNotes(projectNotes) {
            out.append("## My notes\n\n\(notes)")
        }

        if !recordings.isEmpty {
            out.append("---\n\n## Recordings")

            for (index, note) in recordings.enumerated() {
                var block = ["### \(index + 1). \(note.title)"]

                var meta = [formatShortDate(note.createdAt)]
                if let category = note.category { meta.append(category.displayText) }
                if let speaker = trimmed(note.speakerContext) { meta.append(speaker) }
                block.append("_\(meta.joined(separator: " · "))_")

                if options.includeSummary, let summary = trimmed(note.summary) {
                    block.append("**Summary**\n\n\(summary)")
                }
                if options.includeNotes, let notes = bulletedNotes(notesByRecording[note.id] ?? []) {
                    block.append("**My notes**\n\n\(notes)")
                }
                if options.includeTranscript, let transcript = transcriptBody(note, options: options) {
                    block.append("**Transcript**\n\n\(transcript)")
                }

                out.append(block.joined(separator: "\n\n"))
            }
        }

        return out.joined(separator: "\n\n")
    }

    // MARK: - Filenames

    /// e.g. "recap-summit-2026-2026-07-28.md". Share sheets surface this as the
    /// saved filename, so it has to survive every filesystem it might land on.
    static func filename(for title: String) -> String {
        let slug = title
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .prefix(6)
            .joined(separator: "-")

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        return "recap-\(slug.isEmpty ? "export" : slug)-\(stamp.string(from: Date())).md"
    }

    // MARK: - Helpers

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// Voice notes are tagged so a re-read shows which thoughts were spoken in the
    /// room and which were typed afterwards.
    private static func bulletedNotes(_ notes: [PersonalNote]) -> String? {
        let lines = notes.compactMap { note -> String? in
            guard let content = trimmed(note.content) else { return nil }
            // Keep multi-line notes inside their bullet.
            let indented = content.replacingOccurrences(of: "\n", with: "\n  ")
            return note.type == .voice ? "- 🎙 \(indented)" : "- \(indented)"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
