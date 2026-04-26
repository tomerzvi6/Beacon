import SwiftUI

struct ScheduleEventRow: View {
    var event: ScheduleEvent

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: event.startsAt)
    }

    private var dayPartString: String {
        let hour = Calendar.current.component(.hour, from: event.startsAt)
        switch hour {
        case 5..<12: return "בוקר"
        case 12..<17: return "צהריים"
        case 17..<22: return "ערב"
        default: return "לילה"
        }
    }

    private var badgeTone: BeaconBadge.Tone {
        switch event.kind {
        case .medical: return .softBlue
        case .routine: return .sage
        case .logistics: return .neutral
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeString)
                    .font(Theme.Typography.timeLabel)
                    .foregroundStyle(Theme.Palette.deepTeal)
                Text(dayPartString)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(minWidth: 64, alignment: .trailing)

            VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                HStack {
                    BeaconBadge(text: event.kind.displayLabel, tone: badgeTone)
                    Spacer()
                    Text(event.title)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.trailing)
                }

                if let location = event.locationName {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(location)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let subtitle = event.subtitle, event.locationName == nil {
                    Text(subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let companion = event.companion {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("מלווה: \(companion.displayName) (\(companion.relation))")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        BeaconAvatar(
                            systemImage: companion.avatarSymbol,
                            diameter: 22,
                            tint: Theme.Palette.softBlue,
                            foreground: Theme.Palette.deepTeal
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
    }
}

#Preview("ScheduleEventRow") {
    VStack(spacing: Theme.Spacing.m) {
        ScheduleEventRow(event: ScheduleEvent(
            title: "ביקורת אונקולוגית",
            startsAt: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!,
            kind: .medical,
            locationName: "בי״ח איכילוב, מחלקה א׳",
            companionMemberId: FamilyMember.daniel.id
        ))
        ScheduleEventRow(event: ScheduleEvent(
            title: "נטילת תרופות - סבב 2",
            startsAt: Calendar.current.date(bySettingHour: 13, minute: 30, second: 0, of: Date())!,
            kind: .routine,
            subtitle: "2 כדורים לאחר ארוחה"
        ))
    }
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
