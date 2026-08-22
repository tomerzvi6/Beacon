import SwiftUI

struct MedicationDoseCard: View {
    var dose: MedicationDose
    var isPatientView: Bool = false
    var canMarkTaken: Bool = true
    var onUndoTaken: (() -> Void)? = nil
    var onMarkTaken: () -> Void
    @State private var showingUndoConfirm = false

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: dose.scheduledAt)
    }

    var body: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    BeaconAvatar(
                        systemImage: dose.form.iconSymbol,
                        diameter: 40,
                        tint: Theme.Palette.sage,
                        foreground: Theme.Palette.sageDark
                    )
                    Spacer()
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                        Text(timeString)
                            .font(Theme.Typography.timeLabel)
                            .foregroundStyle(Theme.Palette.deepTeal)
                            .beaconHorizontalText()
                        Text(dose.medicationName)
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .beaconHorizontalText(minScale: 0.68)
                        Text(combinedSubtitle)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                actionRow
            }
        }
    }

    private var combinedSubtitle: String {
        if let instructions = dose.usageInstructions {
            return "\(dose.medicationDosage) • \(instructions)"
        }
        return dose.medicationDosage
    }

    @ViewBuilder
    private var actionRow: some View {
        switch dose.status {
        case .upcoming:
            if canMarkTaken {
                BeaconPrimaryButton(
                    title: isPatientView ? "לקחתי עכשיו" : "סמן כנלקח",
                    systemImage: "checkmark.circle.fill",
                    action: onMarkTaken
                )
            } else {
                readOnlyStatus("ממתין לנטילה", systemImage: "clock.fill")
            }
        case .taken:
            Button {
                if onUndoTaken != nil { showingUndoConfirm = true }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.Palette.sageDark)
                        .symbolEffect(.bounce, value: dose.status)
                    Text("נלקח")
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.sageDark)
                        .beaconHorizontalText()
                    if onUndoTaken != nil {
                        Text("· לביטול הקש כאן")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.sageDark.opacity(0.7))
                            .beaconHorizontalText(minScale: 0.6)
                    }
                    Spacer()
                }
                .padding(.vertical, Theme.Layout.controlVerticalPadding)
                .padding(.horizontal, Theme.Spacing.m)
                .background(Theme.Palette.sage)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(onUndoTaken == nil)
            .accessibilityLabel("מינון \(dose.medicationName) נלקח\(onUndoTaken != nil ? ", הקש לביטול הסימון" : "")")
            .confirmationDialog(
                "לבטל את הסימון שהמינון נלקח?",
                isPresented: $showingUndoConfirm,
                titleVisibility: .visible
            ) {
                Button("בטל סימון", role: .destructive) { onUndoTaken?() }
                Button("השאר מסומן כנלקח", role: .cancel) { }
            }
        case .scheduledLater:
            HStack(spacing: Theme.Spacing.xs) {
                Spacer()
                Image(systemName: "clock.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("מתוכנן ל-\(timeString)")
                    .font(Theme.Typography.bodyEmphasis)
                    .beaconHorizontalText()
            }
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.vertical, Theme.Layout.controlVerticalPadding)
            .padding(.horizontal, Theme.Spacing.m)
            .background(Theme.Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
        case .missed:
            if canMarkTaken {
                BeaconPrimaryButton(
                    title: isPatientView ? "כן, לקחתי" : "סמן כנלקח",
                    variant: .danger,
                    action: onMarkTaken
                )
            } else {
                readOnlyStatus("מינון חסר", systemImage: "exclamationmark.triangle.fill")
            }
        }
    }

    private func readOnlyStatus(_ label: String, systemImage: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(label)
                .font(Theme.Typography.bodyEmphasis)
                .beaconHorizontalText()
        }
        .foregroundStyle(Theme.Palette.textSecondary)
        .padding(.vertical, Theme.Layout.controlVerticalPadding)
        .padding(.horizontal, Theme.Spacing.m)
        .background(Theme.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
    }
}

#Preview("MedicationDoseCard") {
    VStack(spacing: Theme.Spacing.m) {
        MedicationDoseCard(
            dose: MedicationDose(
                medicationName: "פרצטמול",
                medicationDosage: "2 כדורים (1000 מ״ג)",
                usageInstructions: "אחרי אוכל",
                form: .pill,
                scheduledAt: Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!,
                status: .upcoming
            ),
            onMarkTaken: { }
        )
        MedicationDoseCard(
            dose: MedicationDose(
                medicationName: "זופרן",
                medicationDosage: "זריקה 1 (8 מ״ג)",
                usageInstructions: "למניעת בחילות",
                form: .injection,
                scheduledAt: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!,
                status: .scheduledLater
            ),
            onMarkTaken: { }
        )
    }
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
