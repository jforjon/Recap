import Foundation

/// Reads the opening of a recording: what to call it, and who is speaking.
///
/// Separate from `SummaryClient` because it runs automatically on every
/// recording rather than on request, so it is built to be cheap and to fail
/// quietly: the cheap model, a truncated transcript, and a caller that treats
/// any error as "keep the date title, leave the speaker blank".
///
/// Both answers come from one call because they come from the same few minutes
/// of speech — a talk announces its subject and its speaker in the same breath,
/// and two calls would double the cost of something the user never asked for.
enum OpeningDetailsClient {
    /// Sending the opening is enough for both answers, and keeps an automatic
    /// call on an hour-long recording down to a fraction of a cent instead of a
    /// few cents.
    private static let wordLimit = 1500

    struct Details {
        /// Nil when the transcript is too thin or unclear to name.
        let title: String?
        /// Nil when nobody identifiable introduced themselves.
        let speakerContext: String?
    }

    private static let system = """
    You read the opening of a recorded talk, panel, training or meeting and \
    pull out two things: what to call it, and who is speaking.

    The transcript comes from live speech-to-text, so names and company names \
    are often misheard. Use the transcript's own spelling rather than guessing \
    at a different one, and never add a detail that isn't there.

    Reply with a single JSON object and nothing else — no Markdown fence, no \
    commentary. Keys:

    - "title": eight words at most, naming the actual subject rather than the \
      format — "Pricing pressure in enterprise SaaS", not "A panel discussion". \
      Prefer the concrete: if a company, product, technique or place is \
      central, use it. Null if the transcript is too short or unclear to name \
      confidently.
    - "speaker": who is speaking or leading — their name, their role and \
      organisation, and any background or credentials they gave for \
      themselves — plus the event or setting if it is stated. Two or three \
      sentences of plain prose, no headings or bullets. Take it from how they \
      introduce themselves or how a host introduces them. Null if nobody is \
      identifiable; a talk where the speaker is never named has no speaker, and \
      an invented one is worse than none.
    """

    /// Throws only for genuine failures — a missing key, a network error.
    static func generate(transcript: String) async throws -> Details {
        let words = transcript.split(whereSeparator: \.isWhitespace)
        // A few seconds of speech names nothing and introduces nobody.
        guard words.count >= 20 else { return Details(title: nil, speakerContext: nil) }

        let excerpt = words.prefix(wordLimit).joined(separator: " ")
        let text = try await AnthropicClient.complete(
            system: system,
            user: "Transcript opening:\n\n\(excerpt)",
            maxTokens: 400,
            model: AnthropicClient.fastModel
        )

        struct Payload: Decodable {
            let title: String?
            let speaker: String?
        }
        guard
            let data = AnthropicClient.unwrapJSON(text).data(using: .utf8),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return Details(title: nil, speakerContext: nil)
        }

        return Details(
            title: clean(payload.title, maxLength: 120),
            speakerContext: clean(payload.speaker, maxLength: 1000)
        )
    }

    /// Models answer "null" as the string "null" often enough to be worth
    /// guarding, and still wrap a title in quotes despite being asked not to.
    private static func clean(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maxLength,
              !["null", "none", "unknown"].contains(trimmed.lowercased())
        else { return nil }
        return trimmed
    }
}
