import Foundation
import Supabase

/// Singleton wrapper around the Supabase client.
/// Reads credentials from `Secrets.plist` (gitignored).
enum SupabaseManager {
    static let shared: SupabaseClient = {
        guard
            let url = SecretsLoader.string(for: "SUPABASE_URL"),
            let key = SecretsLoader.string(for: "SUPABASE_ANON_KEY"),
            let supabaseURL = URL(string: url),
            !url.contains("REPLACE_ME"),
            !key.contains("REPLACE_ME")
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

// MARK: - Secrets loader

private enum SecretsLoader {
    static func string(for key: String) -> String? {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return plist[key] as? String
    }
}
