import SwiftUI
import SwiftData

@main
struct BeaconApp: App {
    let modelContainer: ModelContainer
    @State private var environment = AppEnvironment.live()

    init() {
        // Phase 9.3: MedicalDocument removed — documents now read live
        // from the Beacon backend. Tasks/medications/symptoms still live
        // in SwiftData until phases 4–5 migrate them.
        let schema = Schema([
            ScheduleEvent.self,
            DailyTask.self,
            Medication.self,
            MedicationDose.self,
            SymptomEntry.self,
            HospitalSyncAlert.self,
            FeedPost.self,
            FeedComment.self,
            CaregiverProfile.self,
            CaregiverCheckIn.self
        ])
        if let container = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        ) {
            self.modelContainer = container
        } else {
            // Persistent store failed (schema migration) — fall back to in-memory.
            // Data is re-seeded from MockDataSeeder on every launch in this mode.
            self.modelContainer = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }
        GoogleSignInService.configureIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(environment)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .environment(\.layoutDirection, .rightToLeft)
                .tint(Theme.Palette.deepTeal)
                .task {
                    MockDataSeeder.seedIfNeeded(in: modelContainer.mainContext)
                    await environment.checkSession()
                }
                .onOpenURL { url in
                    // Google Sign-In OAuth redirect — must run before
                    // any other URL handler so the SDK can complete the
                    // sign-in flow.
                    if GoogleSignInService.handle(url: url) { return }
                    if let token = InviteService.parseInviteToken(from: url) {
                        Task { await environment.acceptInvite(token: token) }
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    @ViewBuilder
    private var rootView: some View {
        switch environment.authState {
        case .loading:
            SplashView()
        case .unauthenticated:
            LoginView()
        case .needsOnboarding:
            OnboardingView()
        case .authenticated:
            RootTabView()
        }
    }
}
