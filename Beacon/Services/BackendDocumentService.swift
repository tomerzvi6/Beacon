import Foundation
import CryptoKit

/// Result of a single upload — either a new document, a duplicate of an
/// existing one (server returned status="conflict"), or failure.
enum UploadOutcome {
    case success(documentId: UUID)
    case duplicate(existingDocumentId: UUID, uploadedAt: Date?)
}

/// Drives the three-step upload flow against the Beacon Parser API:
///   1. POST /v1/uploads/presign            (creates a Document row)
///   2. PUT  <upload_url> with raw bytes    (S3 in prod / local handler in dev)
///   3. POST /v1/uploads/finalize           (sets sha256 + status="finalized")
///
/// Step 2 carries our Beacon JWT only when the presigned URL points back at
/// our own backend (STORAGE_BACKEND=local — the dev/local-device path,
/// where /v1/uploads/local/{id} is itself an authenticated route). A real
/// S3 presigned URL already carries its own signature in the query string
/// and must NOT get an extra Authorization header.
struct BackendDocumentService {
    let client: APIClient
    let uploadSession: URLSession

    init(client: APIClient = .shared, uploadSession: URLSession = .shared) {
        self.client = client
        self.uploadSession = uploadSession
    }

    // MARK: - List + fetch + parse (Phase 9.3)

    /// Page of documents returned by GET /v1/documents/.
    struct ListPage {
        let documents: [BackendDocument]
        let nextCursor: String?
        var hasMore: Bool { nextCursor != nil }
    }

    /// List documents for the caller's household. The cursor scheme is
    /// opaque base64(created_at, id) on the server; pass `nil` for the
    /// first page and forward `nextCursor` from the previous response
    /// to get the next.
    func list(
        category: BackendDocumentCategory? = nil,
        fromDate: Date? = nil,
        toDate: Date? = nil,
        uploadedBy: UUID? = nil,
        query: String? = nil,
        cursor: String? = nil,
        limit: Int = 20
    ) async throws -> ListPage {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let category { items.append(URLQueryItem(name: "category", value: category.rawValue)) }
        if let fromDate { items.append(URLQueryItem(name: "from_date", value: Self.iso8601(fromDate))) }
        if let toDate   { items.append(URLQueryItem(name: "to_date",   value: Self.iso8601(toDate))) }
        if let uploadedBy { items.append(URLQueryItem(name: "uploaded_by", value: uploadedBy.uuidString)) }
        if let q = query?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            items.append(URLQueryItem(name: "q", value: q))
        }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }

        let path = "/v1/documents/" + Self.queryString(items)
        let docs: [BackendDocument] = try await client.get(path)
        // The server doesn't echo the next cursor in the body — it's
        // computed from the last row by the caller. We synthesize it
        // here so the view model has a single state transition.
        let next: String?
        if docs.count == limit, let last = docs.last {
            next = Self.encodeCursor(createdAt: last.created_at, id: last.id)
        } else {
            next = nil
        }
        return ListPage(documents: docs, nextCursor: next)
    }

    /// Fetch one document. Used by polling to watch parse-status
    /// transitions (uploaded → parsing → parsed/failed).
    func fetch(documentId: UUID) async throws -> BackendDocument {
        try await client.get("/v1/documents/\(documentId.uuidString)")
    }

    /// Trigger backend parsing. The endpoint runs synchronously today
    /// (OCR + Claude); the iOS side polls anyway in case another
    /// client is parsing or the network drops mid-call.
    @discardableResult
    func parse(documentId: UUID) async throws -> BackendParseResponse {
        try await client.post("/v1/documents/\(documentId.uuidString)/parse")
    }

    // MARK: - Internal helpers

    private static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private static func queryString(_ items: [URLQueryItem]) -> String {
        guard !items.isEmpty else { return "" }
        var components = URLComponents()
        components.queryItems = items
        return "?" + (components.percentEncodedQuery ?? "")
    }

    /// Mirror of `_encode_cursor` in backend/parser_api/routes/documents.py:
    /// base64(JSON([created_at_iso8601, doc_id])).
    private static func encodeCursor(createdAt: Date, id: UUID) -> String {
        let iso = iso8601(createdAt)
        let arr: [Any] = [iso, id.uuidString]
        guard let data = try? JSONSerialization.data(withJSONObject: arr) else { return "" }
        return data.base64EncodedString()
    }

    /// Upload `data` and finalize it as a Beacon document. Progress is
    /// reported in [0, 1]; the closure runs on the main actor.
    func upload(
        data: Data,
        filename: String,
        mimeType: String,
        category: BackendDocumentCategory?,
        isPrivate: Bool,
        onProgress: (@Sendable @MainActor (Double) -> Void)? = nil
    ) async throws -> UploadOutcome {
        // 1. Presign
        struct PresignBody: Encodable {
            let mime_type: String
            let category: String?
            let is_private: Bool
            let filename: String?
        }
        let presign: BackendPresignResponse = try await client.post(
            "/v1/uploads/presign",
            body: PresignBody(
                mime_type: mimeType,
                category: category?.rawValue,
                is_private: isPrivate,
                filename: filename
            )
        )

        // 2. PUT bytes
        try await putBytes(
            to: presign.upload_url,
            data: data,
            mimeType: mimeType,
            onProgress: onProgress
        )

        // 3. SHA-256 + finalize
        let sha = Self.sha256Hex(data)
        struct FinalizeBody: Encodable {
            let document_id: UUID
            let sha256_hex: String
            let filename: String?
        }
        let finalize: BackendFinalizeResponse = try await client.post(
            "/v1/uploads/finalize",
            body: FinalizeBody(
                document_id: presign.document_id,
                sha256_hex: sha,
                filename: filename
            )
        )

        if finalize.status == "conflict", let existing = finalize.existing_document_id {
            return .duplicate(existingDocumentId: existing, uploadedAt: finalize.uploaded_at)
        }
        return .success(documentId: finalize.document_id)
    }

    // MARK: - Internal: PUT raw bytes with progress reporting

    private func putBytes(
        to urlString: String,
        data: Data,
        mimeType: String,
        onProgress: (@Sendable @MainActor (Double) -> Void)?
    ) async throws {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        if url.host == APIConfig.baseURL.host, let token = TokenStore.read() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let delegate: UploadProgressDelegate? = onProgress.map { UploadProgressDelegate(onProgress: $0) }
        let response: URLResponse
        do {
            (_, response) = try await uploadSession.upload(for: request, from: data, delegate: delegate)
        } catch let urlError as URLError {
            throw APIError.transport(urlError)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, requestId: nil, body: nil)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Progress delegate

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: @Sendable @MainActor (Double) -> Void

    init(onProgress: @escaping @Sendable @MainActor (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Task { @MainActor in self.onProgress(fraction) }
    }
}
