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
    @State private var showingPermissions = false

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "BeaconCardBackground") ?? .white
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selection) {
            // Dashboard — always visible (schedule + tasks gated inside)
            DashboardView()
                .tabItem { Label("לוח בקרה", systemImage: "square.grid.2x2.fill") }
                .tag(Tab.dashboard)

            // Medical Vault — gated by .medicalVault read
            if environment.canRead(.medicalVault) {
                MedicalVaultView()
                    .tabItem { Label("תיק רפואי", systemImage: "briefcase.fill") }
                    .tag(Tab.medicalVault)
            }

            // Proactive Care — gated by .medications read
            if environment.canRead(.medications) {
                ProactiveCareView()
                    .tabItem { Label("מעקב טיפול", systemImage: "cross.case.fill") }
                    .tag(Tab.proactiveCare)
            }

            // Circle of Trust — gated by .feed read
            if environment.canRead(.feed) {
                CircleOfTrustView()
                    .tabItem { Label("מעגל תמיכה", systemImage: "bubble.left.and.bubble.right.fill") }
                    .tag(Tab.circleOfTrust)
            }
        }
        .tint(Theme.Palette.deepTeal)
        .sheet(isPresented: $showingPermissions) {
            PermissionsSettingsView()
                .environment(environment)
        }
        .onChange(of: environment.canRead(.medicalVault)) { _, canRead in
            if !canRead && selection == .medicalVault { selection = .dashboard }
        }
        .onChange(of: environment.canRead(.medications)) { _, canRead in
            if !canRead && selection == .proactiveCare { selection = .dashboard }
        }
        .onChange(of: environment.canRead(.feed)) { _, canRead in
            if !canRead && selection == .circleOfTrust { selection = .dashboard }
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
