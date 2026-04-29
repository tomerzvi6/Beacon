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
            fatalError("""
            ⚠️ Supabase credentials missing.

            Please populate Beacon/Secrets.plist with your project's
            SUPABASE_URL and SUPABASE_ANON_KEY (see Secrets.example.plist).

            Get them from:
            Supabase Dashboard → Project Settings → API
            """)
        }
        return SupabaseClient(supabaseURL: supabaseURL, supabaseKey: key)
    }()
}
