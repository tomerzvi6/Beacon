import Foundation

/// Static configuration for the Beacon backend (Parser API).
///
/// Reads `BACKEND_URL` from `Secrets.plist`. If absent or contains the
/// placeholder, falls back to `http://localhost:8000` (simulator dev).
/// Physical devices need the secret pointed at a reachable host (LAN IP
/// or tunnel like ngrok/Tailscale).
enum APIConfig {
    /// Default fallback used when no Secrets.plist value is configured.
    /// Works for the iOS Simulator, never for a physical device.
    static let defaultBaseURL = URL(string: "http://localhost:8000")!

    static let baseURL: URL = {
        if let raw = SecretsLoader.string(for: "BACKEND_URL"),
           let url = URL(string: raw)
        {
            return url
        }
        return defaultBaseURL
    }()

    /// True when running against the simulator-default localhost URL —
    /// surfaced in DiagnosticView so the developer notices on a device.
    static var isUsingDefaultLocalhost: Bool {
        baseURL == defaultBaseURL
    }
}
