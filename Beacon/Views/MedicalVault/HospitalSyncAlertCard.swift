import SwiftUI

struct HospitalSyncAlertCard: View {
    var alert: HospitalSyncAlert
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            BeaconAvatar(
                systemImage: "plus.diamond.fill",
                diameter: 36,
                tint: Theme.Palette.sage,
                foreground: Theme.Palette.sageDark
            )

            VStack(alignment: .trailing, spacing: 2) {
                Text(alert.title)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.sageDark)
                    .multilineTextAlignment(.trailing)
                Text(alert.body)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.sageDark)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("סגור התראה")
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Palette.sage)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous)
                .strokeBorder(Theme.Palette.sageDark.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
    }
}

#Preview("HospitalSyncAlertCard") {
    HospitalSyncAlertCard(
        alert: HospitalSyncAlert(
            title: "תוצאות מעבדה חדשות התקבלו",
            body: "לחץ לצפייה בעדכון האחרון מבי״ח שיבא",
            sourceHospital: "בי״ח שיבא"
        ),
        onDismiss: { }
    )
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
