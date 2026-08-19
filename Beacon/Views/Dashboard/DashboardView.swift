import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var environment

    @State private var viewModel: DashboardViewModel?
    @State private var caregiverViewModel: CaregiverLayerViewModel?
    @State private var toastMessage: String?
    @State private var selectedCheckIn: CaregiverCheckIn?
    @State private var showingCaregiverReport = false
    @State private var showingCaregiverInstructions = false

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

                        if let caregiverVM = caregiverViewModel,
                           caregiverVM.isCaregiverLayerActive,
                           let caregiver = caregiverVM.activeCaregiver {
                            CaregiverHubCard(
                                caregiverName: caregiver.displayName,
                                languageName: caregiver.preferredLanguage.hebrewName,
                                isMissingTodaysCheckIn: caregiverVM.isMissingTodaysCheckIn,
                                activeInstructionCount: caregiverVM.activeInstructions.count,
                                onOpenReport: { showingCaregiverReport = true },
                                onOpenInstructions: { showingCaregiverInstructions = true }
                            )
                        }

                        if let caregiverVM = caregiverViewModel,
                           caregiverVM.hasDashboardUpdate,
                           let checkIn = caregiverVM.latestCheckIn {
                            CaregiverUpdateCard(
                                checkIn: checkIn,
                                caregiverName: caregiverVM.caregiverName(for: checkIn),
                                onTap: { selectedCheckIn = checkIn }
                            )
                        }

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
                                onClaim: { task in
                                    Task {
                                        await vm.claim(task)
                                        toastMessage = "המשימה שויכה אליך ✓"
                                    }
                                },
                                onRelease: { task in
                                    Task {
                                        await vm.release(task)
                                        toastMessage = "המשימה שוחררה."
                                    }
                                },
                                onToggleComplete: { task in
                                    Task { await vm.toggleCompletion(task) }
                                }
                            )
                        } else {
                            PermissionNoticeCard(module: .tasks)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.top, Theme.Layout.scrollContentTopClearance)
                .padding(.bottom, Theme.Layout.scrollContentBottomClearance)
            }
        }
        .beaconScreenBackground()
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.vertical, Theme.Layout.controlVerticalPadding)
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
        .sheet(item: $selectedCheckIn) { checkIn in
            if let caregiverVM = caregiverViewModel {
                CaregiverCheckInDetailView(checkIn: checkIn, viewModel: caregiverVM)
                    .environment(environment)
            }
        }
        .fullScreenCover(isPresented: $showingCaregiverReport, onDismiss: {
            caregiverViewModel?.refresh()
        }) {
            if let caregiverVM = caregiverViewModel {
                CaregiverReportView(viewModel: caregiverVM)
            }
        }
        .sheet(isPresented: $showingCaregiverInstructions, onDismiss: {
            caregiverViewModel?.refresh()
        }) {
            if let caregiverVM = caregiverViewModel {
                CaregiverInstructionsSheet(viewModel: caregiverVM)
                    .environment(environment)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = DashboardViewModel(context: context, environment: environment)
            } else {
                viewModel?.refresh()
            }
            if caregiverViewModel == nil {
                caregiverViewModel = CaregiverLayerViewModel(context: context)
            } else {
                caregiverViewModel?.refresh()
            }
        }
        .onChange(of: environment.contentRevision) {
            viewModel?.refresh()
            caregiverViewModel?.refresh()
        }
        .task {
            await viewModel?.syncWithBackend()
            await caregiverViewModel?.syncWithBackend()
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
