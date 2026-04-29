import Foundation

/// Errors surfaced by `APIClient`. Each case carries enough context for
/// the diagnostic surface; the user-facing string lives in `userMessage`
/// and is always Hebrew.
enum APIError: Error, LocalizedError {
    case transport(URLError)
    case decoding(Error)
    case http(status: Int, requestId: String?, body: Data?)
    case unauthorized
    case server(message: String, requestId: String?)
    case invalidURL

    /// Hebrew user-facing message. Used by `errorDescription` so SwiftUI
    /// `.alert` and similar APIs pick it up automatically.
    var userMessage: String {
        switch self {
        case .transport:
            return "אין חיבור לשרת. בדקו את החיבור לאינטרנט."
        case .decoding:
            return "התקבלה תשובה לא תקינה מהשרת."
        case .http(let status, _, _):
            return "שגיאת שרת (\(status))."
        case .unauthorized:
            return "פג תוקף ההתחברות. נסו להתחבר שוב."
        case .server(let message, _):
            return message
        case .invalidURL:
            return "כתובת השרת לא תקינה."
        }
    }

    var errorDescription: String? { userMessage }

    /// Diagnostic line for DiagnosticView and logs — includes the request
    /// id when the server returned one (so we can correlate with
    /// `X-Request-ID` lines in backend logs).
    var diagnosticDescription: String {
        switch self {
        case .transport(let urlError):
            return "transport: \(urlError.code) \(urlError.localizedDescription)"
        case .decoding(let error):
            return "decoding: \(error)"
        case .http(let status, let rid, _):
            return "http \(status)" + (rid.map { " rid=\($0)" } ?? "")
        case .unauthorized:
            return "401 unauthorized"
        case .server(let message, let rid):
            return "server: \(message)" + (rid.map { " rid=\($0)" } ?? "")
        case .invalidURL:
            return "invalid URL"
        }
    }
}
