import Foundation

/// Calendar (יומן) against `/v1/schedule/*`.
struct ScheduleService {
    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    struct EventDTO: Decodable, Identifiable {
        let id: UUID
        let title: String
        let startsAt: Date
        let kind: String   // medical|routine|logistics
        let locationName: String?
        let companionUserId: UUID?
        let subtitle: String?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title
            case startsAt = "starts_at"
            case kind
            case locationName = "location_name"
            case companionUserId = "companion_user_id"
            case subtitle
            case createdAt = "created_at"
        }
    }

    private struct EventBody: Encodable {
        let title: String
        let starts_at: Date
        let kind: String
        let location_name: String?
        let companion_user_id: UUID?
        let subtitle: String?
    }

    func list() async throws -> [EventDTO] {
        try await client.get("/v1/schedule/")
    }

    func create(
        title: String, startsAt: Date, kind: String,
        locationName: String? = nil, companionUserId: UUID? = nil, subtitle: String? = nil
    ) async throws -> EventDTO {
        try await client.post(
            "/v1/schedule/",
            body: EventBody(
                title: title, starts_at: startsAt, kind: kind,
                location_name: locationName, companion_user_id: companionUserId, subtitle: subtitle
            )
        )
    }

    func delete(eventId: UUID) async throws {
        try await client.delete("/v1/schedule/\(eventId.uuidString)")
    }
}
