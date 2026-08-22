import SwiftUI
import SwiftData

/// Family-side sheet: activate/deactivate the home-caregiver layer and
/// edit the caregiver's name, title and language.
struct CaregiverSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: CaregiverLayerViewModel

    @State private var name: String = ""
    @State private var relationTitle: String = "מטפל/ת סיעודי/ת"
    @State private var language: CaregiverLanguage = .english
    @State private var showingDeactivateConfirm = false
    @State private var showingReportScreen = false

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.isCaregiverLayerActive {
                    activeSection
                }
                if !viewModel.isCaregiverLayerActive {
                    explanationSection
                }
                detailsSection
                if viewModel.isCaregiverLayerActive {
                    reportEntrySection
                    deactivateSection
                }
            }
            .navigationTitle("מטפל/ת בבית")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגור") { dismiss() }
                }
            }
            .onAppear(perform: loadCurrentValues)
            .fullScreenCover(isPresented: $showingReportScreen) {
                CaregiverReportView(viewModel: viewModel)
            }
            .confirmationDialog(
                "לכבות את שכבת המטפל/ת?",
                isPresented: $showingDeactivateConfirm,
                titleVisibility: .visible
            ) {
                Button("כבה את השכבה", role: .destructive) {
                    Task { await viewModel.deactivateCaregiver() }
                    dismiss()
                }
                Button("ביטול", role: .cancel) { }
            } message: {
                Text("הדיווחים הקיימים נשמרים. אפשר להפעיל מחדש בכל רגע.")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    /// Answers "who sees what, does the aide need their own login" — a
    /// rushed first-time user is likely to tap "activate" before ever
    /// reading a footer, so this needs to sit before the form, not after it.
    private var explanationSection: some View {
        Section {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Palette.deepTeal)
                Text("המטפל/ת מדווח/ת דרך מסך פשוט בשפה שלו/ה, וביקון מסכמת לעברית עבור המשפחה. למטפל/ת אין גישה לתיק הרפואי או לשאר האפליקציה — אין למטפל/ת חשבון או התחברות משלו/ה.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .listRowBackground(Theme.Palette.softBlue.opacity(0.2))
    }

    private var activeSection: some View {
        Section {
            HStack(spacing: Theme.Spacing.m) {
                BeaconAvatar(
                    systemImage: "figure.2.arms.open",
                    tint: Theme.Palette.sage.opacity(0.5),
                    foreground: Theme.Palette.sageDark
                )
                VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                    Text(viewModel.activeCaregiver?.displayName ?? "")
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("שכבת המטפל/ת פעילה · \(language.hebrewName)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                BeaconBadge(text: "פעיל", tone: .sage, leadingDot: true)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("שם המטפל/ת", text: $name)
            TextField("תפקיד (למשל: מטפלת סיעודית)", text: $relationTitle)
            Picker("שפת המטפל/ת", selection: $language) {
                ForEach(CaregiverLanguage.allCases) { lang in
                    Text("\(lang.nativeName) · \(lang.hebrewName)").tag(lang)
                }
            }
            BeaconPrimaryButton(
                title: viewModel.isCaregiverLayerActive ? "שמור שינויים" : "הפעל מטפל/ת בבית",
                systemImage: viewModel.isCaregiverLayerActive ? "checkmark" : "plus",
                isEnabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                let wasActive = viewModel.isCaregiverLayerActive
                Task {
                    await viewModel.activateCaregiver(
                        name: name,
                        relationTitle: relationTitle,
                        language: language
                    )
                    if !wasActive { dismiss() }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            Text("פרטי המטפל/ת")
        }
    }

    private var reportEntrySection: some View {
        Section {
            Button {
                showingReportScreen = true
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Palette.deepTeal)
                        .frame(
                            width: Theme.Layout.statusStripIconSize,
                            height: Theme.Layout.statusStripIconSize
                        )
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                        Text("פתח מסך דיווח למטפל/ת")
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.deepTeal)
                        Text("מסך ממוקד בשפת המטפל/ת — מסרו את המכשיר לדיווח")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("דיווח")
        }
    }

    private var deactivateSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeactivateConfirm = true
            } label: {
                Label("כבה את שכבת המטפל/ת", systemImage: "person.crop.circle.badge.minus")
            }
        } footer: {
            Text("כיבוי מסיר את הכרטיס מהדאשבורד. הדיווחים שנשמרו לא נמחקים.")
        }
    }

    private func loadCurrentValues() {
        guard let caregiver = viewModel.activeCaregiver else { return }
        name = caregiver.displayName
        relationTitle = caregiver.relationTitle
        language = caregiver.preferredLanguage
    }
}

#Preview("CaregiverSetupSheet") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    return CaregiverSetupSheet(
        viewModel: CaregiverLayerViewModel(context: container.mainContext)
    )
    .modelContainer(container)
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
