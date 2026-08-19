import SwiftUI

/// Family-side management of the regular medication list: fix an OCR
/// mistake, change dosing times, or remove a medication that was stopped.
struct MedicationManagerSheet: View {
    let viewModel: ProactiveCareViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editingMedication: Medication? = nil
    @State private var deletingMedication: Medication? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                    if viewModel.medications.isEmpty {
                        BeaconCard {
                            BeaconEmptyState(
                                systemImage: "pills",
                                title: "אין תרופות עדיין",
                                message: "הוסיפו תרופה דרך צילום קופסה בטאב התיק הרפואי, או מהזנה ידנית."
                            )
                        }
                    } else {
                        ForEach(viewModel.medications) { medication in
                            medicationRow(medication)
                        }
                    }
                }
                .padding(Theme.Spacing.m)
            }
            .beaconScreenBackground()
            .navigationTitle("ניהול תרופות")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגור") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(item: $editingMedication) { medication in
            MedicationEditSheet(viewModel: viewModel, medication: medication)
        }
        .confirmationDialog(
            "למחוק את \(deletingMedication?.name ?? "התרופה")?",
            isPresented: Binding(
                get: { deletingMedication != nil },
                set: { if !$0 { deletingMedication = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("מחיקה", role: .destructive) {
                if let medication = deletingMedication {
                    Task { await viewModel.deleteMedication(medication) }
                }
                deletingMedication = nil
            }
            Button("ביטול", role: .cancel) { deletingMedication = nil }
        } message: {
            Text("המינונים העתידיים יימחקו. מינונים שכבר סומנו כנלקחו יישארו בהיסטוריה.")
        }
    }

    private func medicationRow(_ medication: Medication) -> some View {
        BeaconCard {
            HStack(spacing: Theme.Spacing.m) {
                Button {
                    deletingMedication = medication
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.coralAccent)
                        .frame(width: Theme.Spacing.xl, height: Theme.Spacing.xl)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("מחיקת \(medication.name)")

                Spacer()

                Button {
                    editingMedication = medication
                } label: {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                        HStack(spacing: Theme.Spacing.s) {
                            Text(medication.name)
                                .font(Theme.Typography.bodyEmphasis)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Image(systemName: medication.form.iconSymbol)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.Palette.sageDark)
                        }
                        Text(scheduleDescription(medication))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Text("מלאי: \(medication.stockCount)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(medication.isLowStock ? Theme.Palette.coralAccent : Theme.Palette.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("עריכת \(medication.name)")
            }
        }
    }

    private func scheduleDescription(_ medication: Medication) -> String {
        let times = medication.dosingMinutes
            .map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
        let dosage = medication.dosageDescription
        if times.isEmpty {
            return dosage.isEmpty ? "ללא לו\"ז קבוע" : dosage
        }
        let schedule = times.joined(separator: " · ")
        return dosage.isEmpty ? schedule : "\(dosage) · \(schedule)"
    }
}

/// Edit form — same fields as the intake confirmation form.
private struct MedicationEditSheet: View {
    let viewModel: ProactiveCareViewModel
    let medication: Medication
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var dosage = ""
    @State private var form: MedicationForm = .pill
    @State private var doseTimes: [Date] = []
    @State private var instructions = ""
    @State private var stockCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                    BeaconCard {
                        VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                            BeaconSectionHeader(title: "פרטי התרופה", systemImage: "pills.fill")
                            labeledField("שם התרופה") {
                                TextField("שם", text: $name)
                            }
                            labeledField("מינון") {
                                TextField("למשל: 500 מ\"ג", text: $dosage)
                            }
                            Picker("צורה", selection: $form) {
                                Text("כדור").tag(MedicationForm.pill)
                                Text("סירופ").tag(MedicationForm.syrup)
                                Text("זריקה").tag(MedicationForm.injection)
                                Text("מדבקה").tag(MedicationForm.patch)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    BeaconCard {
                        VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                            BeaconSectionHeader(title: "מתי לוקחים", systemImage: "clock.fill")
                            Stepper(value: timesPerDayBinding, in: 1...4) {
                                Text("\(doseTimes.count) פעמים ביום")
                                    .font(Theme.Typography.bodyEmphasis)
                                    .foregroundStyle(Theme.Palette.textPrimary)
                            }
                            ForEach(doseTimes.indices, id: \.self) { index in
                                HStack {
                                    DatePicker(
                                        "מנה \(index + 1)",
                                        selection: $doseTimes[index],
                                        displayedComponents: [.hourAndMinute]
                                    )
                                    .labelsHidden()
                                    .environment(\.locale, Locale(identifier: "he_IL"))
                                    Spacer()
                                    Text("מנה \(index + 1)")
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Palette.textSecondary)
                                }
                            }
                            labeledField("הוראות (לא חובה)") {
                                TextField("למשל: אחרי האוכל", text: $instructions)
                            }
                            Stepper(value: $stockCount, in: 0...200) {
                                Text("מלאי: \(stockCount) יחידות")
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Palette.textPrimary)
                            }
                        }
                    }

                    BeaconPrimaryButton(
                        title: "שמירת שינויים",
                        systemImage: "checkmark",
                        isEnabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        Task {
                            await viewModel.updateMedication(
                                medication,
                                name: name,
                                dosageDescription: dosage,
                                form: form,
                                doseTimes: doseTimes,
                                usageInstructions: instructions,
                                stockCount: stockCount
                            )
                        }
                        dismiss()
                    }
                }
                .padding(Theme.Spacing.m)
            }
            .beaconScreenBackground()
            .navigationTitle("עריכת תרופה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            name = medication.name
            dosage = medication.dosageDescription
            form = medication.form
            instructions = medication.usageInstructions ?? ""
            stockCount = medication.stockCount
            let stored = medication.dosingTimesAsDates
            doseTimes = stored.isEmpty
                ? IntakeViewModel.defaultTimes(forTimesPerDay: 1)
                : stored
        }
    }

    private var timesPerDayBinding: Binding<Int> {
        Binding(
            get: { doseTimes.count },
            set: { newCount in
                let clamped = max(1, min(4, newCount))
                if clamped > doseTimes.count {
                    let defaults = IntakeViewModel.defaultTimes(forTimesPerDay: clamped)
                    doseTimes.append(contentsOf: defaults.suffix(clamped - doseTimes.count))
                } else if clamped < doseTimes.count {
                    doseTimes = Array(doseTimes.prefix(clamped))
                }
            }
        )
    }

    @ViewBuilder
    private func labeledField(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(Theme.Typography.captionEmphasis)
                .foregroundStyle(Theme.Palette.textSecondary)
            content()
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .padding(.vertical, Theme.Layout.controlVerticalPadding)
                .padding(.horizontal, Theme.Spacing.m)
                .background(Theme.Palette.background)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
        }
    }
}

#if DEBUG
#Preview("MedicationManagerSheet") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    return MedicationManagerSheet(
        viewModel: ProactiveCareViewModel(context: container.mainContext)
    )
    .modelContainer(container)
}
#endif
