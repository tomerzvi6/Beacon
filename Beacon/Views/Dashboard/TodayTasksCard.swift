import SwiftUI
import SwiftData

struct TodayTasksCard: View {
    var tasks: [DailyTask]
    var currentUser: FamilyMember
    var canWrite: Bool = true
    var onClaim: (DailyTask) -> Void
    var onRelease: (DailyTask) -> Void
    var onToggleComplete: (DailyTask) -> Void

    var body: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                BeaconSectionHeader(title: "משימות להיום", systemImage: "checkmark.circle")

                if tasks.isEmpty {
                    BeaconEmptyState(
                        systemImage: "checkmark.circle",
                        title: "אין משימות פתוחות",
                        message: "כל המשימות להיום הושלמו. כל הכבוד! 🌱"
                    )
                } else {
                    VStack(spacing: Theme.Spacing.s) {
                        ForEach(tasks) { task in
                            TaskRow(
                                task: task,
                                currentUser: currentUser,
                                canWrite: canWrite,
                                onClaim: { onClaim(task) },
                                onRelease: { onRelease(task) },
                                onToggleComplete: { onToggleComplete(task) }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct TaskRow: View {
    var task: DailyTask
    var currentUser: FamilyMember
    var canWrite: Bool = true
    var onClaim: () -> Void
    var onRelease: () -> Void
    var onToggleComplete: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                completionControl

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                    Text(task.title)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .strikethrough(task.isCompleted)
                        .multilineTextAlignment(.trailing)
                    if let detail = task.detail {
                        Text(detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            if let claimant = task.claimedBy, !canWrite {
                HStack(spacing: Theme.Spacing.xs) {
                    Spacer()
                    Text("שובץ ל-\(claimant.displayName)")
                        .font(Theme.Typography.captionEmphasis)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .beaconHorizontalText(minScale: 0.65)
                    Image(systemName: "person.fill.checkmark")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .padding(Theme.Spacing.s)
                .background(Theme.Palette.background)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
            } else if !canWrite {
                readOnlyAssignmentRow
            } else if let claimant = task.claimedBy {
                HStack(spacing: Theme.Spacing.s) {
                    if claimant.id == currentUser.id {
                        Button(action: onRelease) {
                            Text("שחרר")
                                .font(Theme.Typography.captionEmphasis)
                                .foregroundStyle(Theme.Palette.coralAccent)
                                .beaconHorizontalText()
                                .frame(minWidth: Theme.Layout.minimumTouchTarget, minHeight: Theme.Layout.minimumTouchTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("שובץ ל-\(claimant.displayName)")
                            .font(Theme.Typography.captionEmphasis)
                            .foregroundStyle(Theme.Palette.sageDark)
                            .beaconHorizontalText(minScale: 0.65)
                        Image(systemName: "person.fill.checkmark")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Palette.sageDark)
                            .symbolEffect(.bounce, value: claimant.id)
                    }
                }
                .padding(Theme.Spacing.s)
                .background(Theme.Palette.sage.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
            } else {
                Button(action: onClaim) {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("קח על עצמך משימה")
                            .font(Theme.Typography.bodyEmphasis)
                            .beaconHorizontalText()
                    }
                    .foregroundStyle(Theme.Palette.sageDark)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Layout.controlVerticalPadding)
                    .background(Theme.Palette.sage)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
    }

    @ViewBuilder
    private var completionControl: some View {
        if canWrite {
            Button(action: onToggleComplete) {
                completionIcon
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "סמן משימה כפתוחה" : "סמן משימה כהושלמה")
        } else {
            completionIcon
                .accessibilityLabel(task.isCompleted ? "משימה הושלמה" : "משימה פתוחה")
        }
    }

    private var completionIcon: some View {
        Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
            .font(.system(size: 20))
            .foregroundStyle(task.isCompleted ? Theme.Palette.sageDark : Theme.Palette.textSecondary)
            .frame(width: Theme.Layout.minimumTouchTarget, height: Theme.Layout.minimumTouchTarget)
    }

    private var readOnlyAssignmentRow: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Spacer()
            Text("צפייה בלבד")
                .font(Theme.Typography.captionEmphasis)
                .foregroundStyle(Theme.Palette.textSecondary)
                .beaconHorizontalText(minScale: 0.65)
            Image(systemName: "eye.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(Theme.Spacing.s)
        .background(Theme.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
    }
}

#Preview("TodayTasksCard") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    let tasks = try! container.mainContext.fetch(FetchDescriptor<DailyTask>())
    return TodayTasksCard(
        tasks: tasks,
        currentUser: .primaryCaregiver,
        onClaim: { _ in },
        onRelease: { _ in },
        onToggleComplete: { _ in }
    )
    .padding()
    .beaconScreenBackground()
    .modelContainer(container)
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
