import SwiftUI

struct ComposePostCard: View {
    @Binding var text: String
    @Binding var status: FeedPostStatus?
    var currentUser: FamilyMember
    var patient: Patient
    var onPublish: () -> Void
    @Binding var publishAsPatient: Bool

    @State private var showingStatusPicker = false

    private var effectiveAvatar: String {
        publishAsPatient ? patient.avatarSymbol : currentUser.avatarSymbol
    }
    private var effectivePlaceholder: String {
        publishAsPatient
            ? "כתבי את העדכון בשם \(patient.displayName)..."
            : "שתפי עדכון חדש עם המשפחה..."
    }

    var body: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    BeaconAvatar(
                        systemImage: effectiveAvatar,
                        diameter: 40,
                        tint: publishAsPatient ? Theme.Palette.softBlue : Theme.Palette.sage,
                        foreground: publishAsPatient ? Theme.Palette.deepTeal : Theme.Palette.sageDark
                    )
                    TextField(effectivePlaceholder, text: $text, axis: .vertical)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(3...6)
                        .padding(Theme.Spacing.s)
                        .background(Theme.Palette.background)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
                }

                Toggle(isOn: $publishAsPatient.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Palette.deepTeal)
                        Text("פרסמי בשם \(patient.displayName)")
                            .font(Theme.Typography.captionEmphasis)
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
                .tint(Theme.Palette.deepTeal)

                if let status {
                    HStack {
                        BeaconBadge(text: status.displayLabel, tone: tone(for: status), leadingDot: true)
                        Spacer()
                        Button { self.status = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: Theme.Spacing.m) {
                    Button(action: onPublish) {
                        HStack(spacing: Theme.Spacing.s) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("פרסם")
                                .font(Theme.Typography.bodyEmphasis)
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, Theme.Spacing.l)
                        .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Theme.Palette.textSecondary
                                    : Theme.Palette.deepTeal)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    HStack(spacing: Theme.Spacing.xs) {
                        Text("גלוי למשפחה בלבד")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }

                    Spacer()

                    Button { showingStatusPicker = true } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text("סטטוס")
                                .font(Theme.Typography.captionEmphasis)
                        }
                        .foregroundStyle(Theme.Palette.sageDark)
                        .padding(.vertical, 10)
                        .padding(.horizontal, Theme.Spacing.m)
                        .background(Theme.Palette.sage)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .confirmationDialog("בחר סטטוס", isPresented: $showingStatusPicker, titleVisibility: .visible) {
            ForEach(FeedPostStatus.allCases, id: \.self) { s in
                Button(s.displayLabel) { status = s }
            }
            Button("ביטול", role: .cancel) { }
        }
    }

    private func tone(for status: FeedPostStatus) -> BeaconBadge.Tone {
        switch status {
        case .stable, .improving: return .sage
        case .needsRest: return .coral
        case .concerned: return .coral
        }
    }
}

#Preview("ComposePostCard") {
    @Previewable @State var text: String = ""
    @Previewable @State var status: FeedPostStatus? = nil
    @Previewable @State var asPatient: Bool = false
    return ComposePostCard(
        text: $text,
        status: $status,
        currentUser: .primaryCaregiver,
        patient: .primary,
        onPublish: { },
        publishAsPatient: $asPatient
    )
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}
