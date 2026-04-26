import SwiftUI
import SwiftData

struct FeedPostCard: View {
    var post: FeedPost
    var currentUser: FamilyMember
    var onReact: (SupportReaction) -> Void
    var onAddComment: ((String) -> Void)? = nil
    @State private var commentDraft: String = ""

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: post.postedAt, relativeTo: Date())
    }

    private var audienceLabel: String {
        switch post.audience {
        case .familyOnly: return "משפחה"
        case .innerCircle: return "מעגל פנימי"
        }
    }

    var body: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                headerRow

                if let status = post.status {
                    BeaconBadge(text: status.displayLabel, tone: tone(for: status), leadingDot: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Text(post.body)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                SupportReactionBar(
                    heartCount: post.heartCount,
                    hugCount: post.hugCount,
                    commentCount: post.comments.count,
                    canReplyWithText: currentUser.isAdmin,
                    onReact: onReact
                )

                if !post.comments.isEmpty {
                    VStack(spacing: Theme.Spacing.s) {
                        ForEach(post.comments.sorted(by: { $0.postedAt < $1.postedAt })) { comment in
                            CommentRow(comment: comment)
                        }
                    }
                    .padding(.top, Theme.Spacing.s)
                }

                if let onAddComment, currentUser.isAdmin {
                    HStack(spacing: Theme.Spacing.s) {
                        Button {
                            let body = commentDraft
                            commentDraft = ""
                            onAddComment(body)
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(commentDraft.trimmingCharacters(in: .whitespaces).isEmpty
                                                 ? Theme.Palette.textSecondary
                                                 : Theme.Palette.deepTeal)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(commentDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("שלח תגובה")

                        TextField("כתוב תגובה...", text: $commentDraft, axis: .vertical)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1...3)
                            .padding(.vertical, 8)
                            .padding(.horizontal, Theme.Spacing.s)
                            .background(Theme.Palette.background)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            BeaconAvatar(
                systemImage: post.author?.avatarSymbol ?? "person.crop.circle",
                diameter: 44,
                tint: Theme.Palette.softBlue,
                foreground: Theme.Palette.deepTeal
            )
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(authorDisplay)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(audienceLabel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text("•")
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text(relativeTime)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Button { } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(Theme.Spacing.xs)
            }
            .buttonStyle(.plain)
        }
    }

    private var authorDisplay: String {
        guard let author = post.author else { return "עדכון משפחתי" }
        if author.isAdmin {
            return "\(author.displayName) (מטפל/ת ראשי/ת)"
        }
        return author.displayName
    }

    private func tone(for status: FeedPostStatus) -> BeaconBadge.Tone {
        switch status {
        case .stable, .improving: return .sage
        case .needsRest, .concerned: return .coral
        }
    }
}

private struct CommentRow: View {
    var comment: FeedComment

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            BeaconAvatar(
                systemImage: comment.author?.avatarSymbol ?? "person.crop.circle",
                diameter: 32,
                tint: Theme.Palette.softBlue,
                foreground: Theme.Palette.deepTeal
            )
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(comment.author?.displayName ?? "חבר משפחה")
                    .font(Theme.Typography.captionEmphasis)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(comment.body)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(Theme.Spacing.s)
        .background(Theme.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
    }
}

#Preview("FeedPostCard") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    let posts = try! container.mainContext.fetch(FetchDescriptor<FeedPost>(sortBy: [SortDescriptor(\.postedAt, order: .reverse)]))
    return ScrollView {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(posts) { post in
                FeedPostCard(post: post, currentUser: .primaryCaregiver, onReact: { _ in })
            }
        }
        .padding()
    }
    .beaconScreenBackground()
    .modelContainer(container)
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
