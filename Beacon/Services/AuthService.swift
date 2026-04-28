import Foundation
import AuthenticationServices
import Supabase
import CryptoKit

/// Auth state machine drives the root navigation.
enum AuthState: Equatable {
    case loading           // checking existing session on launch
    case unauthenticated   // no session — show LoginView
    case needsOnboarding   // signed in but no family — show OnboardingView
    case authenticated     // ready — show RootTabView
}

/// Errors surfaced to the UI in Hebrew.
enum AuthError: LocalizedError {
    case missingAppleIdentityToken
    case invalidAppleCredential
    case sessionLoadFailed(String)
    case signInFailed(String)
    case signOutFailed(String)
    case familyCreationFailed(String)
    case profileLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAppleIdentityToken:
            return "אין אסימון זהות מ-Apple. נסה שוב."
        case .invalidAppleCredential:
            return "פרטי הזיהוי מ-Apple לא תקינים."
        case .sessionLoadFailed(let msg):
            return "שגיאה בטעינת החיבור: \(msg)"
        case .signInFailed(let msg):
            return "ההתחברות נכשלה: \(msg)"
        case .signOutFailed(let msg):
            return "ההתנתקות נכשלה: \(msg)"
        case .familyCreationFailed(let msg):
            return "יצירת המשפחה נכשלה: \(msg)"
        case .profileLoadFailed(let msg):
            return "טעינת הפרופיל נכשלה: \(msg)"
        }
    }
}

/// Result of fetching user state after sign-in.
struct UserContext: Equatable {
    let userId: UUID
    let displayName: String?
    let familyId: UUID?
    let role: String?
    let patientName: String?

    var hasFamily: Bool { familyId != nil }
}

/// Thin wrapper over Supabase Auth + profiles/families queries.
/// Stateless — owned by AppEnvironment.
struct AuthService {
    let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.shared) {
        self.client = client
    }

    // MARK: - Session

    /// Returns the current session if one exists and is valid.
    func currentSession() async -> Session? {
        try? await client.auth.session
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw AuthError.signOutFailed(error.localizedDescription)
        }
    }

    // MARK: - Apple Sign-In

    /// Request configuration for `SignInWithAppleButton`. Hand the returned
    /// nonce back to `signInWithApple(credential:nonce:)` so it can be verified.
    static func makeNonce() -> (raw: String, hashed: String) {
        let raw = randomNonceString()
        let hashed = sha256(raw)
        return (raw, hashed)
    }

    /// Exchanges an Apple ID credential for a Supabase session.
    func signInWithApple(
        credential: ASAuthorizationAppleIDCredential,
        rawNonce: String
    ) async throws {
        guard
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            throw AuthError.missingAppleIdentityToken
        }

        do {
            try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: rawNonce
                )
            )
        } catch {
            throw AuthError.signInFailed(error.localizedDescription)
        }
    }

    // MARK: - Email / Password (development fallback)
    // Useful for testing on simulator where Apple Sign-In requires a paid
    // developer account. Disable once Apple is fully wired up.

    func signInWithEmail(email: String, password: String) async throws {
        do {
            try await client.auth.signIn(email: email, password: password)
        } catch {
            throw AuthError.signInFailed(error.localizedDescription)
        }
    }

    func signUpWithEmail(email: String, password: String) async throws {
        do {
            try await client.auth.signUp(email: email, password: password)
        } catch {
            throw AuthError.signInFailed(error.localizedDescription)
        }
    }

    // MARK: - Profile + Family fetch

    /// Loads everything we need to determine auth state for the current session.
    func loadUserContext() async throws -> UserContext {
        guard let session = try? await client.auth.session else {
            throw AuthError.profileLoadFailed("לא קיים session")
        }
        let userId = session.user.id

        do {
            // Profile (may be empty if user just signed in for the first time)
            let profileRows: [ProfileRow] = try await client
                .from("profiles")
                .select("display_name")
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value
            let profile = profileRows.first

            // Family membership (may be empty if onboarding not yet complete)
            let memberRows: [MembershipRow] = try await client
                .from("family_members")
                .select("family_id, role, families(patient_name)")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            let membership = memberRows.first

            return UserContext(
                userId: userId,
                displayName: profile?.display_name,
                familyId: membership?.family_id,
                role: membership?.role,
                patientName: membership?.families?.patient_name
            )
        } catch {
            throw AuthError.profileLoadFailed(error.localizedDescription)
        }
    }

    // MARK: - Family creation

    /// Calls the SECURITY DEFINER `create_family_for_current_user` RPC.
    @discardableResult
    func createFamily(patientName: String, caregiverName: String) async throws -> UUID {
        do {
            let response: UUID = try await client
                .rpc("create_family_for_current_user", params: [
                    "p_patient_name":   patientName,
                    "p_caregiver_name": caregiverName
                ])
                .execute()
                .value
            return response
        } catch {
            throw AuthError.familyCreationFailed(error.localizedDescription)
        }
    }

    // MARK: - Invite tokens

    @discardableResult
    func generateInviteToken(familyId: UUID, createdBy: UUID) async throws -> UUID {
        struct NewToken: Encodable { let family_id: UUID; let created_by: UUID }
        struct TokenRow: Decodable { let token: UUID }

        let row: TokenRow = try await client
            .from("invite_tokens")
            .insert(NewToken(family_id: familyId, created_by: createdBy))
            .select("token")
            .single()
            .execute()
            .value
        return row.token
    }

    @discardableResult
    func acceptInvite(token: UUID) async throws -> UUID {
        let familyId: UUID = try await client
            .rpc("accept_invite", params: ["p_token": token])
            .execute()
            .value
        return familyId
    }
}

// MARK: - DTOs

private struct ProfileRow: Decodable {
    let display_name: String
}

private struct FamilyRef: Decodable {
    let patient_name: String
}

private struct MembershipRow: Decodable {
    let family_id: UUID
    let role: String
    let families: FamilyRef?
}

// MARK: - Nonce helpers (Apple Sign-In requires SHA256-hashed nonce)

private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remaining = length
    while remaining > 0 {
        var randoms = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
        precondition(status == errSecSuccess)
        for byte in randoms where remaining > 0 {
            if byte < charset.count {
                result.append(charset[Int(byte)])
                remaining -= 1
            }
        }
    }
    return result
}

private func sha256(_ input: String) -> String {
    SHA256.hash(data: Data(input.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}
