import Foundation

/// Medications + dose tracking against `/v1/medications/*` and `/v1/doses/*`.
struct MedicationService {
    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    struct MedicationDTO: Decodable, Identifiable {
        let id: UUID
        let nameHe: String
        let dosage: String?
        let schedule: [String: [String]]  // {"dosing_times": ["HH:MM", ...]}
        let form: String
        let usageInstructions: String?
        let stockCount: Int
        let lowStockThreshold: Int

        enum CodingKeys: String, CodingKey {
            case id
            case nameHe = "name_he"
            case dosage, schedule, form
            case usageInstructions = "usage_instructions"
            case stockCount = "stock_count"
            case lowStockThreshold = "low_stock_threshold"
        }

        var dosingTimes: [String] { schedule["dosing_times"] ?? [] }
    }

    struct DoseDTO: Decodable, Identifiable {
        let id: UUID
        let medicationId: UUID
        let scheduledAt: Date
        let takenAt: Date?
        let noteHe: String?
        let status: String  // upcoming|taken|missed

        enum CodingKeys: String, CodingKey {
            case id
            case medicationId = "medication_id"
            case scheduledAt = "scheduled_at"
            case takenAt = "taken_at"
            case noteHe = "note_he"
            case status
        }
    }

    private struct MedicationBody: Encodable {
        let name_he: String
        let dosage: String?
        let form: String
        let usage_instructions: String?
        let stock_count: Int
        let low_stock_threshold: Int
        let dosing_times: [String]
    }

    private struct MedicationPatchBody: Encodable {
        var name_he: String?
        var dosage: String?
        var form: String?
        var usage_instructions: String?
        var stock_count: Int?
        var low_stock_threshold: Int?
        var dosing_times: [String]?
    }

    // MARK: - Medications

    func list() async throws -> [MedicationDTO] {
        try await client.get("/v1/medications/")
    }

    func create(
        nameHe: String, dosage: String?, form: String, usageInstructions: String?,
        stockCount: Int, lowStockThreshold: Int, dosingTimes: [String]
    ) async throws -> MedicationDTO {
        try await client.post(
            "/v1/medications/",
            body: MedicationBody(
                name_he: nameHe, dosage: dosage, form: form, usage_instructions: usageInstructions,
                stock_count: stockCount, low_stock_threshold: lowStockThreshold, dosing_times: dosingTimes
            )
        )
    }

    func update(
        medicationId: UUID, nameHe: String? = nil, dosage: String? = nil, form: String? = nil,
        usageInstructions: String? = nil, stockCount: Int? = nil, lowStockThreshold: Int? = nil,
        dosingTimes: [String]? = nil
    ) async throws -> MedicationDTO {
        try await client.patch(
            "/v1/medications/\(medicationId.uuidString)",
            body: MedicationPatchBody(
                name_he: nameHe, dosage: dosage, form: form, usage_instructions: usageInstructions,
                stock_count: stockCount, low_stock_threshold: lowStockThreshold, dosing_times: dosingTimes
            )
        )
    }

    func delete(medicationId: UUID) async throws {
        try await client.delete("/v1/medications/\(medicationId.uuidString)")
    }

    // MARK: - Doses

    func listDoses() async throws -> [DoseDTO] {
        try await client.get("/v1/doses/")
    }

    @discardableResult
    func materializeToday() async throws -> [DoseDTO] {
        try await client.post("/v1/doses/materialize-today")
    }

    struct MarkTakenResponse: Decodable {
        let dose_event_id: String
        let taken_at: Date
    }

    /// `note_he` is a query parameter on the backend (a bare optional scalar
    /// route argument, not a Pydantic body model) — must be appended to the
    /// URL, not sent as a JSON body, or the note silently never lands.
    @discardableResult
    func markTaken(doseId: UUID, noteHe: String? = nil) async throws -> MarkTakenResponse {
        var path = "/v1/doses/\(doseId.uuidString)/taken"
        if let noteHe, let encoded = noteHe.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?note_he=\(encoded)"
        }
        return try await client.post(path)
    }
}
