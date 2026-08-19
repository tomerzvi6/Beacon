import UIKit

/// Bridges the UIKit remote-notification registration callbacks into
/// SwiftUI's app lifecycle — there's no SwiftUI-native equivalent, so a
/// minimal `UIApplicationDelegate` is the standard way to receive these.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await PushService().registerDeviceToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Expected in the Simulator and on any build without the Push
        // Notifications capability provisioned — not a user-facing error.
    }
}
