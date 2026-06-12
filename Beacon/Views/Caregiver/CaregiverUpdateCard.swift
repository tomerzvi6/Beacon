import SwiftUI

/// Dashboard card: latest caregiver check-in, summarized in Hebrew.
/// Rendered only when the caregiver layer is active and a check-in exists.
struct CaregiverUpdateCard: View {
    let checkIn: CaregiverCheckIn
    let caregiverName: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            BeaconCard {
                VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "figure.2.arms.open")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.Palette.deepTeal)
                        Text("עדכון מהמטפל/ת")
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Spacer()
                        if checkIn.needsAttention && !checkIn.isAcknowledged {
                            BeaconBadge(
                                text: checkIn.attentionLevel.hebrewLabel,
                                tone: .coral,
                                leadingDot: true
                            )
                        } else {
                            BeaconBadge(text: "מצב רגוע", tone: .sage, leadingDot: true)
                        }
                    }

                    Text(checkIn.translatedSummaryHebrew)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text("\(caregiverName) · \(timeString)")
                            .font(Theme.Typography.caption)
                        Spacer()
                        Text("לפרטים")
                            .font(Theme.Typography.captionEmphasis)
                            .foregroundStyle(Theme.Palette.deepTeal)
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Palette.deepTeal)
                    }
                    .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("עדכון מהמטפל/ת \(caregiverName)")
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        if Calendar.current.isDateInToday(checkIn.createdAt) {
            formatter.dateFormat = "HH:mm"
            return "היום \(formatter.string(from: checkIn.createdAt))"
        }
        formatter.dateFormat = "EEEE HH:mm"
        return formatter.string(from: checkIn.createdAt)
    }
}
