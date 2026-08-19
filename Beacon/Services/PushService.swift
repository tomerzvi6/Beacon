import Foundation

/// Registers this device's APNs token with the backend so other family
/// members' actions (a feed post, a flagged caregiver check-in) can reach
/// it. Requires the Push Notifications capability + a real Apple Developer
/// Program membership to actually receive anything — see
/// `docs/push_notifications.md`. Safe to call speculatively even when that
/// isn't set up yet; the request just never arrives with a real token.
struct PushService {
    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    private struct Body: Encodable {
        let device_token: String
        let platform: String = "ios"
    }

    func registerDeviceToken(_ tokenData: Data) async {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        try? await client.put("/v1/me/push-token", body: Body(device_token: hex))
        // Best-effort — a missed registration just means this device
        // doesn't get pushes until the next successful attempt.
    }
}
