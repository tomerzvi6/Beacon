import SwiftUI
import SwiftData
import PhotosUI

/// Screenshot of an appointment SMS / printed summons → on-device OCR →
/// editable confirmation form → `ScheduleEvent` on the family calendar.
struct AppointmentIntakeSheet: View {
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
    @State private var title = ""
    // Appointments are always in the future — tomorrow 09:00 beats "now".
    @State private var startsAt = IntakeOCRService.defaultAppointmentDate()
    @State private var locationName = ""
    @State private var note = ""
    @State private var foundDate = true
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
            .navigationTitle("זימון תור")
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
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.Palette.deepTeal)
                    Text("קיבלתם SMS עם זימון?")
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("שתפו צילום מסך של ההודעה או צלמו מכתב זימון — התור ייכנס ליומן המשפחתי לבד.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            BeaconPrimaryButton(title: "בחירת צילום מסך", systemImage: "photo.on.rectangle.angled") {
                photosPickerVisible = true
            }
            BeaconSecondaryButton(title: "צילום מכתב זימון", systemImage: "camera.fill") {
                // Simulator has no camera — route to the album instead of crashing.
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showingCamera = true
                } else {
                    photosPickerVisible = true
                }
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
            Text("קוראים את הזימון…")
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
        }
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                if !didRecognizeAnything {
                    noticeCard("לא הצלחנו לקרוא את הצילום — אפשר למלא ידנית או לנסות תמונה חדה יותר.")
                } else if !foundDate {
                    noticeCard("לא זיהינו תאריך בצילום — בדקו את התאריך והשעה לפני השמירה.")
                }

                BeaconCard {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                        BeaconSectionHeader(title: "פרטי התור", systemImage: "calendar")
                        labeledField("מה התור") {
                            TextField("למשל: ד\"ר כהן — אונקולוגיה", text: $title)
                        }
                        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                            Text("מתי")
                                .font(Theme.Typography.captionEmphasis)
                                .foregroundStyle(Theme.Palette.textSecondary)
                            DatePicker(
                                "מתי",
                                selection: $startsAt,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "he_IL"))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        labeledField("איפה (לא חובה)") {
                            TextField("למשל: רמב\"ם, מרפאות חוץ", text: $locationName)
                        }
                        labeledField("הערה (לא חובה)") {
                            TextField("למשל: להביא הפניה ובדיקות דם", text: $note)
                        }
                    }
                }

                BeaconPrimaryButton(
                    title: "הוספה ליומן",
                    systemImage: "checkmark",
                    isEnabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    Task {
                        await viewModel?.saveAppointment(
                            title: title,
                            startsAt: startsAt,
                            locationName: locationName,
                            subtitle: note
                        )
                    }
                    onSaved(title.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
            }
            .padding(Theme.Spacing.m)
        }
    }

    private func noticeCard(_ message: String) -> some View {
        BeaconCard(style: .tinted(Theme.Palette.coralBackground.opacity(0.5))) {
            Text(message)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
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
        let draft = IntakeOCRService.parseAppointment(from: lines)
        title = draft.title
        startsAt = draft.startsAt
        locationName = draft.locationName
        foundDate = draft.foundDate
        didRecognizeAnything = !lines.isEmpty
        phase = .form
    }
}

#if DEBUG
#Preview("AppointmentIntakeSheet") {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            AppointmentIntakeSheet()
                .modelContainer(MockDataSeeder.makeInMemoryPreviewContainer())
        }
}
#endif
