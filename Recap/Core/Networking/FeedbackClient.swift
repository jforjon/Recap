import Foundation
import UIKit

/// Posts anonymous feedback out of the app.
///
/// Anonymous is literal, not a slogan: there is no address field and the app
/// never touches the user's mail account, so nothing identifying is collected.
/// An earlier draft opened `MFMailComposeViewController`, which contradicted
/// itself — the user's own account is the sender, so "no email is shared" and
/// "we open Mail" cannot both be true.
///
/// The destination is a Google Apps Script web app bound to a Sheet: it appends
/// a row and can email on the same call, which needs no table, no migration and
/// no service beyond the one already holding the sheet.
enum FeedbackClient {

    /// The Apps Script deployment URL, from Secrets.xcconfig — never checked in.
    ///
    /// A successful post is answered with a 302 to script.googleusercontent.com,
    /// which `URLSession` follows as a GET; that redirect is where the "ok"
    /// actually comes from. It only matters if this is ever moved to a client
    /// that keeps POST across redirects, which Google answers with a 405.
    static var endpoint: URL? { AppConfig.feedbackEndpoint }

    /// Sent with the deployment URL so a scraped endpoint can't be posted to
    /// quite so casually. Not a secret in any real sense — it ships in the
    /// binary — but it keeps drive-by writes out of the sheet.
    static var sharedSecret: String { AppConfig.feedbackSecret }

    struct NotConfigured: LocalizedError {
        var errorDescription: String? {
            "Feedback isn't set up yet. Nothing was sent."
        }
    }

    struct SendFailed: LocalizedError {
        var errorDescription: String? {
            "Couldn't send that. Try again in a moment."
        }
    }

    /// The body is capped rather than trusted: an app-embedded endpoint with no
    /// length limit is an invitation.
    private static let maxBodyLength = 4000

    static func send(_ message: String) async throws {
        guard let endpoint else { throw NotConfigured() }

        let trimmed = String(message.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maxBodyLength))

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "secret": sharedSecret,
            "message": trimmed,
            "diagnostics": await diagnostics(),
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        // Apps Script answers 200 even when the script threw — the failure comes
        // back as an HTML error page, not a status code. So the status alone is
        // not evidence of anything; the body has to say so. Without this the app
        // would cheerfully report "Sent" for feedback that never arrived.
        let body = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard (200..<300).contains(status), body == "ok" else { throw SendFailed() }
    }

    /// What rides along with the message.
    ///
    /// Everything here is about the app or the phone model, nothing about the
    /// person. Deliberately excluded: the device *name*, which is very often a
    /// real name ("Jon's iPhone"); the account email; and any recording, title,
    /// transcript, note or summary.
    @MainActor
    static func diagnostics() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let system = UIDevice.current.systemVersion

        let languages = SpokenLanguageStore.shared
        let parts = [
            "recap \(version) (\(build))",
            "iOS \(system)",
            modelIdentifier,
            "audio: \(AudioSettings.shared.location.rawValue)",
            "languages: \(languages.selected.count)",
        ]
        return parts.joined(separator: " · ")
    }

    /// "iPhone17,1" — the hardware model, not the user's name for it.
    private static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        // Bind over the whole `machine` tuple. Rebinding through a pointer to it
        // and asking for the pointer's own size gives 8 bytes, which truncates
        // every identifier longer than "iPhone1".
        return withUnsafeBytes(of: &info.machine) { raw in
            guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "unknown" }
            return String(validatingCString: base) ?? "unknown"
        }
    }
}
