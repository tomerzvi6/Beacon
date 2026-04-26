import SwiftUI
import SwiftData

struct MedicalVaultView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: MedicalVaultViewModel?
    @State private var openedDocument: MedicalDocument?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                    PatientStatusStrip()

                    if let vm = viewModel {
                        if let alert = vm.alert {
                            HospitalSyncAlertCard(alert: alert, onDismiss: { vm.dismissAlert() })
                        }

                        BeaconScreenHeader(
                            title: "תיק רפואי",
                            subtitle: "כל המסמכים והסיכומים של \(environment.patient.displayName), מסודרים וברורים."
                        )

                        AISmartSummaryFeatureCard(
                            summary: vm.featuredSummary,
                            onReadFullSummary: {
                                openedDocument = vm.documents.first {
                                    $0.aiSummaryKey == vm.featuredSummary.id
                                }
                            },
                            onAddSuggestedTasks: {
                                let added = vm.addSuggestedTasksToCalendar(from: vm.featuredSummary)
                                _ = added
                            },
                            importedTaskCount: vm.lastImportedTaskTitles.isEmpty ? nil : vm.lastImportedTaskTitles.count
                        )

                        searchField(vm: vm)
                        DocumentFilterChips(selection: Binding(
                            get: { vm.selectedFilter },
                            set: { vm.selectedFilter = $0 }
                        ))

                        if vm.filteredDocuments.isEmpty {
                            BeaconCard {
                                BeaconEmptyState(
                                    systemImage: "doc.text.magnifyingglass",
                                    title: vm.searchText.isEmpty ? "אין מסמכים בקטגוריה" : "לא נמצאו תוצאות",
                                    message: vm.searchText.isEmpty
                                        ? "מסמכים שיתקבלו מבית החולים יופיעו כאן אוטומטית."
                                        : "נסו לחפש מילת מפתח אחרת או לבחור קטגוריה אחרת."
                                )
                            }
                        } else {
                            VStack(spacing: Theme.Spacing.m) {
                                ForEach(vm.filteredDocuments) { doc in
                                    DocumentCard(
                                        document: doc,
                                        summary: vm.summary(for: doc),
                                        onOpen: { openedDocument = doc }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.m)
            }
            .beaconScreenBackground()
            .navigationDestination(item: $openedDocument) { doc in
                if let vm = viewModel {
                    DocumentDetailView(
                        document: doc,
                        summary: vm.summary(for: doc),
                        onAddSuggestedTasks: { _ in
                            if let summary = vm.summary(for: doc) {
                                _ = vm.addSuggestedTasksToCalendar(from: summary)
                            }
                        }
                    )
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = MedicalVaultViewModel(context: context)
            } else {
                viewModel?.refresh()
            }
        }
    }

    private func searchField(vm: MedicalVaultViewModel) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Palette.textSecondary)
            TextField("חיפוש מסמך, תאריך או מילת מפתח...", text: Binding(
                get: { vm.searchText },
                set: { vm.searchText = $0 }
            ))
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Theme.Spacing.m)
        .background(Theme.Palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous)
                .strokeBorder(Theme.Palette.textSecondary.opacity(0.15), lineWidth: 1)
        )
    }
}

#Preview("MedicalVaultView") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    return MedicalVaultView()
        .modelContainer(container)
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
