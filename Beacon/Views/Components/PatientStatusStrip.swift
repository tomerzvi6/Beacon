import SwiftUI

struct PatientStatusStrip: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showingProfile = false
    @State private var showingWellnessPicker = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button {
                showingProfile = true
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    BeaconAvatar(
                        systemImage: environment.patient.avatarSymbol,
                        diameter: Theme.Layout.minimumTouchTarget - Theme.Spacing.s,
                        tint: Theme.Palette.softBlue,
                        foreground: Theme.Palette.deepTeal
                    )
                    VStack(alignment: .trailing, spacing: Theme.Layout.statusStripTextSpacing) {
                        Text(environment.patient.displayName)
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .beaconHorizontalText(minScale: 0.6)
                        Text("פתח כרטיס רפואי")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .beaconHorizontalText(minScale: 0.6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityLabel("פתח כרטיס רפואי של \(environment.patient.displayName)")

            Button {
                showingWellnessPicker = true
            } label: {
                Text(environment.patient.todaysWellness.emoji)
                    .font(.system(size: 20))
                    .frame(width: Theme.Layout.minimumTouchTarget, height: Theme.Layout.minimumTouchTarget)
                    .background(.regularMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("מצב היום: \(environment.patient.todaysWellness.displayLabel). לחיצה לשינוי")

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    environment.toggleViewer()
                }
            } label: {
                Image(systemName: environment.isPatientView ? "person.fill" : "heart.text.square.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(environment.isPatientView ? Theme.Palette.coralAccent : Theme.Palette.deepTeal)
                    .frame(width: Theme.Layout.minimumTouchTarget, height: Theme.Layout.minimumTouchTarget)
                    .background(.regularMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: environment.activeViewer)
            .accessibilityLabel(environment.isPatientView ? "החלף לתצוגת מטפל/ת" : "החלף לתצוגת חולה")
        }
        .padding(.horizontal, Theme.Layout.statusStripHorizontalPadding)
        .padding(.vertical, Theme.Layout.statusStripVerticalPadding)
        .background(Theme.Palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
        .beaconCardShadow()
        .sheet(isPresented: $showingProfile) {
            PatientProfileSheet()
                .environment(environment)
        }
        .confirmationDialog(
            "איך \(environment.patient.displayName) מרגיש היום?",
            isPresented: $showingWellnessPicker,
            titleVisibility: .visible
        ) {
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

struct BeaconEdgeTopBar: View {
    var body: some View {
        PatientStatusStrip()
            .padding(.horizontal, Theme.Layout.edgeBarHorizontalInset)
            .padding(.top, Theme.Layout.topStatusStripTopInset)
            .padding(.bottom, Theme.Layout.topStatusStripBottomGap)
            .background(
                // Extends an opaque backdrop through the true status-bar /
                // Dynamic Island zone. BeaconEdgeTopBar is a top overlay
                // (not a safeAreaInset — see RootTabView), so scrolled
                // content underneath can reach all the way to the physical
                // screen edge; without this, that sliver above the card
                // itself has nothing opaque covering it.
                Theme.Palette.background.ignoresSafeArea(edges: .top)
            )
    }
}

#Preview("PatientStatusStrip") {
    PatientStatusStrip()
        .padding()
        .beaconScreenBackground()
        .modelContainer(MockDataSeeder.makeInMemoryPreviewContainer())
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
