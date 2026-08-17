import Foundation

/// Turns a recording's transcript into a title, a summary and a category.
///
/// Runs against Anthropic directly from the device — there is no `/api/summarise`
/// route and no server any more.
enum SummaryClient {
    struct SummaryError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Result {
        let title: String
        let summary: String
        let category: NoteCategory?
        /// Who was speaking, when the transcript says. Kept out of the summary
        /// body and stored in its own column, the way the web app split it.
        let speakerContext: String?
    }

    private static let system = """
    You summarise transcripts of talks, panels, trainings and meetings that \
    someone recorded to refer back to later.

    The transcript comes from live speech-to-text. Expect no speaker labels, \
    occasional misheard words, and filler. Work with what is there; never \
    invent detail that isn't in the transcript, and don't note that the \
    transcript is imperfect.

    Reply with a single JSON object and nothing else — no Markdown fence, no \
    commentary. Keys:

    - "title": a specific, plain title, 8 words or fewer. Name the actual \
      subject rather than the format. Not "Panel discussion" but "Pricing \
      pressure in enterprise SaaS".
    - "summary": Markdown. Lead with a short paragraph on what this was about, \
      then "## Key points" as a bullet list of the substance — the arguments, \
      numbers, examples and disagreements, not a table of contents. Where the \
      transcript makes clear who said what, attribute it. If, and only if, the \
      transcript contains things the listener said they would do or should \
      follow up on, add a final "## Action items" section as a bullet list. \
      Omit that section entirely when there are none — do not invent tasks.
    - "category": exactly one of "talk", "training", "panel", or null when none \
      of them fits.
    - "speaker": who gave the talk or led the session — their name, role and \
      organisation, the background they gave for themselves, and the event or \
      setting — plus their apparent angle or expertise where the transcript \
      shows it. Two or three sentences of plain prose, no headings or bullets. \
      Names are often misheard by speech-to-text: use the transcript's own \
      spelling rather than guessing at a different one. Null when nobody is \
      identifiable. Keep this out of the summary — it has its own place in the \
      app — but do attribute points to people inside the summary as usual.
    """

    static func generateSummary(transcript: String) async throws -> Result {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SummaryError(message: "There's no transcript to summarise yet.")
        }

        let text = try await AnthropicClient.complete(
            system: system,
            user: "Transcript:\n\n\(trimmed)"
        )

        struct Payload: Decodable {
            let title: String?
            let summary: String?
            let category: String?
            let speaker: String?
        }
        guard
            let data = AnthropicClient.unwrapJSON(text).data(using: .utf8),
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines),
            let summary = payload.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty, !summary.isEmpty
        else {
            throw SummaryError(message: "The summary came back in an unexpected format. Try again.")
        }

        let speaker = payload.speaker?.trimmingCharacters(in: .whitespacesAndNewlines)

        return Result(
            title: title,
            summary: summary,
            category: payload.category.flatMap(NoteCategory.init(rawValue:)),
            // "null" as a string turns up often enough to be worth guarding.
            speakerContext: (speaker?.isEmpty == false && speaker?.lowercased() != "null")
                ? speaker
                : nil
        )
    }
}
