import Foundation
import Supabase

/// Single shared Supabase client, mirroring app/lib/supabase.ts in the web app.
enum SupabaseService {
    static let client = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey
    )
}
