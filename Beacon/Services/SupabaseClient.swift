import Foundation
import Supabase

/// Singleton wrapper around the Supabase client.
/// Reads credentials from `Secrets.plist` (gitignored).
enum SupabaseManager {
    static let shared: SupabaseClient = {
        guard
            let url = SecretsLoader.string(for: "SUPABASE_URL"),
            let key = SecretsLoader.string(for: "SUPABASE_ANON_KEY"),
            let supabaseURL = URL(string: url)
        else {
            // Credentials missing or contain placeholder values.
            // Return a dummy client so the app launches in unauthenticated
            // state (showing LoginView) instead of crashing with fatalError.
            // Populate Beacon/Secrets.plist with real values to enable auth.
            return SupabaseClient(
                supabaseURL: URL(string: "https://placeholder.supabase.co")!,
                supabaseKey: "placeholder-key"
            )
        }
        return SupabaseClient(supabaseURL: supabaseURL, supabaseKey: key)
    }()
}
