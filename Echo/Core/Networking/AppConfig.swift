import Foundation

/// Reads build-time configuration injected via Secrets.xcconfig -> Info.plist.
enum AppConfig {
    static var supabaseURL: URL {
        guard
            let ref = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PROJECT_REF") as? String,
            !ref.isEmpty,
            let url = URL(string: "https://\(ref).supabase.co")
        else {
            fatalError("SUPABASE_PROJECT_REF is missing. Check Echo/Resources/Secrets.xcconfig.")
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
