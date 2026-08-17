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
    static func complete(
        system: String,
        user: String,
        maxTokens: Int = 2048,
        model: String = model
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

        struct Message: Encodable {
            let role = "user"
            let content: String
        }
        struct Body: Encodable {
            let model: String
            let maxTokens: Int
            let system: String
            let messages: [Message]
            enum CodingKeys: String, CodingKey {
                case model, system, messages
                case maxTokens = "max_tokens"
            }
        }

        request.httpBody = try JSONEncoder().encode(
            Body(model: model, maxTokens: maxTokens, system: system,
                 messages: [Message(content: user)])
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(message: "No response from Anthropic.")
        }

        struct ResponseBody: Decodable {
            struct Block: Decodable { let text: String? }
            struct APIError: Decodable { let message: String? }
            let content: [Block]?
            let error: APIError?
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
