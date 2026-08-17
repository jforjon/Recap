import Foundation

/// Summarises a whole project across its recordings.
///
/// The prompt is assembled on device: the old `/api/projects/[id]/summary` route
/// existed only to fetch the project's notes server-side, and the app can do
/// that itself.
enum ProjectSummaryClient {
    struct SummaryError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let system = """
    You write a single digest across several recordings someone made under one \
    project — a conference, a course, a client, a research trip.

    Reply with Markdown only. No preamble, no JSON, no title heading.

    Open with a short paragraph on what this body of work covers. Then \
    "## Themes" drawing out what recurs across the recordings, what they \
    disagree about, and what changed over time — this is the part that a reader \
    can't get by opening the recordings one by one, so make it the substance. \
    Then "## By recording", one bullet per recording naming it and its single \
    most useful takeaway.

    If the material contains things the listener said they would do or should \
    follow up on, finish with "## Action items" as a bullet list. Omit that \
    section when there are none; never invent tasks.

    Work only from what you are given.
    """

    /// - Parameter notes: the project's recordings, newest first. A note's
    ///   summary is used when it has one, since it is denser than the raw
    ///   transcript; otherwise the transcript is trimmed to keep the prompt from
    ///   ballooning on a project with dozens of long recordings.
    static func generateProjectSummary(
        projectName: String,
        notes: [Note]
    ) async throws -> String {
        let usable = notes.filter {
            !($0.summary ?? "").isEmpty || !($0.transcript ?? "").isEmpty
        }
        guard !usable.isEmpty else {
            throw SummaryError(message: "This project has no recordings to summarise yet.")
        }

        let body = usable.reversed().enumerated().map { index, note -> String in
            let summary = (note.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let content = summary.isEmpty
                ? String((note.transcript ?? "").prefix(6000))
                : summary
            var header = "### Recording \(index + 1): \(note.title)"
            if let speaker = note.speakerContext, !speaker.isEmpty {
                header += "\nSpeaker & context: \(speaker)"
            }
            return "\(header)\n\n\(content)"
        }.joined(separator: "\n\n---\n\n")

        let summary = try await AnthropicClient.complete(
            system: system,
            user: "Project: \(projectName)\n\n\(body)",
            maxTokens: 4096
        )

        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SummaryError(message: "The summary came back empty. Try again.")
        }
        return trimmed
    }
}
