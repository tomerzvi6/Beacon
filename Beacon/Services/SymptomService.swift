import Foundation

/// Quick symptom reporting against `/v1/symptoms/*`.
struct SymptomService {
    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    struct SymptomDTO: Decodable, Identifiable {
        let id: UUID
        let kind: String
        let severity: Int?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, kind, severity
            case createdAt = "created_at"
        }
    }

    private struct ReportBody: Encodable {
        let kind: String
        let severity: Int?
        let note_he: String?
    }

    func list(limit: Int = 20) async throws -> [SymptomDTO] {
        try await client.get("/v1/symptoms/?limit=\(limit)")
    }

    @discardableResult
    func report(kind: String, severity: Int?, noteHe: String?) async throws -> SymptomDTO {
        try await client.post("/v1/symptoms/", body: ReportBody(kind: kind, severity: severity, note_he: noteHe))
    }
}
