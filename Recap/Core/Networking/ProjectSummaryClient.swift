import Foundation

enum ProjectSummaryClient {
    struct SummaryError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Calls /api/projects/[id]/summary — mirrors handleGenerateSummary() in the web app.
    static func generateProjectSummary(projectId: UUID, accessToken: String) async throws -> String {
        var request = URLRequest(
            url: AppConfig.apiBaseURL.appendingPathComponent("api/projects/\(projectId.uuidString)/summary")
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        struct ResponseBody: Decodable {
            let summary: String?
            let error: String?
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SummaryError(message: decoded.error ?? "Failed to generate project summary")
        }
        guard let summary = decoded.summary else {
            throw SummaryError(message: "Summary response was empty")
        }
        return summary
    }
}
