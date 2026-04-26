import SwiftUI
import SwiftData

struct ProactiveCareView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: ProactiveCareViewModel?
    @State private var toastMessage: String?
    @State private var showingCustomSymptomSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                PatientStatusStrip()

                if let vm = viewModel {
                    BeaconScreenHeader(
                        title: environment.isPatientView ? "התרופות שלי היום" : "התרופות של \(environment.patient.displayName) היום",
                        subtitle: environment.isPatientView ? "הנה מה שצריך לקחת היום." : "הנה מה שדרוש תשומת לב כרגע."
                    )

                    ForEach(vm.lowStockMedications) { med in
                        LowStockCard(medication: med) {
                            vm.createRefillTask(for: med)
                            toastMessage = "נוספה משימת קנייה ל\(med.name)."
                        }
                    }

                    if let missed = vm.missedDose {
                        MissedDoseAlertCard(
                            dose: missed,
                            onMarkTaken: {
                                vm.resolveMissed(missed, markAsTaken: true)
                                toastMessage = "המינון עודכן כנלקח."
                            },
                            onAddNote: {
                                vm.resolveMissed(missed, markAsTaken: false, note: "נרשם על ידי המטפל/ת.")
                                toastMessage = "ההערה נרשמה."
                            }
                        )
                    }

                    VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                        BeaconSectionHeader(
                            title: "תרופות להיום",
                            accessory: AnyView(BeaconBadge(text: "\(vm.remainingCount) נותרו", tone: .softBlue))
                        )
                        ForEach(vm.upcomingDoses) { dose in
                            MedicationDoseCard(dose: dose, isPatientView: environment.isPatientView) {
                                vm.markTaken(dose)
                                toastMessage = environment.isPatientView
                                    ? "כל הכבוד! \(dose.medicationName) נלקח."
                                    : "\(dose.medicationName) סומן כנלקח."
                            }
                        }
                    }

                    QuickSymptomLogger { symptom in
                        if symptom == .custom {
                            showingCustomSymptomSheet = true
                        } else {
                            vm.logSymptom(symptom)
                            toastMessage = "נרשם: \(symptom.displayLabel)."
                        }
                    }

                    if !vm.recentSymptoms.isEmpty {
                        recentSymptomsCard(entries: vm.recentSymptoms)
                    }
                }
            }
            .padding(Theme.Spacing.m)
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
        .sheet(isPresented: $showingCustomSymptomSheet) {
            CustomSymptomSheet { label, severity, note in
                viewModel?.logCustomSymptom(label: label, severity: severity, note: note)
                toastMessage = "נרשם: \(label)."
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
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func toastView(text: String) -> some View {
        Text(text)
            .font(Theme.Typography.bodyEmphasis)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.vertical, 12)
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
