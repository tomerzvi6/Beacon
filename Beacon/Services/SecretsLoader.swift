import Foundation

/// Reads keys from `Secrets.plist` (gitignored). See `Secrets.example.plist`
/// for the expected format. Returns `nil` if the file or key is missing.
enum SecretsLoader {
    private static let secretsFilename = "Secrets.plist"

    static func string(for key: String) -> String? {
        if let value = value(for: key, from: Bundle.main.url(forResource: "Secrets", withExtension: "plist")) {
            return value
        }

#if DEBUG
        // Developer fallback when the plist was created in the repo but not yet
        // added to Copy Bundle Resources for the active target/scheme.
        let candidatePaths = [
            "Beacon/Beacon/\(secretsFilename)",
            secretsFilename
        ]
        for relativePath in candidatePaths {
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(relativePath)
            if let value = value(for: key, from: url) {
                return value
            }
        }
#endif

        return nil
    }

    private static func value(for key: String, from url: URL?) -> String? {
        guard
            let url,
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: Any],
            let rawValue = plist[key] as? String
        else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .controlCharacters)
        guard !value.contains("REPLACE_ME"), !value.isEmpty else { return nil }
        return value
    }
}
