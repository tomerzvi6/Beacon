import Foundation

/// Minimal URLSession-backed JSON client for the Beacon Parser API.
///
/// All requests:
/// - Send `Accept: application/json`, `Content-Type: application/json`.
/// - When `authenticated == true`, attach `Authorization: Bearer <jwt>`
///   from `TokenStore` if a token is present.
/// - Decode ISO-8601 dates (with or without fractional seconds) — matches
///   what FastAPI emits by default.
/// - Surface typed `APIError` rather than raw URL/decoding errors.
final class APIClient {
    static let shared = APIClient()

    /// Invoked once, centrally, whenever any request comes back 401. A
    /// token can go bad mid-session for reasons the user had no part in
    /// (server restarted with a fresh signing key in dev, a session was
    /// revoked) — without a central hook, every screen's own sync call
    /// would silently no-op on 401 and just show stale/empty data forever.
    /// `AppEnvironment` sets this once, at launch, to sign the user out and
    /// route back to login with an explanation.
    static var onUnauthorized: (@Sendable () -> Void)?

    /// Invoked when the server 403s specifically because
    /// household_members no longer has a row for this token — i.e. a
    /// patient/co_owner revoked this device's access from elsewhere.
    /// Distinct from a plain 403 (e.g. a caregiver hitting a write
    /// endpoint above their granted level), which should only fail that
    /// one action, not end the session.
    static var onAccessRevoked: (@Sendable () -> Void)?

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = APIClient.makeSession()) {
        self.session = session
        self.decoder = APIClient.makeDecoder()
        self.encoder = APIClient.makeEncoder()
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = withFractional.date(from: raw) { return date }
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unparseable ISO-8601 date: \(raw)"
            )
        }
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // MARK: - Public API

    func get<R: Decodable>(_ path: String, authenticated: Bool = true) async throws -> R {
        try await sendNoBody(method: "GET", path: path, authenticated: authenticated)
    }

    func post<B: Encodable, R: Decodable>(
        _ path: String,
        body: B,
        authenticated: Bool = true
    ) async throws -> R {
        try await sendWithBody(method: "POST", path: path, body: body, authenticated: authenticated)
    }

    /// Body-less POST — used by FastAPI endpoints that take no request
    /// body (e.g. POST /v1/documents/{id}/parse).
    func post<R: Decodable>(_ path: String, authenticated: Bool = true) async throws -> R {
        try await sendNoBody(method: "POST", path: path, authenticated: authenticated)
    }

    func patch<B: Encodable, R: Decodable>(
        _ path: String,
        body: B,
        authenticated: Bool = true
    ) async throws -> R {
        try await sendWithBody(method: "PATCH", path: path, body: body, authenticated: authenticated)
    }

    func put<B: Encodable>(_ path: String, body: B, authenticated: Bool = true) async throws {
        let _: EmptyResponse = try await sendWithBody(
            method: "PUT", path: path, body: body, authenticated: authenticated
        )
    }

    func delete(_ path: String, authenticated: Bool = true) async throws {
        let _: EmptyResponse = try await sendNoBody(
            method: "DELETE", path: path, authenticated: authenticated
        )
    }

    /// DELETE that returns a decoded body — for endpoints like
    /// `/v1/feed/{id}/react` that respond 200 with the updated resource
    /// rather than 204 No Content.
    func delete<R: Decodable>(_ path: String, authenticated: Bool = true) async throws -> R {
        try await sendNoBody(method: "DELETE", path: path, authenticated: authenticated)
    }

    // MARK: - Internals

    private func sendNoBody<R: Decodable>(
        method: String,
        path: String,
        authenticated: Bool
    ) async throws -> R {
        let request = try makeRequest(method: method, path: path, authenticated: authenticated)
        return try await execute(request)
    }

    private func sendWithBody<B: Encodable, R: Decodable>(
        method: String,
        path: String,
        body: B,
        authenticated: Bool
    ) async throws -> R {
        var request = try makeRequest(method: method, path: path, authenticated: authenticated)
        request.httpBody = try encoder.encode(body)
        return try await execute(request)
    }

    private func makeRequest(
        method: String,
        path: String,
        authenticated: Bool
    ) throws -> URLRequest {
        let base = APIConfig.baseURL.absoluteString.trimmingTrailingSlash()
        let normalized = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: base + normalized) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated, let token = TokenStore.read() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func execute<R: Decodable>(_ request: URLRequest) async throws -> R {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.transport(urlError)
        } catch {
            throw APIError.transport(URLError(.unknown))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        let requestId = http.value(forHTTPHeaderField: "X-Request-ID")

        switch http.statusCode {
        case 200..<300:
            if data.isEmpty {
                if R.self == EmptyResponse.self, let empty = EmptyResponse() as? R {
                    return empty
                }
            }
            do {
                return try decoder.decode(R.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        case 401:
            Self.onUnauthorized?()
            throw APIError.unauthorized
        case 403:
            let detail = Self.extractDetail(from: data)
            if let detail, detail.contains("membership") {
                Self.onAccessRevoked?()
            }
            if let detail {
                throw APIError.server(message: detail, requestId: requestId)
            }
            throw APIError.http(status: http.statusCode, requestId: requestId, body: data)
        default:
            if let detail = Self.extractDetail(from: data) {
                throw APIError.server(message: detail, requestId: requestId)
            }
            throw APIError.http(status: http.statusCode, requestId: requestId, body: data)
        }
    }

    private static func extractDetail(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let dict = json as? [String: Any]
        else { return nil }
        if let s = dict["detail"] as? String { return s }
        if let arr = dict["detail"] as? [[String: Any]],
           let first = arr.first,
           let msg = first["msg"] as? String
        {
            return msg
        }
        return nil
    }
}

/// Marker type used internally for endpoints that return no JSON body.
struct EmptyResponse: Decodable {}

private extension String {
    func trimmingTrailingSlash() -> String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}
