import SwiftUI

/// Library search across everything a recording or project actually contains —
/// not just its title.
///
/// Runs entirely on what the Library already has in memory: `getNotes()` selects
/// `*`, so transcripts and summaries are loaded anyway, and personal notes come
/// down in one extra query. No server-side index, no per-keystroke round trip.
///
/// Matching is case- and diacritic-insensitive (so "resume" finds "résumé") and
/// multi-word queries are AND-ed across fields, so "keynote pricing" matches a
/// recording titled "Keynote" whose transcript mentions pricing.
enum LibrarySearch {

    /// Which part of an item the query was found in. The order is the priority
    /// used when several fields match — the most useful one to show wins.
    enum Field: String {
        case title, summary, note, transcript, speaker, event

        var label: String {
            switch self {
            case .title: "TITLE"
            case .summary: "SUMMARY"
            case .note: "YOUR NOTE"
            case .transcript: "TRANSCRIPT"
            case .speaker: "SPEAKER"
            case .event: "EVENT"
            }
        }
    }

    struct NoteHit: Identifiable {
        let note: Note
        let field: Field
        /// Text around the match, with the matched term highlighted. Nil when the
        /// match was the title, which the row already shows in full.
        let snippet: AttributedString?
        var id: UUID { note.id }
    }

    struct ProjectHit: Identifiable {
        let project: ProjectWithNoteCount
        let field: Field
        let snippet: AttributedString?
        var id: UUID { project.id }
    }

    // MARK: - Entry points

    static func notes(
        matching rawQuery: String,
        in notes: [Note],
        personalNotesByRecording: [UUID: [PersonalNote]]
    ) -> [NoteHit] {
        guard let terms = terms(from: rawQuery) else {
            return notes.map { NoteHit(note: $0, field: .title, snippet: nil) }
        }

        return notes.compactMap { note in
            let personal = (personalNotesByRecording[note.id] ?? [])
                .map(\.content)
                .joined(separator: "\n")

            let fields: [(Field, String)] = [
                (.title, note.title),
                (.summary, note.summary ?? ""),
                (.note, personal),
                (.transcript, note.transcript ?? ""),
                (.speaker, note.speakerContext ?? ""),
                (.event, note.eventName ?? ""),
            ]

            guard let best = bestMatch(terms: terms, fields: fields) else { return nil }
            return NoteHit(
                note: note,
                field: best.field,
                snippet: best.field == .title ? nil : snippet(best.text, around: best.term)
            )
        }
    }

    static func projects(
        matching rawQuery: String,
        in projects: [ProjectWithNoteCount],
        personalNotesByProject: [UUID: [PersonalNote]]
    ) -> [ProjectHit] {
        guard let terms = terms(from: rawQuery) else {
            return projects.map { ProjectHit(project: $0, field: .title, snippet: nil) }
        }

        return projects.compactMap { item in
            let personal = (personalNotesByProject[item.id] ?? [])
                .map(\.content)
                .joined(separator: "\n")

            // A project's generated summary lives in `notes` — see
            // ProjectDetailView.generateSummary().
            let fields: [(Field, String)] = [
                (.title, item.project.name),
                (.summary, item.project.notes ?? ""),
                (.note, personal),
            ]

            guard let best = bestMatch(terms: terms, fields: fields) else { return nil }
            return ProjectHit(
                project: item,
                field: best.field,
                snippet: best.field == .title ? nil : snippet(best.text, around: best.term)
            )
        }
    }

    // MARK: - Matching

    /// Nil for a blank query, meaning "no filtering" rather than "matches nothing".
    private static func terms(from raw: String) -> [String]? {
        let parts = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        return parts.isEmpty ? nil : parts
    }

    private struct Match {
        let field: Field
        let text: String
        /// The term to build the snippet around.
        let term: String
    }

    /// An item matches only when *every* term appears somewhere in it, so extra
    /// words narrow the results instead of widening them. The hit that gets shown
    /// is chosen by field priority, using the longest term — the most distinctive
    /// one — to position the snippet.
    private static func bestMatch(terms: [String], fields: [(Field, String)]) -> Match? {
        let populated = fields.filter { !$0.1.isEmpty }

        for term in terms {
            guard populated.contains(where: { contains($0.1, term) }) else { return nil }
        }

        let anchor = terms.max(by: { $0.count < $1.count }) ?? terms[0]
        if let field = populated.first(where: { contains($0.1, anchor) }) {
            return Match(field: field.0, text: field.1, term: anchor)
        }
        // The anchor sits in a different field from the others; fall back to
        // whichever field the first term landed in.
        guard let field = populated.first(where: { contains($0.1, terms[0]) }) else { return nil }
        return Match(field: field.0, text: field.1, term: terms[0])
    }

    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: - Snippets

    /// A one-line window of `text` around the first occurrence of `term`, with the
    /// term highlighted. Transcripts arrive as long multi-line blocks, so runs of
    /// whitespace are collapsed first — otherwise the snippet renders as ragged
    /// fragments stacked on top of each other.
    private static func snippet(_ text: String, around term: String, context: Int = 44) -> AttributedString? {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let match = flat.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let start = flat.index(match.lowerBound, offsetBy: -context, limitedBy: flat.startIndex)
            ?? flat.startIndex
        let end = flat.index(match.upperBound, offsetBy: context, limitedBy: flat.endIndex)
            ?? flat.endIndex

        var result = AttributedString(start > flat.startIndex ? "…" : "")
        result += AttributedString(flat[start..<match.lowerBound])

        // Set the font on the run directly rather than using a presentation
        // intent — intents only resolve when the string came from Markdown.
        var highlighted = AttributedString(flat[match])
        highlighted.foregroundColor = AppColors.accentGraphic
        highlighted.font = AppFont.sans(14, medium: true)
        result += highlighted

        result += AttributedString(flat[match.upperBound..<end])
        if end < flat.endIndex { result += AttributedString("…") }
        return result
    }
}
