import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var environment

    @State private var viewModel: DashboardViewModel?
    @State private var toastMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                    if let vm = viewModel {
                        GreetingHeader(
                            greeting: environment.greetingForCurrentHour,
                            name: environment.greetingName,
                            dateString: environment.todayHebrewDate
                        )

                        if environment.canRead(.schedule) {
                            FamilyScheduleCard(events: vm.events)
                        } else {
                            PermissionNoticeCard(module: .schedule)
                        }

                        if environment.canRead(.tasks) {
                            TodayTasksCard(
                                tasks: vm.tasks.filter { !$0.isCompleted } + vm.tasks.filter { $0.isCompleted },
                                currentUser: environment.currentUser,
                                canWrite: environment.canWrite(.tasks),
                                onClaim: {
                                    vm.claim($0)
                                    toastMessage = "המשימה שויכה אליך ✓"
                                },
                                onRelease: {
                                    vm.release($0)
                                    toastMessage = "המשימה שוחררה."
                                },
                                onToggleComplete: { vm.toggleCompletion($0) }
                            )
                        } else {
                            PermissionNoticeCard(module: .tasks)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.m)
            }
        }
        .beaconScreenBackground()
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, Theme.Spacing.l)
                    .background(.regularMaterial, in: Capsule())
                    .beaconCardShadow()
                    .padding(.bottom, Theme.Spacing.l)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: toastMessage)
        .sensoryFeedback(.success, trigger: toastMessage)
        .task(id: toastMessage) {
            guard toastMessage != nil else { return }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            toastMessage = nil
        }
        .onAppear {
            if viewModel == nil {
                viewModel = DashboardViewModel(context: context, environment: environment)
            } else {
                viewModel?.refresh()
            }
        }
    }
}

private struct PermissionNoticeCard: View {
    let module: AppModule

    var body: some View {
        BeaconCard {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: Theme.Layout.statusStripIconSize, height: Theme.Layout.statusStripIconSize)
                    .background(Theme.Palette.softBlue.opacity(0.35))
                    .clipShape(Circle())
                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    Text("אין הרשאה ל\(module.displayLabel)")
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("המטופל/ת או מנהל/ת הגישה יכולים לפתוח לך גישה.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
            }
        }
    }
}

#Preview("DashboardView") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    return DashboardView()
        .modelContainer(container)
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
