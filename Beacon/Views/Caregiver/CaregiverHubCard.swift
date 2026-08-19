import SwiftUI

/// Dashboard hub for the home-caregiver layer: shows today's reporting
/// status and gives one-tap access to the two daily actions — handing the
/// phone over for the daily report, and managing standing instructions.
/// Rendered only when a caregiver is active.
struct CaregiverHubCard: View {
    let caregiverName: String
    let languageName: String
    let isMissingTodaysCheckIn: Bool
    let activeInstructionCount: Int
    var onOpenReport: () -> Void
    var onOpenInstructions: () -> Void

    var body: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "figure.2.arms.open")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.deepTeal)
                    Text("מטפל/ת בבית — \(caregiverName)")
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .beaconHorizontalText()
                    Spacer()
                    if isMissingTodaysCheckIn {
                        BeaconBadge(text: "אין דיווח היום", tone: .coral, leadingDot: true)
                    }
                }

                HStack(spacing: Theme.Spacing.s) {
                    actionButton(
                        icon: "hand.wave.fill",
                        title: "דיווח יומי",
                        subtitle: "מסרו את הטלפון — המסך ב\(languageName)",
                        isProminent: isMissingTodaysCheckIn,
                        action: onOpenReport
                    )
                    actionButton(
                        icon: "list.bullet.clipboard.fill",
                        title: "הוראות למטפל/ת",
                        subtitle: activeInstructionCount > 0
                            ? "\(activeInstructionCount) הוראות פעילות"
                            : "למשל: תרופה ושעה",
                        isProminent: false,
                        action: onOpenInstructions
                    )
                }
            }
        }
    }

    private func actionButton(
        icon: String,
        title: String,
        subtitle: String,
        isProminent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    Text(title)
                        .font(Theme.Typography.bodyEmphasis)
                        .beaconHorizontalText(minScale: 0.8)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .opacity(0.8)
            }
            .padding(Theme.Spacing.s + Theme.Spacing.xs)
            .foregroundStyle(isProminent ? .white : Theme.Palette.textPrimary)
            .background(isProminent ? Theme.Palette.deepTeal : Theme.Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("CaregiverHubCard") {
    VStack(spacing: Theme.Spacing.m) {
        CaregiverHubCard(
            caregiverName: "Maria",
            languageName: "טגלוג (פיליפינית)",
            isMissingTodaysCheckIn: true,
            activeInstructionCount: 2,
            onOpenReport: {},
            onOpenInstructions: {}
        )
        CaregiverHubCard(
            caregiverName: "Maria",
            languageName: "טגלוג (פיליפינית)",
            isMissingTodaysCheckIn: false,
            activeInstructionCount: 0,
            onOpenReport: {},
            onOpenInstructions: {}
        )
    }
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
#endif
