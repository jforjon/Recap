import Foundation

/// Talks to the Anthropic Messages API directly from the device, using the key
/// the user supplied in Settings.
///
/// There is deliberately no server in between. The key belongs to the user, the
/// transcript never touches anyone else's infrastructure, and there is nothing
/// to host, pay for, or keep awake. The trade-off is that this only works for
/// users who have brought their own key — which is the app's only mode.
enum AnthropicClient {
    /// Summaries are a summarisation job over a few thousand tokens: Sonnet is
    /// the right balance of quality and speed, and it's the user's money.
    static let model = "claude-sonnet-5"

    /// Naming a recording is not a hard task, and it runs automatically on every
    /// one — so it uses the cheap model. Roughly a fifth of Sonnet's cost, spent
    /// out of the user's own Anthropic account.
    static let fastModel = "claude-haiku-4-5-20251001"

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    struct ClientError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Sends one prompt and returns the model's text response.
    ///
    /// `outputSchema` is a JSON Schema (`additionalProperties: false`, every key
    /// listed in `required`, `anyOf` for nullables). When given, the API
    /// constrains generation to it, so the reply *is* the JSON — no fence, no
    /// preamble, no unescaped newline inside a Markdown string. Asking nicely in
    /// the system prompt was not enough: a long summary was the most common
    /// place for the model to slip, and the parse failure surfaced as
    /// "unexpected format".
    ///
    /// `maxTokens` is a cap, not a target — the model stops at the end of its
    /// answer, so a generous ceiling costs nothing on a short one. A cap that
    /// is hit truncates the reply mid-JSON, which is why the default is high
    /// and why hitting it is an error rather than a silently mangled result.
    static func complete(
        system: String,
        user: String,
        maxTokens: Int = 8192,
        model: String = model,
        outputSchema: [String: Any]? = nil
    ) async throws -> String {
        guard let key = try await AnthropicKeyStore.load() else {
            throw ClientError(
                message: "Add your Anthropic API key in Settings to generate summaries."
            )
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // A long talk plus a long reply can take a while on a slow connection.
        request.timeoutInterval = 120

        // Built as a dictionary rather than an `Encodable` so the schema — an
        // arbitrary nested JSON object — can go straight in.
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        if let outputSchema {
            body["output_config"] = [
                "format": ["type": "json_schema", "schema": outputSchema],
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(message: "No response from Anthropic.")
        }

        struct ResponseBody: Decodable {
            struct Block: Decodable { let text: String? }
            struct APIError: Decodable { let message: String? }
            let content: [Block]?
            let stopReason: String?
            let error: APIError?
            enum CodingKeys: String, CodingKey {
                case content, error
                case stopReason = "stop_reason"
            }
        }
        let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data)

        guard (200...299).contains(http.statusCode) else {
            // 401 is nearly always a wrong or revoked key, and the raw message
            // doesn't tell the user where to go and fix it.
            if http.statusCode == 401 {
                throw ClientError(
                    message: "Anthropic rejected your API key. Check it in Settings, or paste a new one."
                )
            }
            throw ClientError(
                message: decoded?.error?.message ?? "Anthropic returned an error (\(http.statusCode))."
            )
        }

        // A reply cut off at the cap is not a reply: for JSON it is unparseable,
        // and for prose it ends mid-sentence. Say what happened rather than
        // handing back something that fails further down for a vaguer reason.
        if decoded?.stopReason == "max_tokens" {
            throw ClientError(
                message: "The reply was too long to finish. Try again — a retry usually comes back shorter."
            )
        }
        if decoded?.stopReason == "refusal" {
            throw ClientError(message: "Anthropic declined to process this transcript.")
        }

        let text = (decoded?.content ?? []).compactMap(\.text).joined()
        guard !text.isEmpty else {
            throw ClientError(message: "Anthropic returned an empty response.")
        }
        return text
    }

    /// Models sometimes wrap requested JSON in a Markdown fence despite being
    /// asked not to. Strip it rather than failing the whole summary over it.
    static func unwrapJSON(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        if let firstNewline = trimmed.firstIndex(of: "\n") {
            trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
        }
        if let fence = trimmed.range(of: "```", options: .backwards) {
            trimmed = String(trimmed[..<fence.lowerBound])
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
