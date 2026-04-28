import SwiftUI

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var step = 0
    @State private var patientName = ""
    @State private var caregiverName = ""
    @State private var isWorking = false
    @FocusState private var focusedField: Field?

    enum Field { case patient, caregiver }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                progressDots
                    .padding(.top, Theme.Spacing.l)

                TabView(selection: $step) {
                    patientStep.tag(0)
                    caregiverStep.tag(1)
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

    // MARK: - Progress

    private var progressDots: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(0..<2) { i in
                Capsule()
                    .fill(step >= i ? Theme.Palette.deepTeal : Theme.Palette.softBlue)
                    .frame(width: step == i ? 28 : 10, height: 8)
                    .animation(.spring(duration: 0.3), value: step)
            }
        }
    }

    // MARK: - Step 1

    private var patientStep: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Palette.coralAccent)
                .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                Text("את מי אנחנו מלווים?")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("שם המטופל יוצג בכל מקום שהמשפחה תיגש לתיק שלו.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
            }

            TextField("שם המטופל", text: $patientName)
                .textContentType(.name)
                .font(Theme.Typography.body)
                .padding(Theme.Spacing.m)
                .background(Theme.Palette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip))
                .focused($focusedField, equals: .patient)
                .submitLabel(.next)
                .onSubmit { advance() }

            BeaconPrimaryButton(
                title: "המשך",
                systemImage: "arrow.left.circle.fill",
                isEnabled: !patientName.trimmingCharacters(in: .whitespaces).isEmpty
            ) {
                advance()
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.l)
        .onAppear { focusedField = .patient }
    }

    // MARK: - Step 2

    private var caregiverStep: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
            Spacer()

            Image(systemName: "person.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Palette.deepTeal)
                .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                Text("ומה השם שלך?")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("ככה בני המשפחה יראו אותך באפליקציה.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
            }

            TextField("השם שלך", text: $caregiverName)
                .textContentType(.name)
                .font(Theme.Typography.body)
                .padding(Theme.Spacing.m)
                .background(Theme.Palette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip))
                .focused($focusedField, equals: .caregiver)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }

            BeaconPrimaryButton(
                title: isWorking ? "יוצר משפחה..." : "צור משפחה והמשך",
                systemImage: "checkmark.circle.fill"
            ) {
                Task { await submit() }
            }
            .disabled(caregiverName.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            .opacity((caregiverName.trimmingCharacters(in: .whitespaces).isEmpty || isWorking) ? 0.5 : 1.0)

            Button("חזור") { withAnimation { step = 0 } }
                .font(Theme.Typography.captionEmphasis)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.l)
        .onChange(of: step) { _, newValue in
            if newValue == 1 { focusedField = .caregiver }
        }
    }

    // MARK: - Actions

    private func advance() {
        guard !patientName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation { step = 1 }
    }

    @MainActor
    private func submit() async {
        let p = patientName.trimmingCharacters(in: .whitespaces)
        let c = caregiverName.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, !c.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        await environment.createFamily(patientName: p, caregiverName: c)
    }
}

#Preview("OnboardingView") {
    OnboardingView()
        .environment(AppEnvironment(authState: .needsOnboarding))
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
