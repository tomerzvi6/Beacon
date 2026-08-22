import SwiftUI

struct MissedDoseAlertCard: View {
    var dose: MedicationDose
    var additionalMissedCount: Int = 0
    var canResolve: Bool = true
    var onMarkTaken: () -> Void
    var onAddNote: () -> Void

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: dose.scheduledAt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Theme.Palette.coralAccent)
                .frame(width: 6)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Theme.CornerRadius.card,
                        bottomLeadingRadius: Theme.CornerRadius.card
                    )
                )

            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                HStack(alignment: .top) {
                    BeaconAvatar(
                        systemImage: "exclamationmark.triangle.fill",
                        diameter: 36,
                        tint: Theme.Palette.coralBackground,
                        foreground: Theme.Palette.coralAccent
                    )
                    Spacer()
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                        Text("התראת מינון חסר")
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(Theme.Palette.coralAccent)
                            .beaconHorizontalText(minScale: 0.7)
                        Text("לא נרשמה נטילת '\(dose.medicationName)' בשעה \(timeString).")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        if additionalMissedCount > 0 {
                            Text("יש עוד \(additionalMissedCount) מינונים חסרים היום — אפשר לראות אותם ברשימה למטה.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.coralAccent)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if canResolve {
                    HStack(spacing: Theme.Spacing.s) {
                        BeaconSecondaryButton(title: "סמן שטופל בלי נטילה", action: onAddNote)
                        BeaconPrimaryButton(
                            title: "סמן כנלקח עכשיו",
                            variant: .danger,
                            action: onMarkTaken
                        )
                    }
                } else {
                    HStack(spacing: Theme.Spacing.xs) {
                        Spacer()
                        Image(systemName: "eye.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("צפייה בלבד")
                            .font(Theme.Typography.bodyEmphasis)
                            .beaconHorizontalText()
                    }
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.vertical, Theme.Layout.controlVerticalPadding)
                    .padding(.horizontal, Theme.Spacing.m)
                    .background(Theme.Palette.cardBackground.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
                }
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.Palette.coralBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
        .beaconCardShadow()
    }
}

#Preview("MissedDoseAlertCard") {
    MissedDoseAlertCard(
        dose: MedicationDose(
            medicationName: "אוקסיקונטין",
            medicationDosage: "10 מ״ג",
            form: .pill,
            scheduledAt: Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!,
            status: .missed
        ),
        onMarkTaken: { },
        onAddNote: { }
    )
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
