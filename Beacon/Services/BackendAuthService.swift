import Foundation

/// Decoded shape of `POST /v1/auth/apple`.
struct BackendAppleAuthResponse: Decodable {
    let access_token: String
    let token_type: String
    let user: BackendUser
    let expires_in_seconds: Int
}

/// Exchanges an Apple `ASAuthorizationAppleIDCredential` identity token for
/// a Beacon JWT issued by the Parser API. On success, persists the JWT in
/// the Keychain via `TokenStore`.
struct BackendAuthService {
    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func exchangeAppleToken(
        identityToken: String,
        rawNonce: String,
        givenName: String?,
        familyName: String?
    ) async throws -> BackendAppleAuthResponse {
        struct FullName: Encodable {
            let given_name: String?
            let family_name: String?
        }
        struct Body: Encodable {
            let identity_token: String
            let nonce: String
            let full_name: FullName?
        }

        let fullName: FullName? = {
            let g = givenName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let f = familyName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if (g?.isEmpty ?? true) && (f?.isEmpty ?? true) { return nil }
            return FullName(given_name: g?.isEmpty == false ? g : nil,
                            family_name: f?.isEmpty == false ? f : nil)
        }()

        let body = Body(
            identity_token: identityToken,
            nonce: rawNonce,
            full_name: fullName
        )

        let response: BackendAppleAuthResponse = try await client.post(
            "/v1/auth/apple",
            body: body,
            authenticated: false
        )
        TokenStore.save(response.access_token)
        return response
    }
}
