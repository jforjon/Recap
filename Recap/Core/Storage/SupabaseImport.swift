import Foundation
import Security

/// One-off: brings recordings made while recap ran on Supabase into the
/// SwiftData store, straight from the old account. Delete this file, the
/// `SUPABASE_*` Info.plist keys and `StorageService.importLegacy` once the data
/// is across — only the developer ever had data on Supabase.
///
/// No Supabase package: two plain REST calls. The old build's supabase-swift
/// left its session in this app's Keychain, so the import usually needs no
/// sign-in at all — the refresh token there buys a fresh access token, and
/// row-level security returns exactly that account's rows. If the session
/// isn't readable (Keychain items are scoped to the signing team, so moving to
/// a new team hides them), the user signs in with email and password instead.
///
/// Ids are kept, so recordings stay filed under their projects, personal notes
/// stay attached, and audio already saved on this phone (named by note id)
/// lines up with its recording. Importing twice is harmless: anything already
/// in the store is skipped.
enum SupabaseImport {
    struct Summary {
        var projects = 0
        var notes = 0
        var personalNotes = 0
        var skipped = 0

        var message: String {
            var text = "Imported \(notes) recordings, \(projects) projects and \(personalNotes) notes."
            if skipped > 0 { text += " \(skipped) were already here and were skipped." }
            return text
        }
    }

    struct ImportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - When to offer it

    private static let finishedKey = "supabaseImport.finished"

    /// The old project is configured in this build and the import hasn't been
    /// completed. Gates the row in Settings → Your data.
    static var isAvailable: Bool {
        AppConfig.legacySupabase != nil && !UserDefaults.standard.bool(forKey: finishedKey)
    }

    /// Worth interrupting launch for: the old build left a signed-in session
    /// behind, so there is almost certainly data, and importing takes one tap.
    static var shouldOfferOnLaunch: Bool {
        isAvailable && savedRefreshToken() != nil
    }

    // MARK: - Running it

    /// Imports using the session the old build left in the Keychain.
    static func importWithSavedSession() async throws -> Summary {
        guard let refreshToken = savedRefreshToken() else {
            throw ImportError(message: "The old sign-in isn't on this iPhone any more. Sign in with your email and password instead.")
        }
        let token = try await authenticate(grantType: "refresh_token", body: ["refresh_token": refreshToken])
        return try await importAll(accessToken: token)
    }

    static func importSigningIn(email: String, password: String) async throws -> Summary {
        let token = try await authenticate(grantType: "password", body: ["email": email, "password": password])
        return try await importAll(accessToken: token)
    }

    private static func importAll(accessToken: String) async throws -> Summary {
        let export = Export(
            projects: try await fetch("projects", accessToken: accessToken),
            notes: try await fetch("notes", accessToken: accessToken),
            personalNotes: try await fetch("personal_notes", accessToken: accessToken)
        )
        let summary = try await StorageService.importLegacy(export)
        // Done for good: stop offering it, and drop the dead session.
        UserDefaults.standard.set(true, forKey: finishedKey)
        deleteSavedSession()
        return summary
    }

    // MARK: - Old session in the Keychain

    /// Where supabase-swift 2.x keeps the session: a generic password under
    /// service `supabase.gotrue.swift`, account `sb-<project ref>-auth-token`,
    /// holding the `Session` as JSON.
    private static func sessionQuery() -> [String: Any]? {
        guard let ref = AppConfig.legacySupabase?.projectRef else { return nil }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "supabase.gotrue.swift",
            kSecAttrAccount as String: "sb-\(ref)-auth-token",
        ]
    }

    private static func savedRefreshToken() -> String? {
        guard var query = sessionQuery() else { return nil }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        // Encoded with a plain JSONEncoder, so camelCase — but older versions
        // nested it under "session" and used snake_case. Accept all of them.
        let session = json["session"] as? [String: Any] ?? json
        return session["refreshToken"] as? String ?? session["refresh_token"] as? String
    }

    private static func deleteSavedSession() {
        guard let query = sessionQuery() else { return }
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - REST

    private static func authenticate(grantType: String, body: [String: String]) async throws -> String {
        guard let config = AppConfig.legacySupabase else {
            throw ImportError(message: "This build doesn't know where the old account was.")
        }
        var components = URLComponents(url: config.url.appendingPathComponent("auth/v1/token"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String
        else {
            if grantType == "password" {
                throw ImportError(message: "That email and password didn't work for the old account.")
            }
            throw ImportError(message: "The old sign-in has expired. Sign in with your email and password instead.")
        }
        return token
    }

    /// Every row of `table` the account can see, a page at a time — PostgREST
    /// caps a single response, and a silent cap would lose recordings.
    private static func fetch<Row: Decodable>(_ table: String, accessToken: String) async throws -> [Row] {
        guard let config = AppConfig.legacySupabase else { return [] }
        let pageSize = 200
        var rows: [Row] = []
        while true {
            var components = URLComponents(url: config.url.appendingPathComponent("rest/v1/\(table)"),
                                           resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.asc"),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(rows.count)),
            ]
            var request = URLRequest(url: components.url!)
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw ImportError(message: "Couldn't read \(table) from the old account (HTTP \(status)). If the Supabase project is paused, restore it from the dashboard and try again.")
            }
            let page: [Row]
            do {
                page = try JSONDecoder().decode([Row].self, from: data)
            } catch {
                throw ImportError(message: "The old \(table) table had an unexpected shape: \(error)")
            }
            rows += page
            if page.count < pageSize { return rows }
        }
    }

    // MARK: - Rows

    struct Export {
        var projects: [LegacyProject]
        var notes: [LegacyNote]
        var personalNotes: [LegacyPersonalNote]
    }

    struct LegacyProject: Decodable {
        let id: UUID
        let name: String
        let notes: String?
        let created_at: String
        let updated_at: String?
    }

    struct LegacyNote: Decodable {
        let id: UUID
        let project_id: UUID?
        let title: String
        let event_name: String?
        let speaker_context: String?
        let category: String?
        let personal_reaction: String?
        let reaction_type: String?
        let summary: String?
        let transcript: String?
        let transcript_segments: [TranscriptSegment]?
        let created_at: String
        let updated_at: String?
    }

    struct LegacyPersonalNote: Decodable {
        let id: UUID
        let project_id: UUID?
        let note_id: UUID?
        let content: String
        let type: String?
        let created_at: String
    }

    // MARK: - Dates

    /// Postgres writes timestamps with microseconds (`…T10:11:12.123456+00:00`),
    /// which `ISO8601DateFormatter` doesn't reliably accept, so the fraction is
    /// cut to milliseconds before parsing. A missing or odd date falls back to
    /// now rather than failing the whole import.
    static func date(_ string: String?) -> Date? {
        guard var string else { return nil }
        string = string.replacingOccurrences(of: " ", with: "T")
        if let dot = string.firstIndex(of: "."),
           let zone = string[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let fraction = string[string.index(after: dot)..<zone].prefix(3)
            string = String(string[..<dot]) + "." + fraction.padding(toLength: 3, withPad: "0", startingAt: 0) + String(string[zone...])
        }
        // "+00" (no minutes) is valid Postgres output but not valid ISO 8601.
        if let sign = string.lastIndex(where: { $0 == "+" || $0 == "-" }),
           string.distance(from: sign, to: string.endIndex) == 3,
           string[..<sign].contains("T") {
            string += ":00"
        }
        return ISODate.date(string)
    }
}
