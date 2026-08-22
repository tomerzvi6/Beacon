import SwiftUI
import SwiftData

struct ProactiveCareView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: ProactiveCareViewModel?
    @State private var toastMessage: String?
    @State private var showingMedicationManager = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                    if let vm = viewModel {
                        BeaconScreenHeader(
                            title: environment.isPatientView ? "התרופות שלי היום" : "התרופות של \(environment.patient.displayName) היום",
                            subtitle: environment.isPatientView ? "הנה מה שצריך לקחת היום." : "הנה מה שדרוש תשומת לב כרגע."
                        )

                        ForEach(vm.lowStockMedications) { med in
                            LowStockCard(medication: med, canCreateRefillTask: canWriteMedications) {
                                Task {
                                    await vm.createRefillTask(for: med)
                                    toastMessage = "נוספה משימת קנייה ל\(med.name)."
                                }
                            }
                        }

                        if let missed = vm.missedDose {
                            MissedDoseAlertCard(
                                dose: missed,
                                additionalMissedCount: max(0, vm.missedDoseCount - 1),
                                canResolve: canWriteMedications,
                                onMarkTaken: {
                                    Task {
                                        await vm.resolveMissed(missed, markAsTaken: true)
                                        toastMessage = "המינון עודכן כנלקח."
                                    }
                                },
                                onAddNote: {
                                    Task {
                                        let note = "סומן כטופל ללא נטילה על ידי \(environment.currentUser.displayName)."
                                        await vm.resolveMissed(missed, markAsTaken: false, note: note)
                                        toastMessage = "נרשם: טופל בלי נטילה."
                                    }
                                }
                            )
                        }

                        VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                            BeaconSectionHeader(
                                title: "תרופות להיום",
                                accessory: AnyView(
                                    HStack(spacing: Theme.Spacing.s) {
                                        if canWriteMedications {
                                            Button {
                                                showingMedicationManager = true
                                            } label: {
                                                HStack(spacing: Theme.Spacing.xxs) {
                                                    Text("ניהול")
                                                        .font(Theme.Typography.captionEmphasis)
                                                    Image(systemName: "pencil.and.list.clipboard")
                                                        .font(.system(size: 13, weight: .semibold))
                                                }
                                                .foregroundStyle(Theme.Palette.deepTeal)
                                                .padding(.horizontal, Theme.Spacing.s)
                                                .frame(height: Theme.Spacing.xl)
                                                .background(Theme.Palette.softBlue.opacity(0.35), in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("ניהול תרופות")
                                        }
                                        BeaconBadge(text: "\(vm.remainingCount) נותרו", tone: .softBlue)
                                    }
                                )
                            )
                            ForEach(vm.upcomingDoses) { dose in
                                MedicationDoseCard(
                                    dose: dose,
                                    isPatientView: environment.isPatientView,
                                    canMarkTaken: canWriteMedications,
                                    onUndoTaken: canWriteMedications ? {
                                        Task {
                                            await vm.undoTaken(dose)
                                            toastMessage = "הסימון בוטל."
                                        }
                                    } : nil
                                ) {
                                    Task {
                                        await vm.markTaken(dose)
                                        toastMessage = environment.isPatientView
                                            ? "כל הכבוד! \(dose.medicationName) נלקח."
                                            : "\(dose.medicationName) סומן כנלקח."
                                    }
                                }
                            }
                        }

                        if !canWriteMedications {
                            readOnlyMedicationNotice
                        }

                        if !vm.recentSymptoms.isEmpty {
                            recentSymptomsCard(entries: vm.recentSymptoms)
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
                toastView(text: toastMessage)
                    .padding(.bottom, Theme.Spacing.l)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: toastMessage)
        .sensoryFeedback(.success, trigger: toastMessage)
        .sheet(isPresented: $showingMedicationManager, onDismiss: {
            viewModel?.refresh()
        }) {
            if let vm = viewModel {
                MedicationManagerSheet(viewModel: vm)
            }
        }
        .task(id: toastMessage) {
            guard toastMessage != nil else { return }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            toastMessage = nil
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ProactiveCareViewModel(context: context)
            } else {
                viewModel?.refresh()
            }
        }
        .onChange(of: environment.contentRevision) {
            viewModel?.refresh()
        }
        .task {
            await viewModel?.syncWithBackend()
        }
    }

    private var canWriteMedications: Bool {
        environment.canWrite(.medications)
    }

    private func recentSymptomsCard(entries: [SymptomEntry]) -> some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                BeaconSectionHeader(title: "מדדים אחרונים")
                ForEach(entries.prefix(5)) { entry in
                    HStack {
                        Text(entry.loggedAt, style: .time)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Spacer()
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(entry.displayLabel)
                                .font(Theme.Typography.bodyEmphasis)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Image(systemName: entry.type.iconSymbol)
                                .foregroundStyle(Theme.Palette.sageDark)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
    }

    private var readOnlyMedicationNotice: some View {
        BeaconCard {
            BeaconEmptyState(
                systemImage: "eye.fill",
                title: "צפייה בלבד",
                message: "אפשר לראות תרופות ומדדים, אבל רק משתמש עם הרשאת עריכה יכול לסמן מינון או ליצור משימת קנייה."
            )
        }
    }

    private func toastView(text: String) -> some View {
        Text(text)
            .font(Theme.Typography.bodyEmphasis)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.vertical, Theme.Layout.controlVerticalPadding)
            .padding(.horizontal, Theme.Spacing.l)
            .background(.regularMaterial, in: Capsule())
            .beaconCardShadow()
    }
}

#Preview("ProactiveCareView") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    return ProactiveCareView()
        .modelContainer(container)
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
