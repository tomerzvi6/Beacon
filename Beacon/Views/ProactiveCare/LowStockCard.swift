import SwiftUI

struct LowStockCard: View {
    var medication: Medication
    var canCreateRefillTask: Bool = true
    var onCreateRefillTask: () -> Void
    @State private var taskCreated = false

    var body: some View {
        BeaconCard(style: .tinted(Theme.Palette.coralBackground.opacity(0.6))) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                BeaconAvatar(
                    systemImage: "exclamationmark.circle.fill",
                    diameter: 36,
                    tint: Theme.Palette.coralBackground,
                    foreground: Theme.Palette.coralAccent
                )
                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    Text("מלאי נמוך — \(medication.name)")
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("נותרו \(medication.stockCount) בלבד. מומלץ לחדש מרשם.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    if taskCreated {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolEffect(.bounce, value: taskCreated)
                            Text("נוספה משימה ללוח הבקרה")
                                .font(Theme.Typography.captionEmphasis)
                                .beaconHorizontalText(minScale: 0.66)
                        }
                        .foregroundStyle(Theme.Palette.sageDark)
                        .padding(.top, Theme.Spacing.xs)
                    } else if canCreateRefillTask {
                        Button(action: {
                            onCreateRefillTask()
                            taskCreated = true
                        }) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "cart.badge.plus")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("צור משימת קנייה")
                                    .font(Theme.Typography.captionEmphasis)
                                    .beaconHorizontalText(minScale: 0.66)
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, Theme.Layout.chipVerticalPadding)
                            .padding(.horizontal, Theme.Spacing.m)
                            .background(Theme.Palette.coralAccent)
                            .clipShape(Capsule())
                            .frame(minHeight: Theme.Layout.minimumTouchTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Theme.Spacing.xs)
                    } else {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "eye.fill")
                            Text("צפייה בלבד")
                                .font(Theme.Typography.captionEmphasis)
                        }
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.top, Theme.Spacing.xs)
                    }
                }
            }
        }
    }
}

#Preview("LowStockCard") {
    LowStockCard(
        medication: Medication(
            name: "אוקסיקונטין",
            dosageDescription: "10 מ״ג",
            form: .pill,
            stockCount: 2
        ),
        onCreateRefillTask: { }
    )
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
