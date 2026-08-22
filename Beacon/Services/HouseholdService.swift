import Foundation

/// Family membership against the Beacon backend.
///
/// This replaces the old Supabase invite flow. The two lived in different
/// databases: invites were written to Supabase while documents are scoped by
/// the backend's `household_id`, so an invited relative joined one family and
/// read from another — and saw an empty vault. Everything here speaks to the
/// backend only, so joining and reading agree on who the family is.
struct HouseholdService {
    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    // MARK: - DTOs

    struct Member: Decodable, Identifiable {
        let id: UUID
        let userId: UUID
        let householdId: UUID
        let role: String
        let joinedAt: Date
        let displayName: String
        /// Per-module AccessLevel.rawValue, caregiver rows only — nil for
        /// patient/co_owner (they always have full access) and nil for a
        /// caregiver module key that was never explicitly set (defaults to
        /// read on the backend).
        let permissions: [String: Int]?

        enum CodingKeys: String, CodingKey {
            case id
            case userId = "user_id"
            case householdId = "household_id"
            case role
            case joinedAt = "joined_at"
            case displayName = "display_name"
            case permissions
        }
    }

    struct InviteCode: Decodable {
        let inviteId: UUID
        let code: String
        let expiresInMinutes: Int

        enum CodingKeys: String, CodingKey {
            case inviteId = "invite_id"
            case code
            case expiresInMinutes = "expires_in_minutes"
        }
    }

    /// Joining moves the caller into a different household, and the household
    /// is baked into the JWT — so the server hands back a replacement token.
    struct JoinResult: Decodable {
        let member: Member
        let accessToken: String
        let expiresInSeconds: Int

        enum CodingKeys: String, CodingKey {
            case member
            case accessToken = "access_token"
            case expiresInSeconds = "expires_in_seconds"
        }
    }

    private struct CodeBody: Encodable {
        let code: String
    }

    private struct PermissionPatchBody: Encodable {
        let module: String
        let level: Int
    }

    private struct CoOwnerInviteBody: Encodable {
        // Open code — the person being invited normally hasn't signed up yet,
        // so there is no user id to aim it at.
        let invitee_user_id: UUID? = nil
    }

    private struct CoOwnerInviteResponse: Decodable {
        let inviteId: UUID
        let code: String

        enum CodingKeys: String, CodingKey {
            case inviteId = "invite_id"
            case code
        }
    }

    // MARK: - Reads

    func members() async throws -> [Member] {
        try await client.get("/v1/households/members")
    }

    // MARK: - Invites

    /// Six-digit code for another family member to join as caregiver.
    /// Caregivers get read access; the patient keeps veto over sensitive modules.
    func createCaregiverInvite() async throws -> InviteCode {
        try await client.post("/v1/households/caregiver-invite")
    }

    /// Six-digit code that promotes the joiner to co-owner — a second adult
    /// who can manage the case alongside the patient. Only one per household.
    func createCoOwnerInvite() async throws -> InviteCode {
        let response: CoOwnerInviteResponse = try await client.post(
            "/v1/households/invite/co-owner",
            body: CoOwnerInviteBody()
        )
        return InviteCode(
            inviteId: response.inviteId,
            code: response.code,
            expiresInMinutes: 0
        )
    }

    // MARK: - Join

    /// Redeem a six-digit code. The code alone carries both the household and
    /// the role, which is what makes it shareable over WhatsApp.
    ///
    /// The refreshed token is stored before returning: until it replaces the
    /// old one, every request would still be scoped to the caller's previous
    /// (empty) household and the join would look like it did nothing.
    @discardableResult
    func join(code: String) async throws -> JoinResult {
        let digits = code.filter(\.isNumber)
        guard digits.count == 6 else {
            throw APIError.server(message: "קוד ההצטרפות חייב להיות 6 ספרות", requestId: nil)
        }
        let result: JoinResult = try await client.post(
            "/v1/households/join",
            body: CodeBody(code: digits)
        )
        _ = TokenStore.save(result.accessToken)
        return result
    }

    // MARK: - Manage (patient/co_owner only — backend enforces via require_roles)

    /// Revokes the member's access on the server. Unlike the pre-sync
    /// version of this screen, this actually ends their access everywhere —
    /// their own device's next request 403s (get_session re-checks
    /// membership on every call), not just this device's local list.
    func removeMember(id: UUID) async throws {
        try await client.delete("/v1/households/members/\(id.uuidString)")
    }

    @discardableResult
    func updatePermission(memberId: UUID, module: AppModule, level: AccessLevel) async throws -> Member {
        try await client.patch(
            "/v1/households/members/\(memberId.uuidString)/permissions",
            body: PermissionPatchBody(module: module.rawValue, level: level.rawValue)
        )
    }
}
