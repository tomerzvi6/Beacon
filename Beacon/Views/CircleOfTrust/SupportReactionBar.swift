import SwiftUI

struct SupportReactionBar: View {
    var heartCount: Int
    var hugCount: Int
    var commentCount: Int
    var canReplyWithText: Bool
    var reactedTypes: Set<SupportReaction> = []
    var onReact: (SupportReaction) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            reactionButton(.heart, count: heartCount)
            reactionButton(.hug, count: hugCount)

            if canReplyWithText {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(commentCount)")
                        .font(Theme.Typography.captionEmphasis)
                }
                .foregroundStyle(Theme.Palette.textSecondary)
            } else {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 15))
                    Text("\(commentCount)")
                        .font(Theme.Typography.caption)
                }
                .foregroundStyle(Theme.Palette.textSecondary.opacity(0.5))
            }

            Spacer()
        }
    }

    private func reactionButton(_ reaction: SupportReaction, count: Int) -> some View {
        let isActive = reactedTypes.contains(reaction)
        return Button {
            onReact(reaction)
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: reaction.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.bounce, value: count)
                Text("\(count)")
                    .font(Theme.Typography.bodyEmphasis)
                    .contentTransition(.numericText(value: Double(count)))
            }
            .foregroundStyle(isActive ? .white : tint(for: reaction))
            .padding(.vertical, 10)
            .padding(.horizontal, Theme.Spacing.m)
            .background(isActive ? tint(for: reaction) : tint(for: reaction).opacity(0.1))
            .clipShape(Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(reaction == .heart ? "אהבתי" : "חיבוק") — \(count)\(isActive ? ", כבר הגבת" : "")")
    }

    private func tint(for reaction: SupportReaction) -> Color {
        switch reaction {
        case .heart: return Theme.Palette.coralAccent
        case .hug: return Theme.Palette.deepTeal
        }
    }
}

#Preview("SupportReactionBar") {
    VStack(spacing: Theme.Spacing.m) {
        SupportReactionBar(heartCount: 12, hugCount: 4, commentCount: 3, canReplyWithText: true, onReact: { _ in })
        SupportReactionBar(heartCount: 8, hugCount: 2, commentCount: 0, canReplyWithText: false, onReact: { _ in })
    }
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
