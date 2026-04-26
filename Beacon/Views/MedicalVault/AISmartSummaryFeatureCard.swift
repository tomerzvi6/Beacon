import SwiftUI

struct AISmartSummaryFeatureCard: View {
    var summary: AISummary
    var onReadFullSummary: () -> Void
    var onAddSuggestedTasks: () -> Void
    var importedTaskCount: Int?

    private let gradient = LinearGradient(
        colors: [
            Color("BeaconDeepTeal"),
            Color(red: 0.22, green: 0.45, blue: 0.55),
            Color(red: 0.34, green: 0.56, blue: 0.62)
        ],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
    )

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
            HStack {
                BeaconAvatar(
                    systemImage: "leaf.fill",
                    diameter: 42,
                    tint: .white.opacity(0.2),
                    foreground: .white
                )
                Spacer()
            }

            HStack(spacing: Theme.Spacing.s) {
                BeaconBadge(text: "חדש", tone: .softBlue)
                Text("סיכום AI חכם")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Text(summary.summaryText)
                .font(Theme.Typography.body)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Button(action: onReadFullSummary) {
                HStack {
                    Image(systemName: "arrow.forward")
                        .font(.system(size: 14, weight: .semibold))
                    Text("קרא סיכום מלא")
                        .font(Theme.Typography.bodyEmphasis)
                    Spacer()
                }
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.vertical, 14)
                .padding(.horizontal, Theme.Spacing.m)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack {
                Spacer()
                if let importedTaskCount, importedTaskCount > 0 {
                    Label("נוספו \(importedTaskCount) משימות ליומן", systemImage: "checkmark.circle.fill")
                        .font(Theme.Typography.captionEmphasis)
                        .foregroundStyle(.white)
                } else {
                    Button(action: onAddSuggestedTasks) {
                        Label("הוסף משימות מוצעות", systemImage: "calendar.badge.plus")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(gradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
        .beaconCardShadow()
    }
}

#Preview("AISmartSummaryFeatureCard") {
    AISmartSummaryFeatureCard(
        summary: SampleAISummaries.oncologyVisit,
        onReadFullSummary: { },
        onAddSuggestedTasks: { },
        importedTaskCount: nil
    )
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
