import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var nonce: (raw: String, hashed: String) = AuthService.makeNonce()
    @State private var isWorking = false
    @State private var showDevSheet = false
    @State private var openedLegalDocument: LegalDocument? = nil

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Palette.deepTeal, Theme.Palette.deepTealDark],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                VStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Beacon")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("מרכז שליטה משפחתי")
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("לטיפול מאורגן, יחד")
                        .font(Theme.Typography.body)
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                VStack(spacing: Theme.Spacing.m) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = nonce.hashed
                    } onCompletion: { result in
                        Task { await handleApple(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.button, style: .continuous))
                    .accessibilityLabel("התחבר עם Apple")

                    if GoogleSignInService.hasClientID {
                        GoogleSignInRow(isWorking: isWorking) {
                            Task { await handleGoogle() }
                        }
                    }

                    #if DEBUG
                    Button {
                        showDevSheet = true
                    } label: {
                        Text("התחברות עם אימייל (למפתחים)")
                            .font(Theme.Typography.captionEmphasis)
                            .foregroundStyle(.white.opacity(0.75))
                            .underline()
                    }
                    .padding(.top, Theme.Spacing.s)
                    #endif
                }
                .padding(.horizontal, Theme.Spacing.l)

                if isWorking {
                    ProgressView().tint(.white)
                }

                if let msg = environment.authErrorMessage {
                    Text(msg)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.coralAccent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.vertical, Theme.Spacing.s)
                        .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: Theme.CornerRadius.chip))
                }

                if let msg = environment.signUpSuccessMessage {
                    Text(msg)
                        .font(Theme.Typography.captionEmphasis)
                        .foregroundStyle(Theme.Palette.sageDark)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.vertical, Theme.Spacing.s)
                        .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: Theme.CornerRadius.chip))
                }

                VStack(spacing: Theme.Spacing.xxs) {
                    Text("גרסת פיילוט — מומלץ לשמור עותק של מסמכים חשובים גם מחוץ לאפליקציה.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, Theme.Spacing.xxs)
                    Text("ההתחברות מהווה הסכמה ל:")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                    HStack(spacing: Theme.Spacing.s) {
                        Button("תנאי השימוש") { openedLegalDocument = .termsOfUse }
                        Text("·").foregroundStyle(.white.opacity(0.5))
                        Button("מדיניות הפרטיות") { openedLegalDocument = .privacyPolicy }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.l)
            }
        }
        .sheet(item: $openedLegalDocument) { document in
            LegalTextSheet(document: document)
        }
        .sheet(isPresented: $showDevSheet) {
            DevEmailSignInSheet()
                .environment(environment)
        }
    }

    @MainActor
    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        isWorking = true
        defer { isWorking = false }
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                environment.authErrorMessage = AuthError.invalidAppleCredential.errorDescription
                return
            }
            await environment.signInWithApple(credential: credential, rawNonce: nonce.raw)
            // Refresh nonce for next attempt
            nonce = AuthService.makeNonce()
        case .failure(let error):
            // User-cancelled errors should not be shown
            let nsError = error as NSError
            if nsError.code != ASAuthorizationError.canceled.rawValue {
                // The raw SDK error is an English NSError description with
                // technical codes — replace it with something a Hebrew-
                // speaking, non-technical user can actually act on.
                environment.authErrorMessage = "ההתחברות לא הצליחה. בדוק/י את החיבור לאינטרנט ונסה/י שוב."
            }
        }
    }

    @MainActor
    private func handleGoogle() async {
        isWorking = true
        defer { isWorking = false }
        await environment.signInWithGoogle()
    }
}

// MARK: - Google Sign-In button

/// Per Google's branding guidelines, the button uses a white background,
/// the official "G" logo on the leading edge, and the text
/// "Sign in with Google" — we keep the Hebrew label "המשך עם Google"
/// alongside the SF Symbol fallback for the logo, accepting that a fully
/// branded build needs the official PNG asset shipped from Google's
/// branding kit (added in Phase 8 polish).
private struct GoogleSignInRow: View {
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Palette.googleBlue)
                Text("המשך עם Google")
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(.black.opacity(0.85))
                Spacer()
                if isWorking { ProgressView() }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.button, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.button, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("המשך עם Google")
        .disabled(isWorking)
    }
}

// MARK: - Email/Password development sheet

private struct DevEmailSignInSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var mode: Mode = .signIn
    @State private var isWorking = false

    enum Mode: String, CaseIterable, Identifiable {
        case signIn, signUp
        var id: String { rawValue }
        var label: String { self == .signIn ? "התחברות" : "הרשמה" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("מצב", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if mode == .signUp {
                        TextField("שם מלא", text: $displayName)
                            .textContentType(.name)
                    }
                    TextField("אימייל", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("סיסמה (לפחות 6 תווים)", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking {
                                ProgressView()
                            } else {
                                Text(mode.label).bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(email.isEmpty || password.count < 6 || isWorking)
                }

                if let msg = environment.authErrorMessage {
                    Section {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.coralAccent)
                    }
                }
                if let msg = environment.signUpSuccessMessage {
                    Section {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.sageDark)
                    }
                }
            }
            .navigationTitle("התחברות עם אימייל")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגור") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    @MainActor
    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        switch mode {
        case .signIn:
            await environment.signInWithEmail(email: email, password: password)
        case .signUp:
            await environment.signUpWithEmail(email: email, password: password, displayName: displayName)
        }
        // Keep the sheet open when Supabase requires email confirmation.
        if environment.authErrorMessage == nil && environment.signUpSuccessMessage == nil {
            dismiss()
        }
    }
}

#Preview("LoginView") {
    LoginView()
        .environment(AppEnvironment(authState: .unauthenticated))
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
