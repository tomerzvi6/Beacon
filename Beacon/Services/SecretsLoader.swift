import Foundation

/// Reads keys from `Secrets.plist` (gitignored). See `Secrets.example.plist`
/// for the expected format. Returns `nil` if the file or key is missing.
enum SecretsLoader {
    static func string(for key: String) -> String? {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: Any],
            let value = plist[key] as? String,
            !value.contains("REPLACE_ME"),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
