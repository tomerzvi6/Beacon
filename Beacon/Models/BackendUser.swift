import Foundation

/// Mirror of `AppleAuthUserOut` from the backend (`shared/schemas.py`).
/// Keep the property names aligned with Pydantic's snake_case output.
struct BackendUser: Codable, Equatable {
    let id: UUID
    let household_id: UUID
    let role: String          // "patient" | "co_owner" | "caregiver"
    let full_name: String
}

/// Mirror of `HouseholdMemberOut` from the backend.
struct BackendHouseholdMember: Codable, Identifiable, Equatable {
    let id: UUID
    let user_id: UUID
    let household_id: UUID
    let role: String
    let joined_at: Date
}
