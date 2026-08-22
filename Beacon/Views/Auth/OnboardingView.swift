import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var step = 0
    @State private var patientName = ""
    @State private var patientAge = ""
    @State private var patientGender: PatientGender = .male
    @State private var primaryHospital = ""
    @State private var primaryDoctor = ""
    @State private var healthFund = ""
    @State private var bloodType = ""
    @State private var allergies = ""
    @State private var emergencyContactName = ""
    @State private var emergencyContactPhone = ""
    @State private var patientVerificationEmail = ""
    @State private var hasIdPhotoForVerification = false
    @State private var caregiverName = ""
    @State private var isWorking = false
    @State private var showingJoinSheet = false
    @FocusState private var focusedField: Field?

    private let totalSteps = 5

    enum Field {
        case patientName
        case patientAge
        case primaryHospital
        case primaryDoctor
        case healthFund
        case bloodType
        case allergies
        case emergencyContactName
        case emergencyContactPhone
        case patientVerificationEmail
        case caregiverName
    }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                progressDots
                    .padding(.top, Theme.Spacing.l)

                TabView(selection: $step) {
                    modeStep.tag(0)
                    patientStep.tag(1)
                    medicalInfoStep.tag(2)
                    verificationStep.tag(3)
                    caregiverStep.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: step)

                if let msg = environment.authErrorMessage {
                    Text(msg)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.coralAccent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.bottom, Theme.Spacing.s)
                }
            }
        }
    }

    private var progressDots: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(step >= index ? Theme.Palette.deepTeal : Theme.Palette.softBlue)
                    .frame(
                        width: step == index ? Theme.Spacing.l + Theme.Spacing.xs : Theme.Spacing.s + Theme.Spacing.xs,
                        height: Theme.Spacing.s
                    )
                    .animation(.spring(duration: 0.3), value: step)
            }
        }
    }

    private var modeStep: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                Spacer(minLength: Theme.Spacing.xl)

                stepIcon("arrow.triangle.2.circlepath", tint: Theme.Palette.deepTeal)

                stepHeader(
                    title: "איך יגיע המידע הרפואי?",
                    subtitle: "אפשר להחליף את זה בכל שלב מהכרטיס הרפואי באפליקציה."
                )

                VStack(spacing: Theme.Spacing.m) {
                    ForEach(DataSourceMode.allCases) { mode in
                        modeOptionRow(mode)
                    }
                }

                BeaconPrimaryButton(title: "המשך", systemImage: "arrow.left.circle.fill") {
                    withAnimation { step = 1 }
                }

                // Someone invited by a relative must not create a second
                // family — that would leave them with their own empty vault
                // instead of the one they were invited to.
                Button {
                    showingJoinSheet = true
                } label: {
                    Text("הוזמנת על ידי בן משפחה? הזן/י קוד הצטרפות")
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.deepTeal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Layout.controlVerticalPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .sheet(isPresented: $showingJoinSheet) {
            JoinWithCodeSheet()
                .environment(environment)
        }
    }

    private func modeOptionRow(_ mode: DataSourceMode) -> some View {
        let isSelected = environment.dataSourceMode == mode
        return Button {
            environment.dataSourceMode = mode
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.Palette.deepTeal : Theme.Palette.textSecondary)
                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    Text(mode.displayLabel)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(mode.explanation)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
                Spacer()
                Image(systemName: mode.iconSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Palette.deepTeal)
            }
            .padding(Theme.Spacing.m)
            .background(isSelected ? Theme.Palette.softBlue.opacity(0.35) : Theme.Palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Palette.deepTeal : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var patientStep: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                Spacer(minLength: Theme.Spacing.xl)

                stepIcon("heart.fill", tint: Theme.Palette.coralAccent)

                stepHeader(
                    title: "יצירת פרופיל חולה",
                    subtitle: "אפשר לנהל מטופל/ת אחד/ת כרגע. תמיד אפשר לעדכן את הפרטים האלה מאוחר יותר."
                )

                inputField(
                    title: "שם המטופל/ת",
                    text: $patientName,
                    prompt: "לדוגמה: יוסף כהן",
                    field: .patientName,
                    contentType: .name,
                    submitLabel: .next
                ) {
                    focusedField = .patientAge
                }

                inputField(
                    title: "גיל",
                    text: $patientAge,
                    prompt: "לדוגמה: 71",
                    field: .patientAge,
                    keyboard: .numberPad,
                    submitLabel: .next
                ) {
                    advanceFromPatient()
                }

                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    Text("מין")
                        .font(Theme.Typography.captionEmphasis)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Picker("מין", selection: $patientGender) {
                        ForEach(PatientGender.allCases) { g in
                            Text(g.displayLabel).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                BeaconPrimaryButton(
                    title: "המשך לפרטים רפואיים",
                    systemImage: "arrow.left.circle.fill",
                    isEnabled: !trimmed(patientName).isEmpty
                ) {
                    advanceFromPatient()
                }

                Button("חזור") { withAnimation { step = 0 } }
                    .font(Theme.Typography.captionEmphasis)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .onChange(of: step) { _, newValue in
            if newValue == 1 { focusedField = .patientName }
        }
    }

    private var medicalInfoStep: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                Spacer(minLength: Theme.Spacing.xl)

                stepIcon("cross.case.fill", tint: Theme.Palette.deepTeal)

                stepHeader(
                    title: "מידע שימושי לטיפול",
                    subtitle: "לא נוסיף אבחנה בשלב הזה. נשמור רק פרטים שעוזרים למשפחה לפעול מהר. כל השדות כאן הם לא חובה — אפשר להמשיך גם בלעדיהם."
                )

                inputField(
                    title: "בית חולים (לא חובה)",
                    text: $primaryHospital,
                    prompt: "לדוגמה: שיבא — רק אם יש תיק בבית חולים ספציפי",
                    field: .primaryHospital,
                    submitLabel: .next
                ) {
                    focusedField = .primaryDoctor
                }

                inputField(
                    title: "רופא/ה ראשי/ת (לא חובה)",
                    text: $primaryDoctor,
                    prompt: "לדוגמה: ד״ר לוי",
                    field: .primaryDoctor,
                    submitLabel: .next
                ) {
                    focusedField = .healthFund
                }

                inputField(
                    title: "קופת חולים (לא חובה)",
                    text: $healthFund,
                    prompt: "לדוגמה: כללית, מכבי, מאוחדת, לאומית",
                    field: .healthFund,
                    submitLabel: .next
                ) {
                    focusedField = .bloodType
                }

                inputField(
                    title: "סוג דם (לא חובה)",
                    text: $bloodType,
                    prompt: "לדוגמה: A+",
                    field: .bloodType,
                    submitLabel: .next
                ) {
                    focusedField = .allergies
                }

                inputField(
                    title: "אלרגיות (לא חובה)",
                    text: $allergies,
                    prompt: "להפריד בפסיקים, אם יש",
                    field: .allergies,
                    submitLabel: .next
                ) {
                    focusedField = .emergencyContactName
                }

                inputField(
                    title: "איש קשר לחירום (לא חובה)",
                    text: $emergencyContactName,
                    prompt: "שם מלא",
                    field: .emergencyContactName,
                    contentType: .name,
                    submitLabel: .next
                ) {
                    focusedField = .emergencyContactPhone
                }

                inputField(
                    title: "טלפון חירום (לא חובה)",
                    text: $emergencyContactPhone,
                    prompt: "050-0000000",
                    field: .emergencyContactPhone,
                    contentType: .telephoneNumber,
                    keyboard: .phonePad,
                    submitLabel: .next
                ) {
                    withAnimation { step = 3 }
                }

                HStack(spacing: Theme.Spacing.m) {
                    BeaconSecondaryButton(title: "חזור") {
                        withAnimation { step = 1 }
                    }
                    BeaconPrimaryButton(title: "המשך", systemImage: "arrow.left.circle.fill") {
                        withAnimation { step = 3 }
                    }
                }

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .onChange(of: step) { _, newValue in
            if newValue == 2 { focusedField = .primaryHospital }
        }
    }

    private var caregiverStep: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                Spacer(minLength: Theme.Spacing.xl)

                stepIcon("person.fill", tint: Theme.Palette.sageDark)

                stepHeader(
                    title: "ומי מנהל/ת את הטיפול?",
                    subtitle: "עד שהמטופל יאשר, התיק יוגדר כתיק ממתין ולא יפתח מידע רפואי רגיש."
                )

                inputField(
                    title: "השם שלך",
                    text: $caregiverName,
                    prompt: "לדוגמה: רונית",
                    field: .caregiverName,
                    contentType: .name,
                    submitLabel: .go
                ) {
                    Task { await submit() }
                }

                BeaconPrimaryButton(
                    title: isWorking ? "יוצר פרופיל חולה..." : "צור פרופיל חולה והמשך",
                    systemImage: "checkmark.circle.fill",
                    isEnabled: !trimmed(caregiverName).isEmpty && !trimmed(patientName).isEmpty && isVerificationReady && !isWorking
                ) {
                    Task { await submit() }
                }

                Button("חזור") { withAnimation { step = 3 } }
                    .font(Theme.Typography.captionEmphasis)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .onChange(of: step) { _, newValue in
            if newValue == 4 { focusedField = .caregiverName }
        }
    }

    private var verificationStep: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                Spacer(minLength: Theme.Spacing.xl)

                stepIcon("checkmark.shield.fill", tint: Theme.Palette.deepTeal)

                stepHeader(
                    title: "אישור המטופל",
                    subtitle: "כדי לשמור על סודיות רפואית, נאסוף מייל לאימות ואישור שקיים צילום תעודת זהות. לאחר יצירת התיק תישלח למטופל/ת בקשה נפרדת לאישור הבעלות."
                )

                inputField(
                    title: "מייל המטופל/ת לאימות",
                    text: $patientVerificationEmail,
                    prompt: "patient@example.com",
                    field: .patientVerificationEmail,
                    contentType: .emailAddress,
                    keyboard: .emailAddress,
                    submitLabel: .next
                ) {
                    focusedField = .caregiverName
                }

                Button {
                    hasIdPhotoForVerification.toggle()
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: hasIdPhotoForVerification ? "checkmark.circle.fill" : "camera.viewfinder")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(hasIdPhotoForVerification ? Theme.Palette.deepTeal : Theme.Palette.textSecondary)
                            .frame(width: Theme.Layout.statusStripIconSize, height: Theme.Layout.statusStripIconSize)
                            .background(Theme.Palette.softBlue.opacity(0.4))
                            .clipShape(Circle())
                        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                            Text(hasIdPhotoForVerification ? "צילום תעודת זהות סומן" : "סמן שקיים צילום תעודת זהות")
                                .font(Theme.Typography.bodyEmphasis)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Text("ב-MVP זה סימון מקומי בלבד; בהמשך זה יהיה העלאה מאובטחת.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(Theme.Spacing.m)
                    .background(Theme.Palette.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip))
                }
                .buttonStyle(.plain)

                HStack(spacing: Theme.Spacing.m) {
                    BeaconSecondaryButton(title: "חזור") {
                        withAnimation { step = 2 }
                    }
                    BeaconPrimaryButton(
                        title: "המשך",
                        systemImage: "arrow.left.circle.fill",
                        isEnabled: isVerificationReady
                    ) {
                        withAnimation { step = 4 }
                    }
                }

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .onChange(of: step) { _, newValue in
            if newValue == 3 { focusedField = .patientVerificationEmail }
        }
    }

    private func stepIcon(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 56))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
    }

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
            Text(subtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func inputField(
        title: String,
        text: Binding<String>,
        prompt: String,
        field: Field,
        contentType: UITextContentType? = nil,
        keyboard: UIKeyboardType = .default,
        submitLabel: SubmitLabel = .next,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.captionEmphasis)
                .foregroundStyle(Theme.Palette.textSecondary)
            TextField(prompt, text: text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .font(Theme.Typography.body)
                .multilineTextAlignment(.trailing)
                .padding(Theme.Spacing.m)
                .background(Theme.Palette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip))
                .focused($focusedField, equals: field)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
        }
    }

    private func advanceFromPatient() {
        guard !trimmed(patientName).isEmpty else { return }
        withAnimation { step = 2 }
    }

    private var isVerificationReady: Bool {
        trimmed(patientVerificationEmail).contains("@") && hasIdPhotoForVerification
    }

    @MainActor
    private func submit() async {
        let patient = trimmed(patientName)
        let caregiver = trimmed(caregiverName)
        guard !patient.isEmpty else {
            // Reachable if the swipeable TabView skipped patientStep without
            // the "המשך" button's own check — otherwise the button above is
            // already disabled and this never fires silently.
            environment.authErrorMessage = "חסר שם המטופל/ת — חזרו לשלב הראשון והזינו אותו."
            withAnimation { step = 1 }
            return
        }
        guard !caregiver.isEmpty, isVerificationReady else { return }
        isWorking = true
        defer { isWorking = false }
        await environment.createFamily(
            patientProfile: PatientProfileDraft(
                displayName: patient,
                age: Int(trimmed(patientAge)),
                gender: patientGender,
                primaryDoctor: trimmed(primaryDoctor),
                primaryHospital: trimmed(primaryHospital),
                healthFund: trimmed(healthFund),
                bloodType: trimmed(bloodType),
                allergies: allergies
                    .split(separator: ",")
                    .map { trimmed(String($0)) }
                    .filter { !$0.isEmpty },
                emergencyContactName: trimmed(emergencyContactName),
                emergencyContactPhone: trimmed(emergencyContactPhone)
            ),
            caregiverName: caregiver,
            approvalDraft: PatientApprovalDraft(
                verificationEmail: trimmed(patientVerificationEmail),
                hasIdPhotoForVerification: hasIdPhotoForVerification
            )
        )
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview("OnboardingView") {
    OnboardingView()
        .environment(AppEnvironment(authState: .needsOnboarding))
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
