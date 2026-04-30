import SwiftUI

/// Hero card pinned to the top of the Medical Vault. Phase 9.3 swap:
/// shows the most recently parsed document's simple Hebrew summary
/// (`parsed_summary_simple_he`). Returns nil when nothing has parsed
/// yet — the parent view conditionally hides it.
struct AISmartSummaryFeatureCard: View {
    var document: BackendDocument
    var onReadFullSummary: () -> Void

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
                    systemImage: document.typedCategory?.iconSymbol ?? "leaf.fill",
                    diameter: 42,
                    tint: .white.opacity(0.2),
                    foreground: .white
                )
                Spacer()
            }

            HStack(spacing: Theme.Spacing.s) {
                BeaconBadge(text: "חדש", tone: .softBlue)
                Text(headline)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            if let simple = document.parsed_summary_simple_he, !simple.isEmpty {
                Text(simple)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .lineLimit(6)
            }

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
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(gradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
        .beaconCardShadow()
    }

    private var headline: String {
        if let category = document.typedCategory {
            return "סיכום AI — \(category.displayLabel)"
        }
        return "סיכום AI חכם"
    }
}
