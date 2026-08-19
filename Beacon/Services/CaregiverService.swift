import Foundation

/// Caregiver layer (שכבת מטפל/ת) against `/v1/caregivers/*`.
struct CaregiverService {
    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    struct ProfileDTO: Decodable, Identifiable {
        let id: UUID
        let displayName: String
        let relationTitle: String
        let preferredLanguage: String
        let isActive: Bool
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case relationTitle = "relation_title"
            case preferredLanguage = "preferred_language"
            case isActive = "is_active"
            case createdAt = "created_at"
        }
    }

    struct CheckInDTO: Decodable, Identifiable {
        let id: UUID
        let caregiverId: UUID
        let mealStatus: String
        let hydrationStatus: String
        let sleepStatus: String
        let painLevel: Int
        let nauseaLevel: Int
        let fatigueLevel: Int
        let medicationStatus: String
        let medicationNote: String?
        let freeTextOriginal: String?
        let originalLanguage: String
        let translatedSummaryHebrew: String
        let attentionLevel: String
        let alertReasons: [String]
        let isAcknowledged: Bool
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case caregiverId = "caregiver_id"
            case mealStatus = "meal_status"
            case hydrationStatus = "hydration_status"
            case sleepStatus = "sleep_status"
            case painLevel = "pain_level"
            case nauseaLevel = "nausea_level"
            case fatigueLevel = "fatigue_level"
            case medicationStatus = "medication_status"
            case medicationNote = "medication_note"
            case freeTextOriginal = "free_text_original"
            case originalLanguage = "original_language"
            case translatedSummaryHebrew = "translated_summary_hebrew"
            case attentionLevel = "attention_level"
            case alertReasons = "alert_reasons"
            case isAcknowledged = "is_acknowledged"
            case createdAt = "created_at"
        }
    }

    struct InstructionDTO: Decodable, Identifiable {
        let id: UUID
        let kind: String
        let detail: String
        let createdByName: String
        let isActive: Bool
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, kind, detail
            case createdByName = "created_by_name"
            case isActive = "is_active"
            case createdAt = "created_at"
        }
    }

    private struct ProfileBody: Encodable {
        let display_name: String
        let relation_title: String
        let preferred_language: String
    }

    private struct ProfilePatchBody: Encodable {
        var display_name: String?
        var relation_title: String?
        var preferred_language: String?
        var is_active: Bool?
    }

    private struct CheckInBody: Encodable {
        let caregiver_id: UUID
        let meal_status: String
        let hydration_status: String
        let sleep_status: String
        let pain_level: Int
        let nausea_level: Int
        let fatigue_level: Int
        let medication_status: String
        let medication_note: String?
        let free_text_original: String?
        let original_language: String
        let translated_summary_hebrew: String
        let attention_level: String
        let alert_reasons: [String]
    }

    private struct InstructionBody: Encodable {
        let kind: String
        let detail: String
    }

    private struct InstructionPatchBody: Encodable {
        let is_active: Bool
    }

    // MARK: - Profiles

    func listProfiles() async throws -> [ProfileDTO] {
        try await client.get("/v1/caregivers/profiles")
    }

    func createProfile(displayName: String, relationTitle: String, preferredLanguage: String) async throws -> ProfileDTO {
        try await client.post(
            "/v1/caregivers/profiles",
            body: ProfileBody(display_name: displayName, relation_title: relationTitle, preferred_language: preferredLanguage)
        )
    }

    func patchProfile(
        profileId: UUID,
        displayName: String? = nil, relationTitle: String? = nil,
        preferredLanguage: String? = nil, isActive: Bool? = nil
    ) async throws -> ProfileDTO {
        try await client.patch(
            "/v1/caregivers/profiles/\(profileId.uuidString)",
            body: ProfilePatchBody(
                display_name: displayName, relation_title: relationTitle,
                preferred_language: preferredLanguage, is_active: isActive
            )
        )
    }

    // MARK: - Check-ins

    func listCheckIns() async throws -> [CheckInDTO] {
        try await client.get("/v1/caregivers/checkins")
    }

    func createCheckIn(
        caregiverId: UUID, mealStatus: String, hydrationStatus: String, sleepStatus: String,
        painLevel: Int, nauseaLevel: Int, fatigueLevel: Int,
        medicationStatus: String, medicationNote: String?, freeTextOriginal: String?,
        originalLanguage: String, translatedSummaryHebrew: String,
        attentionLevel: String, alertReasons: [String]
    ) async throws -> CheckInDTO {
        try await client.post(
            "/v1/caregivers/checkins",
            body: CheckInBody(
                caregiver_id: caregiverId, meal_status: mealStatus, hydration_status: hydrationStatus,
                sleep_status: sleepStatus, pain_level: painLevel, nausea_level: nauseaLevel,
                fatigue_level: fatigueLevel, medication_status: medicationStatus,
                medication_note: medicationNote, free_text_original: freeTextOriginal,
                original_language: originalLanguage, translated_summary_hebrew: translatedSummaryHebrew,
                attention_level: attentionLevel, alert_reasons: alertReasons
            )
        )
    }

    func acknowledgeCheckIn(checkInId: UUID) async throws -> CheckInDTO {
        try await client.post("/v1/caregivers/checkins/\(checkInId.uuidString)/acknowledge")
    }

    // MARK: - Instructions

    func listInstructions() async throws -> [InstructionDTO] {
        try await client.get("/v1/caregivers/instructions")
    }

    func createInstruction(kind: String, detail: String) async throws -> InstructionDTO {
        try await client.post("/v1/caregivers/instructions", body: InstructionBody(kind: kind, detail: detail))
    }

    func deactivateInstruction(instructionId: UUID) async throws -> InstructionDTO {
        try await client.patch(
            "/v1/caregivers/instructions/\(instructionId.uuidString)",
            body: InstructionPatchBody(is_active: false)
        )
    }
}
