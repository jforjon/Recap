import Foundation

enum SummaryClient {
    struct SummaryError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Result {
        let title: String
        let summary: String
        let category: NoteCategory?
    }

    /// Calls /api/summarise — mirrors app/lib/claude.ts's generateSummary().
    static func generateSummary(transcript: String, accessToken: String) async throws -> Result {
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("api/summarise"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["transcript": transcript])

        let (data, response) = try await URLSession.shared.data(for: request)

        struct ResponseBody: Decodable {
            let title: String?
            let summary: String?
            let category: String?
            let error: String?
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SummaryError(message: decoded.error ?? "Summary generation failed")
        }
        guard let title = decoded.title, let summary = decoded.summary else {
            throw SummaryError(message: "Summary response did not include title and summary")
        }

        return Result(
            title: title,
            summary: summary,
            category: decoded.category.flatMap(NoteCategory.init(rawValue:))
        )
    }
}
