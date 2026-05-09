import Foundation
import GoogleSignIn
import UIKit

/// Result of a successful Google Sign-In flow. Mirrors the subset of
/// `GIDGoogleUser` we forward to the backend exchange.
struct GoogleSignInResult {
    let idToken: String
    let givenName: String?
    let familyName: String?
    let email: String?
    let nonce: String?  // Phase 9.1.5: not yet generated client-side
}

enum GoogleSignInError: Error, LocalizedError {
    case clientIDMissing
    case noPresenter
    case missingIDToken
    case sdkError(Error)

    var errorDescription: String? {
        switch self {
        case .clientIDMissing:
            return "GOOGLE_CLIENT_ID חסר ב-Secrets.plist."
        case .noPresenter:
            return "לא נמצא חלון פעיל ל-Google Sign-In."
        case .missingIDToken:
            return "Google לא החזיר id_token."
        case .sdkError(let error):
            return error.localizedDescription
        }
    }
}

/// Wraps Google's iOS SDK so the rest of the app deals only in
/// `GoogleSignInResult` / `GoogleSignInError` and a single `signIn()`
/// async entry point.
@MainActor
struct GoogleSignInService {
    /// Initialise the SDK with the OAuth client ID from `Secrets.plist`.
    /// Idempotent — call once at app launch.
    static func configureIfNeeded() {
        guard let clientID = SecretsLoader.string(for: "GOOGLE_CLIENT_ID") else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    /// Forward an inbound URL (the OAuth redirect) to the SDK. Wire this
    /// into `BeaconApp.onOpenURL` alongside the invite-token handler.
    @discardableResult
    static func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// Restore a previously-signed-in user without UI, if any.
    /// Returns the result on success, or nil if there is no cached user.
    static func restorePreviousSignIn() async -> GoogleSignInResult? {
        await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                continuation.resume(returning: user.flatMap(Self.makeResult))
            }
        }
    }

    /// Sign-out helper. Safe to call even if no user is signed in.
    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    /// Present the Google Sign-In sheet on top of the key window. Throws
    /// `GoogleSignInError.clientIDMissing` if the SDK isn't configured.
    func signIn() async throws -> GoogleSignInResult {
        guard GIDSignIn.sharedInstance.configuration != nil else {
            throw GoogleSignInError.clientIDMissing
        }
        guard let presenter = Self.topViewController() else {
            throw GoogleSignInError.noPresenter
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let mapped = Self.makeResult(result.user) else {
                throw GoogleSignInError.missingIDToken
            }
            return mapped
        } catch let error as GoogleSignInError {
            throw error
        } catch {
            throw GoogleSignInError.sdkError(error)
        }
    }

    // MARK: - Helpers

    nonisolated private static func makeResult(_ user: GIDGoogleUser) -> GoogleSignInResult? {
        guard let idToken = user.idToken?.tokenString else { return nil }
        return GoogleSignInResult(
            idToken: idToken,
            givenName: user.profile?.givenName,
            familyName: user.profile?.familyName,
            email: user.profile?.email,
            nonce: nil
        )
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScenes = scenes.compactMap { $0 as? UIWindowScene }
        let windows = windowScenes.flatMap { $0.windows }
        let keyWindow = windows.first(where: { $0.isKeyWindow }) ?? windows.first
        return keyWindow?.rootViewController?.beacon_topMost
    }
}

private extension UIViewController {
    var beacon_topMost: UIViewController {
        if let presented = presentedViewController { return presented.beacon_topMost }
        if let nav = self as? UINavigationController {
            return nav.visibleViewController?.beacon_topMost ?? nav
        }
        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.beacon_topMost ?? tab
        }
        return self
    }
}
