import SwiftUI

/// Entry point for someone a relative invited: they type the six-digit code
/// instead of creating a family of their own.
///
/// Without this screen an invited caregiver has no way in — signing in always
/// produced a brand-new empty household, so relatives could never end up
/// looking at the same medical file.
struct JoinWithCodeSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isJoining = false
    @State private var errorMessage: String?
    @FocusState private var codeFieldFocused: Bool

    private var isCodeComplete: Bool { code.count == 6 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                    Spacer(minLength: Theme.Spacing.m)

                    Image(systemName: "person.2.badge.key.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(Theme.Palette.deepTeal)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                        Text("הצטרפות למשפחה קיימת")
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("הזן/י את הקוד בן 6 הספרות שקיבלת מבן המשפחה שהזמין אותך.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    // Digits stay left-to-right so they don't reorder inside
                    // the app's RTL layout.
                    TextField("000000", text: $code)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .environment(\.layoutDirection, .leftToRight)
                        .focused($codeFieldFocused)
                        .padding(.vertical, Theme.Spacing.m)
                        .background(Theme.Palette.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
                        .onChange(of: code) { _, newValue in
                            let digits = newValue.filter(\.isNumber)
                            code = String(digits.prefix(6))
                            if errorMessage != nil { errorMessage = nil }
                        }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.coralAccent)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    BeaconPrimaryButton(
                        title: isJoining ? "מצטרף/ת…" : "הצטרפות",
                        systemImage: "checkmark.circle.fill",
                        isEnabled: isCodeComplete && !isJoining
                    ) {
                        Task { await join() }
                    }

                    Text("הקוד מצרף אותך לתיק הרפואי של המשפחה. ההרשאות שלך נקבעות על ידי מי שהזמין אותך, וניתן לשנות אותן בכל שלב.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Spacer(minLength: Theme.Spacing.l)
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
            .beaconScreenBackground()
            .navigationTitle("הצטרפות")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .task { codeFieldFocused = true }
    }

    private func join() async {
        isJoining = true
        errorMessage = nil
        let joined = await environment.joinHousehold(code: code)
        isJoining = false
        if joined {
            dismiss()
        } else {
            errorMessage = environment.authErrorMessage ?? "ההצטרפות נכשלה. בדוק/י את הקוד ונסה/י שוב."
            code = ""
            codeFieldFocused = true
        }
    }
}

#Preview("JoinWithCodeSheet") {
    JoinWithCodeSheet()
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
