import SwiftUI
import SwiftData
import UserNotifications

@main
struct BeaconApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushAppDelegate
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
            CaregiverCheckIn.self,
            CaregiverInstruction.self
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
                    // Demo data is opt-in only (כרטיס רפואי ← נתוני הדגמה).
                    // Real families must start with a clean, empty app.
                    if MockDataSeeder.isDemoDataEnabled {
                        MockDataSeeder.seedIfNeeded(in: modelContainer.mainContext)
                    }
                    await environment.checkSession()
                }
                .onChange(of: environment.authState, initial: true) {
                    guard environment.authState == .authenticated else { return }
                    Task {
                        await DoseReminderService.requestAuthorizationIfNeeded()
                        let settings = await UNUserNotificationCenter.current().notificationSettings()
                        guard settings.authorizationStatus == .authorized
                            || settings.authorizationStatus == .provisional else { return }
                        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
                    }
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
