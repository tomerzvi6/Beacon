import SwiftUI

struct PatientStatusStrip: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showingProfile = false
    @State private var showingWellnessPicker = false
    @State private var showingPermissions = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                showingProfile = true
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    BeaconAvatar(
                        systemImage: environment.patient.avatarSymbol,
                        diameter: 40,
                        tint: Theme.Palette.softBlue,
                        foreground: Theme.Palette.deepTeal
                    )
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(environment.patient.displayName)
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text("פתח כרטיס רפואי")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("פתח כרטיס רפואי של \(environment.patient.displayName)")

            Spacer()

            Button {
                showingWellnessPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(environment.patient.todaysWellness.emoji)
                        .font(.system(size: 18))
                    Text(environment.patient.todaysWellness.displayLabel)
                        .font(Theme.Typography.captionEmphasis)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, Theme.Spacing.m)
                .background(.regularMaterial, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("שנה את מצב \(environment.patient.displayName) להיום")

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    environment.toggleViewer()
                }
            } label: {
                Image(systemName: environment.isPatientView ? "person.fill" : "heart.text.square.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(environment.isPatientView ? Theme.Palette.coralAccent : Theme.Palette.deepTeal)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: environment.activeViewer)
            .accessibilityLabel(environment.isPatientView ? "החלף לתצוגת מטפל/ת" : "החלף לתצוגת חולה")

            if environment.canManagePermissions {
                Button {
                    showingPermissions = true
                } label: {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("נהל הרשאות גישה")
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.Palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
        .beaconCardShadow()
        .sheet(isPresented: $showingProfile) {
            PatientProfileSheet()
                .environment(environment)
        }
        .sheet(isPresented: $showingPermissions) {
            PermissionsSettingsView()
                .environment(environment)
        }
        .confirmationDialog("איך \(environment.patient.displayName) מרגיש היום?",
                            isPresented: $showingWellnessPicker,
                            titleVisibility: .visible) {
            ForEach(PatientWellness.allCases) { wellness in
                Button("\(wellness.emoji)  \(wellness.displayLabel)") {
                    var updated = environment.patient
                    updated.todaysWellness = wellness
                    environment.patient = updated
                }
            }
            Button("ביטול", role: .cancel) { }
        }
    }
}

#Preview("PatientStatusStrip") {
    PatientStatusStrip()
        .padding()
        .beaconScreenBackground()
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
