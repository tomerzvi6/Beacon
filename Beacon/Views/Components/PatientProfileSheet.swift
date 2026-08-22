import SwiftUI

struct PatientProfileSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingPermissions = false
    @State private var demoDataEnabled = MockDataSeeder.isDemoDataEnabled
    @State private var showingClearDemoConfirm = false

    private var patient: Patient { environment.patient }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    headerCard
                    #if DEBUG
                    if environment.currentUser.hasFullAccess {
                        modeControlCard
                    }
                    #endif
                    emergencyCard
                    medicalCard
                }
                .padding(Theme.Spacing.m)
            }
            .beaconScreenBackground()
            .navigationTitle("כרטיס רפואי")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגור") { dismiss() }
                }
                if environment.canManagePermissions {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("ניהול גישה") { showingPermissions = true }
                    }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(isPresented: $showingPermissions) {
            PermissionsSettingsView()
                .environment(environment)
        }
    }

    private var headerCard: some View {
        BeaconCard {
            VStack(spacing: Theme.Spacing.m) {
                BeaconAvatar(
                    systemImage: patient.avatarSymbol,
                    diameter: 80,
                    tint: Theme.Palette.softBlue,
                    foreground: Theme.Palette.deepTeal
                )
                Text(patient.displayName)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("גיל \(patient.age)")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)

                HStack(spacing: Theme.Spacing.xs) {
                    Text(patient.todaysWellness.emoji)
                    Text("היום: \(patient.todaysWellness.displayLabel(for: patient.gender))")
                        .font(Theme.Typography.captionEmphasis)
                }
                .padding(.vertical, Theme.Layout.compactPillVerticalPadding)
                .padding(.horizontal, Theme.Spacing.m)
                .background(Theme.Palette.sage.opacity(0.5))
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var emergencyCard: some View {
        BeaconCard(style: .tinted(Theme.Palette.coralBackground.opacity(0.5))) {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                HStack {
                    Spacer()
                    Label("מידע לחירום", systemImage: "cross.case.fill")
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.coralAccent)
                }

                infoRow(label: "סוג דם", value: patient.bloodType, icon: "drop.fill")

                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    HStack {
                        Spacer()
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(Theme.Palette.coralAccent)
                        Text("אלרגיות:")
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    Text(patient.allergies.isEmpty ? "לא ידוע / לא הוזן" : patient.allergies.joined(separator: ", "))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.coralAccent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let emergencyCallURL {
                    Link(destination: emergencyCallURL) {
                        emergencyCallButtonContent
                    }
                } else {
                    emergencyCallButtonContent
                        .opacity(0.65)
                        .accessibilityLabel("אין מספר טלפון תקין לאיש קשר לחירום")
                }
            }
        }
    }

    private var emergencyCallURL: URL? {
        let phone = patient.emergencyContactPhone.filter { $0.isNumber || $0 == "+" }
        guard !phone.isEmpty else { return nil }
        return URL(string: "tel:\(phone)")
    }

    private var emergencyCallButtonContent: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "phone.fill")
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text("התקשר ל-\(patient.emergencyContactName)")
                    .font(Theme.Typography.bodyEmphasis)
                Text(patient.emergencyContactPhone.isEmpty ? "לא הוגדר מספר" : patient.emergencyContactPhone)
                    .font(Theme.Typography.caption)
                    .opacity(0.85)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.vertical, Theme.Layout.prominentControlVerticalPadding)
        .padding(.horizontal, Theme.Spacing.m)
        .background(Theme.Palette.coralAccent)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
    }

    private var medicalCard: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                BeaconSectionHeader(title: "צוות רפואי", systemImage: "stethoscope")
                infoRow(label: "רופא ראשי", value: patient.primaryDoctor, icon: "person.text.rectangle")
                infoRow(label: "בית חולים", value: patient.primaryHospital, icon: "building.2")
                infoRow(label: "קופת חולים", value: patient.healthFund, icon: "cross.case")
            }
        }
    }

    /// Single control panel for the three testable states — keeps the
    /// tester from hunting through two separate toggles. Shows the live
    /// current state up top, then the version switch and the demo switch.
    private var modeControlCard: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                BeaconSectionHeader(title: "מצב האפליקציה (לבדיקה)", systemImage: "slider.horizontal.3")

                // Live current-state banner
                HStack(spacing: Theme.Spacing.s) {
                    Text(currentModeSummary)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.deepTeal)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Image(systemName: environment.dataSourceMode.iconSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.deepTeal)
                }
                .padding(Theme.Spacing.s)
                .frame(maxWidth: .infinity)
                .background(Theme.Palette.softBlue.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))

                // Version switch
                Text("גרסה")
                    .font(Theme.Typography.captionEmphasis)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Picker("גרסה", selection: Binding(
                    get: { environment.dataSourceMode },
                    set: { environment.dataSourceMode = $0 }
                )) {
                    ForEach(DataSourceMode.allCases) { mode in
                        Text(mode.displayLabel).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(environment.dataSourceMode.explanation)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Divider()

                // Demo data switch
                Text("נתוני הדגמה")
                    .font(Theme.Typography.captionEmphasis)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(demoDataEnabled
                     ? "פעיל — משפחה, תרופות, יומן, פיד ומטפלת לדוגמה."
                     : "כבוי — האפליקציה נקייה, כמו אצל משפחה אמיתית.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if demoDataEnabled {
                    BeaconSecondaryButton(title: "ניקוי נתוני ההדגמה", systemImage: "trash") {
                        showingClearDemoConfirm = true
                    }
                } else {
                    BeaconSecondaryButton(title: "טעינת נתוני הדגמה", systemImage: "sparkles") {
                        MockDataSeeder.enableDemoData(in: modelContext)
                        demoDataEnabled = true
                        environment.contentRevision += 1
                    }
                }
            }
        }
        .confirmationDialog(
            "לנקות את כל נתוני ההדגמה?",
            isPresented: $showingClearDemoConfirm,
            titleVisibility: .visible
        ) {
            Button("ניקוי הכל", role: .destructive) {
                MockDataSeeder.disableDemoData(in: modelContext)
                demoDataEnabled = false
                environment.contentRevision += 1
            }
            Button("ביטול", role: .cancel) { }
        } message: {
            Text("כל התרופות, המשימות, הפוסטים והמטפל/ת שנטענו להדגמה יימחקו. פעולה זו מוחקת גם רשומות שהוספתם ידנית באפליקציה.")
        }
    }

    private var currentModeSummary: String {
        let version = environment.dataSourceMode.displayLabel
        let demo = demoDataEnabled ? "דמו פעיל" : "נקי"
        return "מצב נוכחי: \(version) · \(demo)"
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Text(value.isEmpty ? "לא הוגדר" : value)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(value.isEmpty ? Theme.Palette.textSecondary : Theme.Palette.textPrimary)
            Spacer()
            HStack(spacing: Theme.Spacing.xs) {
                Text(label)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }
}

#Preview("PatientProfileSheet") {
    PatientProfileSheet()
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
}
