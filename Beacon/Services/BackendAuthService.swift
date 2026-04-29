import Foundation

/// Decoded shape of `POST /v1/auth/apple` and `POST /v1/auth/google` —
/// both endpoints return the same envelope.
struct BackendAuthResponse: Decodable {
    let access_token: String
    let token_type: String
    let user: BackendUser
    let expires_in_seconds: Int
}

/// Backwards-compat alias retained from Phase 9.1.
typealias BackendAppleAuthResponse = BackendAuthResponse

/// Exchanges a provider-issued identity token (Apple or Google) for a
/// Beacon JWT issued by the Parser API. On success, persists the JWT in
/// the Keychain via `TokenStore`.
struct BackendAuthService {
    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    // MARK: - Apple

    func exchangeAppleToken(
        identityToken: String,
        rawNonce: String,
        givenName: String?,
        familyName: String?
    ) async throws -> BackendAuthResponse {
        struct FullName: Encodable {
            let given_name: String?
            let family_name: String?
        }
        struct Body: Encodable {
            let identity_token: String
            let nonce: String
            let full_name: FullName?
        }

        let fullName = makeFullName(given: givenName, family: familyName)
        let body = Body(
            identity_token: identityToken,
            nonce: rawNonce,
            full_name: fullName.map { FullName(given_name: $0.given, family_name: $0.family) }
        )

        let response: BackendAuthResponse = try await client.post(
            "/v1/auth/apple",
            body: body,
            authenticated: false
        )
        TokenStore.save(response.access_token)
        return response
    }

    // MARK: - Google

    func exchangeGoogleToken(
        idToken: String,
        nonce: String?
    ) async throws -> BackendAuthResponse {
        struct Body: Encodable {
            let id_token: String
            let nonce: String?
        }
        let body = Body(id_token: idToken, nonce: nonce)
        let response: BackendAuthResponse = try await client.post(
            "/v1/auth/google",
            body: body,
            authenticated: false
        )
        TokenStore.save(response.access_token)
        return response
    }

    // MARK: - Helpers

    private func makeFullName(
        given: String?,
        family: String?
    ) -> (given: String?, family: String?)? {
        let g = given?.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = family?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (g?.isEmpty ?? true) && (f?.isEmpty ?? true) { return nil }
        return (g?.isEmpty == false ? g : nil, f?.isEmpty == false ? f : nil)
    }
}
