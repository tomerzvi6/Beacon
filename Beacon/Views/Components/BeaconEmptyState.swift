import SwiftUI

struct BeaconEmptyState: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.Palette.deepTeal)
                .frame(width: 60, height: 60)
                .background(Theme.Palette.softBlue.opacity(0.3))
                .clipShape(Circle())

            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.deepTeal)
                        .padding(.vertical, 10)
                        .padding(.horizontal, Theme.Spacing.l)
                        .background(Theme.Palette.softBlue.opacity(0.4))
                        .clipShape(Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.l)
    }
}

#Preview("BeaconEmptyState") {
    VStack(spacing: Theme.Spacing.l) {
        BeaconEmptyState(
            systemImage: "checkmark.circle",
            title: "אין משימות פתוחות",
            message: "כל המשימות להיום הושלמו. כל הכבוד!"
        )
        BeaconEmptyState(
            systemImage: "doc.text",
            title: "אין מסמכים בתיק",
            message: "מסמכים שיתקבלו מבית החולים יופיעו כאן.",
            actionTitle: "הוסף מסמך ידנית",
            action: { }
        )
    }
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
