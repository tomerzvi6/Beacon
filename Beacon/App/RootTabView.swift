import SwiftUI

struct RootTabView: View {
    @Environment(AppEnvironment.self) private var environment

    enum Tab: Hashable {
        case dashboard
        case medicalVault
        case proactiveCare
        case circleOfTrust
    }

    @State private var selection: Tab = .dashboard

    init() {
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BeaconEdgeTopBar()
                .padding(.bottom, -Theme.Layout.edgeBarHalfCentimeterOffset)
                .offset(y: -Theme.Layout.edgeBarHalfCentimeterOffset)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BeaconBottomTabBar(selection: $selection, tabs: availableTabs)
                .padding(.horizontal, Theme.Layout.bottomTabBarHorizontalInset)
                .padding(.bottom, Theme.Layout.bottomTabBarBottomInset)
                .padding(.top, -Theme.Layout.edgeBarHalfCentimeterOffset)
                .offset(y: Theme.Layout.edgeBarHalfCentimeterOffset)
        }
        .tint(Theme.Palette.deepTeal)
    }

    private var availableTabs: [Tab] {
        [.dashboard, .medicalVault, .proactiveCare, .circleOfTrust]
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selection {
        case .dashboard:
            DashboardView()
        case .medicalVault:
            if environment.canRead(.medicalVault) {
                MedicalVaultView()
            } else {
                AccessDeniedView(module: .medicalVault)
            }
        case .proactiveCare:
            if environment.canRead(.medications) {
                ProactiveCareView()
            } else {
                AccessDeniedView(module: .medications)
            }
        case .circleOfTrust:
            if environment.canRead(.feed) {
                CircleOfTrustView()
            } else {
                AccessDeniedView(module: .feed)
            }
        }
    }
}

private struct AccessDeniedView: View {
    @Environment(AppEnvironment.self) private var environment
    let module: AppModule

    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                BeaconScreenHeader(
                    title: module.displayLabel,
                    subtitle: "המידע הזה מוגן לפי הרשאות המשפחה."
                )

                BeaconCard {
                    BeaconEmptyState(
                        systemImage: "lock.shield.fill",
                        title: title,
                        message: message
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.m)
        }
        .beaconScreenBackground()
    }

    private var title: String {
        if environment.patientAuthorizationStatus == .pendingPatientConsent {
            return "התיק ממתין לאישור המטופל"
        }
        return "אין לך הרשאה למסך הזה"
    }

    private var message: String {
        if environment.patientAuthorizationStatus == .pendingPatientConsent {
            return "אחרי אימות מייל וצילום תעודת זהות, המטופל יאשר מי רשאי לראות או לערוך את המידע."
        }
        return "אפשר לבקש ממנהל/ת הגישה או מהמטופל/ת לעדכן הרשאות עבור \(module.displayLabel)."
    }
}

private struct BeaconBottomTabBar: View {
    @Binding var selection: RootTabView.Tab
    let tabs: [RootTabView.Tab]

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 21, weight: .semibold))
                            .frame(height: Theme.Layout.bottomTabIconHeight)
                        Text(tab.title)
                            .font(Theme.Typography.tag)
                            .multilineTextAlignment(.center)
                            .beaconHorizontalText(minScale: Theme.Layout.bottomTabLabelMinScale)
                    }
                    .foregroundStyle(selection == tab ? Theme.Palette.deepTeal : Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.Layout.bottomTabItemMinHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, Theme.Layout.bottomTabBarHorizontalPadding)
        .padding(.vertical, Theme.Layout.bottomTabBarVerticalPadding)
        .background(Theme.Palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
        .beaconCardShadow()
    }
}

private extension RootTabView.Tab {
    var title: String {
        switch self {
        case .dashboard: return "לוח בקרה"
        case .medicalVault: return "תיק רפואי"
        case .proactiveCare: return "מעקב טיפול"
        case .circleOfTrust: return "מעגל תמיכה"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .medicalVault: return "briefcase.fill"
        case .proactiveCare: return "cross.case.fill"
        case .circleOfTrust: return "bubble.left.and.bubble.right.fill"
        }
    }
}

#Preview("RootTabView") {
    RootTabView()
        .modelContainer(MockDataSeeder.makeInMemoryPreviewContainer())
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
