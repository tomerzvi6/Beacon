import Foundation
import UserNotifications

/// Local notifications for medication doses. No server needed — reminders
/// are (re)scheduled from the dose list every time ProactiveCare refreshes,
/// and cancelled when a dose is marked taken.
enum DoseReminderService {
    private static let idPrefix = "dose-"
    private static let authRequestedKey = "beacon.doseReminders.authRequested.v1"

    /// Ask once, the first time there is actually something to remind about.
    static func requestAuthorizationIfNeeded() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: authRequestedKey) else { return }
        defaults.set(true, forKey: authRequestedKey)
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Replaces all pending dose reminders with the given upcoming doses
    /// (next 48h). Idempotent — safe to call on every refresh.
    static func syncReminders(for doses: [MedicationDose]) async {
        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else { return }

        // Drop existing dose reminders (leave any other notification kinds alone).
        let pending = await center.pendingNotificationRequests()
        let doseIds = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: doseIds)

        let now = Date()
        let horizon = now.addingTimeInterval(48 * 3600)
        let calendar = Calendar.current

        for dose in doses
        where dose.status == .upcoming && dose.scheduledAt > now && dose.scheduledAt < horizon {
            let content = UNMutableNotificationContent()
            content.title = "הגיע הזמן לתרופה 💊"
            content.body = dose.medicationDosage.isEmpty
                ? dose.medicationName
                : "\(dose.medicationName) — \(dose.medicationDosage)"
            if let instructions = dose.usageInstructions, !instructions.isEmpty {
                content.body += " (\(instructions))"
            }
            content.sound = .default

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dose.scheduledAt
            )
            let request = UNNotificationRequest(
                identifier: idPrefix + dose.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    static func cancelReminder(doseId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [idPrefix + doseId])
    }
}
