import Foundation

enum TranscriptionClient {
    struct TranscribeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Uploads one audio chunk to /api/transcribe — mirrors app/lib/whisper.ts.
    static func transcribe(fileURL: URL, accessToken: String) async throws -> String {
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("api/transcribe"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        struct ResponseBody: Decodable {
            let transcript: String?
            let error: String?
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TranscribeError(message: decoded.error ?? "Transcription failed")
        }
        guard let transcript = decoded.transcript else {
            throw TranscribeError(message: "Transcription response did not include transcript text")
        }
        return transcript
    }
}
