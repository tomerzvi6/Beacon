import Foundation
import SwiftData

/// Family task management against `/v1/tasks/*`. Mirrors the shape of
/// `HouseholdService` — request/response DTOs live inline rather than in
/// Models/, matching the Phase 9.6 convention.
struct TaskService {
    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    struct TaskDTO: Decodable, Identifiable {
        let id: UUID
        let titleHe: String
        let descriptionHe: String?
        let category: String
        let kind: String            // medical|logistics
        let origin: String          // manual|ai_suggestion|hospital_sync
        let dueAt: Date?
        let status: String          // suggested|approved|done|dismissed
        let claimedBy: UUID?
        let completedAt: Date?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case titleHe = "title_he"
            case descriptionHe = "description_he"
            case category, kind, origin
            case dueAt = "due_at"
            case status
            case claimedBy = "claimed_by"
            case completedAt = "completed_at"
            case createdAt = "created_at"
        }
    }

    private struct CreateBody: Encodable {
        let title_he: String
        let description_he: String?
        let kind: String
        let category: String
        let due_at: Date?
    }

    func list(status: String = "approved") async throws -> [TaskDTO] {
        try await client.get("/v1/tasks/?status_filter=\(status)")
    }

    func create(titleHe: String, detail: String?, kind: String, category: String = "admin", dueAt: Date? = nil) async throws -> TaskDTO {
        try await client.post(
            "/v1/tasks/",
            body: CreateBody(title_he: titleHe, description_he: detail, kind: kind, category: category, due_at: dueAt)
        )
    }

    func claim(taskId: UUID) async throws -> TaskDTO {
        try await client.post("/v1/tasks/\(taskId.uuidString)/claim")
    }

    func unclaim(taskId: UUID) async throws -> TaskDTO {
        try await client.post("/v1/tasks/\(taskId.uuidString)/unclaim")
    }

    func complete(taskId: UUID) async throws -> TaskDTO {
        try await client.post("/v1/tasks/\(taskId.uuidString)/complete")
    }

    func reopen(taskId: UUID) async throws -> TaskDTO {
        try await client.post("/v1/tasks/\(taskId.uuidString)/reopen")
    }

    func dismiss(taskId: UUID) async throws -> TaskDTO {
        try await client.post("/v1/tasks/\(taskId.uuidString)/dismiss")
    }

    /// Creates a task on the backend and inserts the confirmed row into
    /// local SwiftData under the backend-issued id, so it shows up across
    /// every device the household is signed into rather than staying on
    /// this one. Used by view models (refill nudges, AI-suggested tasks,
    /// caregiver follow-ups) that create a `DailyTask` from a context of
    /// their own. Returns nil (and inserts nothing) if the request fails —
    /// callers can fall back to a local-only insert if they need one.
    @MainActor
    @discardableResult
    func createAndInsert(
        title: String, detail: String? = nil, kind: TaskKind, origin: TaskOrigin = .manual,
        in context: ModelContext
    ) async -> DailyTask? {
        guard let dto = try? await create(titleHe: title, detail: detail, kind: kind.rawValue) else {
            return nil
        }
        let task = DailyTask(
            id: dto.id.uuidString,
            title: dto.titleHe,
            detail: dto.descriptionHe,
            kind: TaskKind(rawValue: dto.kind) ?? kind,
            origin: TaskOrigin(rawValue: dto.origin) ?? origin,
            dueAt: dto.dueAt,
            createdAt: dto.createdAt
        )
        context.insert(task)
        try? context.save()
        return task
    }
}
