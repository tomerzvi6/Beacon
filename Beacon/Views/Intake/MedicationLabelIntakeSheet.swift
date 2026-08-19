import SwiftUI
import SwiftData
import PhotosUI

/// Photo of a medication box / pharmacy label → on-device OCR → editable
/// confirmation form → `Medication` + dose schedule in SwiftData.
struct MedicationLabelIntakeSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case pickSource
        case recognizing
        case form
    }

    @State private var phase: Phase = .pickSource
    @State private var showingCamera = false
    @State private var photosPickerVisible = false
    @State private var photosSelection: PhotosPickerItem? = nil

    // Editable draft fields
    @State private var name = ""
    @State private var dosage = ""
    @State private var form: MedicationForm = .pill
    @State private var doseTimes: [Date] = IntakeViewModel.defaultTimes(forTimesPerDay: 1)
    @State private var instructions = ""
    @State private var stockCount = 14
    @State private var didRecognizeAnything = true

    @State private var viewModel: IntakeViewModel? = nil
    var onSaved: (String) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pickSource: sourcePicker
                case .recognizing: recognizingView
                case .form: formView
                }
            }
            .beaconScreenBackground()
            .navigationTitle("קופסת תרופה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            if viewModel == nil { viewModel = IntakeViewModel(context: context) }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(
                onImage: { image in
                    showingCamera = false
                    Task { await recognize(image) }
                },
                onCancel: { showingCamera = false }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $photosPickerVisible, selection: $photosSelection, matching: .images)
        .onChange(of: photosSelection) { _, newItem in
            guard let newItem else { return }
            Task {
                photosSelection = nil
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                await recognize(image)
            }
        }
    }

    // MARK: - Phases

    private var sourcePicker: some View {
        VStack(spacing: Theme.Spacing.m) {
            BeaconCard {
                VStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.Palette.sageDark)
                    Text("צלמו את מדבקת בית המרקחת")
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("על המדבקה כתוב הכל — שם, מינון ותדירות. ביקון יקרא אותה בשבילכם.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            BeaconPrimaryButton(title: "צילום המדבקה", systemImage: "camera.fill") {
                // Simulator has no camera — route to the album instead of crashing.
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showingCamera = true
                } else {
                    photosPickerVisible = true
                }
            }
            BeaconSecondaryButton(title: "בחירה מהאלבום", systemImage: "photo.on.rectangle.angled") {
                photosPickerVisible = true
            }
            BeaconSecondaryButton(title: "הזנה ידנית בלי צילום", systemImage: "square.and.pencil") {
                didRecognizeAnything = true
                phase = .form
            }
            Spacer()
        }
        .padding(Theme.Spacing.l)
    }

    private var recognizingView: some View {
        VStack(spacing: Theme.Spacing.m) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(Theme.Palette.deepTeal)
            Text("קוראים את המדבקה…")
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
        }
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                if !didRecognizeAnything {
                    BeaconCard(style: .tinted(Theme.Palette.coralBackground.opacity(0.5))) {
                        Text("לא הצלחנו לקרוא את המדבקה — אפשר למלא ידנית או לנסות צילום חד יותר.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                BeaconCard {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                        BeaconSectionHeader(title: "פרטי התרופה", systemImage: "pills.fill")
                        labeledField("שם התרופה") {
                            TextField("למשל: Acamol", text: $name)
                        }
                        labeledField("מינון") {
                            TextField("למשל: 500 מ\"ג", text: $dosage)
                        }
                        labeledField("צורה") {
                            Picker("צורה", selection: $form) {
                                Text("כדור").tag(MedicationForm.pill)
                                Text("סירופ").tag(MedicationForm.syrup)
                                Text("זריקה").tag(MedicationForm.injection)
                                Text("מדבקה").tag(MedicationForm.patch)
                            }
                            .pickerStyle(.segmented)
                        }
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
                    title: "הוספה לתרופות",
                    systemImage: "checkmark",
                    isEnabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    Task {
                        await viewModel?.saveMedication(
                            name: name,
                            dosageDescription: dosage,
                            form: form,
                            doseTimes: doseTimes,
                            usageInstructions: instructions,
                            stockCount: stockCount
                        )
                    }
                    onSaved(name.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
            }
            .padding(Theme.Spacing.m)
        }
    }

    /// Stepper drives the count; existing user-edited times survive resizes.
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

    // MARK: - OCR

    @MainActor
    private func recognize(_ image: UIImage) async {
        phase = .recognizing
        let lines = await IntakeOCRService.recognizeText(in: image)
        let draft = IntakeOCRService.parseMedicationLabel(from: lines)
        name = draft.name
        dosage = draft.dosageDescription
        doseTimes = IntakeViewModel.defaultTimes(
            forTimesPerDay: max(1, min(4, draft.timesPerDay))
        )
        instructions = draft.usageInstructions
        didRecognizeAnything = !lines.isEmpty
        phase = .form
    }
}

#if DEBUG
#Preview("MedicationLabelIntakeSheet") {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            MedicationLabelIntakeSheet()
                .modelContainer(MockDataSeeder.makeInMemoryPreviewContainer())
        }
}
#endif
