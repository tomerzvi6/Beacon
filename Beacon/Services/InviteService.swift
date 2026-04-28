import Foundation

/// Generates and parses invite deep links.
///
/// Link format: `beacon://join?token=<UUID>`
struct InviteService {
    static let scheme = "beacon"
    static let host   = "join"

    let auth: AuthService

    init(auth: AuthService = AuthService()) {
        self.auth = auth
    }

    /// Creates a fresh invite token in Supabase and returns a shareable link.
    func generateInviteLink(for familyId: UUID, createdBy: UUID) async throws -> URL {
        let token = try await auth.generateInviteToken(familyId: familyId, createdBy: createdBy)
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host   = Self.host
        components.queryItems = [URLQueryItem(name: "token", value: token.uuidString)]
        guard let url = components.url else {
            throw AuthError.familyCreationFailed("יצירת לינק נכשלה")
        }
        return url
    }

    /// Parses a deep link and returns the embedded token, or nil if it's not an invite.
    static func parseInviteToken(from url: URL) -> UUID? {
        guard
            url.scheme == scheme,
            url.host == host,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let tokenString = components.queryItems?.first(where: { $0.name == "token" })?.value,
            let token = UUID(uuidString: tokenString)
        else {
            return nil
        }
        return token
    }
}
