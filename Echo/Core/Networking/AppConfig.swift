import Foundation

/// Reads build-time configuration injected via Secrets.xcconfig -> Info.plist.
enum AppConfig {
    static var supabaseURL: URL {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: raw)
        else {
            fatalError("SUPABASE_URL is missing or invalid. Check Echo/Resources/Secrets.xcconfig.")
        }
        return url
    }

    static var supabaseAnonKey: String {
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !key.isEmpty
        else {
            fatalError("SUPABASE_ANON_KEY is missing. Check Echo/Resources/Secrets.xcconfig.")
        }
        return key
    }
}
