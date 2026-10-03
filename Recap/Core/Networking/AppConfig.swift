import Foundation

/// Reads build-time configuration injected via Secrets.xcconfig -> Info.plist.
enum AppConfig {
    /// Where anonymous feedback is posted, and the token sent with it.
    ///
    /// Both live in Secrets.xcconfig rather than in source because this repo is
    /// public: an endpoint in a binary takes effort to extract, whereas one in a
    /// public repo is scraped by bots within minutes of the push.
    ///
    /// Only the deployment id is stored — an xcconfig reads an unescaped `//` as
    /// the start of a comment, so a full URL arrives as `https:`. The `$()`
    /// escape does not survive the round trip through the generated plist
    /// either, so the URL is assembled here instead.
    ///
    /// Optional rather than `fatalError`: a missing feedback destination should
    /// disable one screen, never stop the app launching.
    static var feedbackEndpoint: URL? {
        guard
            let id = Bundle.main.object(forInfoDictionaryKey: "FEEDBACK_SCRIPT_ID") as? String,
            !id.isEmpty
        else { return nil }
        return URL(string: "https://script.google.com/macros/s/\(id)/exec")
    }

    static var feedbackSecret: String {
        Bundle.main.object(forInfoDictionaryKey: "FEEDBACK_SECRET") as? String ?? ""
    }

    /// The old Supabase project, read only by `SupabaseImport` to bring the
    /// developer's Supabase-era recordings across. Optional: a build without the
    /// keys simply never offers the import. Delete with `SupabaseImport`.
    static var legacySupabase: (projectRef: String, url: URL, anonKey: String)? {
        guard
            let ref = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PROJECT_REF") as? String,
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !ref.isEmpty, !key.isEmpty,
            let url = URL(string: "https://\(ref).supabase.co")
        else { return nil }
        return (ref, url, key)
    }

    // There is no backend to configure. Summaries call Anthropic directly with
    // the user's own key (`AnthropicClient`), and data lives in SwiftData synced
    // through the user's own iCloud (`RecapStore`).
}
