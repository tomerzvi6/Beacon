import Foundation
import Observation
import AuthenticationServices

@Observable
final class AppEnvironment {
    enum Viewer: String, CaseIterable, Identifiable {
        case caregiver
        case patient

        var id: String { rawValue }
        var displayLabel: String {
            switch self {
            case .caregiver: return "תצוגת מטפל/ת"
            case .patient:   return "תצוגת חולה"
            }
        }
    }

    // MARK: - Auth state
    var authState: AuthState = .loading
    var authErrorMessage: String? = nil
    private let authService: AuthService?
    private(set) var supabaseUserId: UUID? = nil

    /// Beacon backend identity (issued by `POST /v1/auth/apple`). Populated
    /// after Sign in with Apple succeeds. Nil in preview/mock mode and
    /// nil if the backend exchange failed (in which case
    /// `backendAuthErrorMessage` carries the reason).
    private(set) var backendUser: BackendUser? = nil
    var backendAuthErrorMessage: String? = nil
    private let backendAuthService = BackendAuthService()

    // MARK: - Domain state (was previously hard-mocked)
    var currentUser: FamilyMember
    var patient: Patient
    var activeViewer: Viewer
    var members: [FamilyMember]

    // MARK: - Init paths
    /// Production initializer — empty state until session check completes.
    /// Use this from `BeaconApp`.
    static func live() -> AppEnvironment {
        AppEnvironment(authService: AuthService())
    }

    private init(authService: AuthService) {
        self.authService = authService
        self.currentUser = .primaryCaregiver
        self.patient = .primary
        self.activeViewer = .caregiver
        self.members = FamilyMember.all
    }

    /// Preview / mock initializer — bypasses Supabase entirely.
    /// Default values match the previous behavior so existing previews
    /// using `AppEnvironment()` continue to work unchanged.
    init(
        currentUser: FamilyMember = .primaryCaregiver,
        patient: Patient = .primary,
        activeViewer: Viewer = .caregiver,
        members: [FamilyMember] = FamilyMember.all,
        authState: AuthState = .authenticated
    ) {
        self.authService = nil
        self.currentUser = currentUser
        self.patient = patient
        self.activeViewer = activeViewer
        self.members = members
        self.authState = authState
    }

    // MARK: - Session lifecycle

    /// Called once on app launch. Decides whether to show login,
    /// onboarding, or the main app.
    @MainActor
    func checkSession() async {
        guard let authService else {
            // Preview / mock mode — already authenticated
            self.authState = .authenticated
            return
        }

        if await authService.currentSession() == nil {
            self.authState = .unauthenticated
            return
        }

        await loadUserContextAndRoute(using: authService)
    }

    @MainActor
    func signInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String) async {
        guard let authService else { return }
        authErrorMessage = nil
        do {
            try await authService.signInWithApple(credential: credential, rawNonce: rawNonce)
            await exchangeBackendToken(credential: credential, rawNonce: rawNonce)
            await loadUserContextAndRoute(using: authService)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    /// Exchange the Apple identity token for a Beacon backend JWT. Failures
    /// are NOT fatal — Supabase auth still drives the UI in Phase 9.1; the
    /// reason is stored on `backendAuthErrorMessage` for DiagnosticView.
    @MainActor
    private func exchangeBackendToken(
        credential: ASAuthorizationAppleIDCredential,
        rawNonce: String
    ) async {
        backendAuthErrorMessage = nil
        guard
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            backendAuthErrorMessage = "Apple credential missing identity token"
            return
        }
        do {
            let response = try await backendAuthService.exchangeAppleToken(
                identityToken: idToken,
                rawNonce: rawNonce,
                givenName: credential.fullName?.givenName,
                familyName: credential.fullName?.familyName
            )
            self.backendUser = response.user
        } catch let error as APIError {
            backendAuthErrorMessage = error.diagnosticDescription
        } catch {
            backendAuthErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    func signInWithEmail(email: String, password: String) async {
        guard let authService else { return }
        authErrorMessage = nil
        do {
            try await authService.signInWithEmail(email: email, password: password)
            await loadUserContextAndRoute(using: authService)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    func signUpWithEmail(email: String, password: String) async {
        guard let authService else { return }
        authErrorMessage = nil
        do {
            try await authService.signUpWithEmail(email: email, password: password)
            await loadUserContextAndRoute(using: authService)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    func createFamily(patientName: String, caregiverName: String) async {
        guard let authService else { return }
        authErrorMessage = nil
        do {
            _ = try await authService.createFamily(
                patientName: patientName,
                caregiverName: caregiverName
            )
            await loadUserContextAndRoute(using: authService)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    func signOut() async {
        guard let authService else { return }
        authErrorMessage = nil
        do {
            try await authService.signOut()
            TokenStore.clear()
            self.backendUser = nil
            self.backendAuthErrorMessage = nil
            self.supabaseUserId = nil
            self.authState = .unauthenticated
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    func acceptInvite(token: UUID) async {
        guard let authService else { return }
        authErrorMessage = nil
        do {
            _ = try await authService.acceptInvite(token: token)
            await loadUserContextAndRoute(using: authService)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Routing helper

    @MainActor
    private func loadUserContextAndRoute(using authService: AuthService) async {
        do {
            let ctx = try await authService.loadUserContext()
            self.supabaseUserId = ctx.userId

            if !ctx.hasFamily || ctx.displayName == nil {
                self.authState = .needsOnboarding
                return
            }

            // Map remote user → local FamilyMember.
            // For POC we keep the existing mock family list; the cloud
            // user becomes the "current admin" and patient name comes
            // from the family record.
            let role: MemberRole = (ctx.role == "patient") ? .patient
                                  : (ctx.role == "admin")  ? .admin
                                  : .defaultMember
            let cloudUser = FamilyMember(
                id: ctx.userId.uuidString,
                displayName: ctx.displayName ?? "מטפל/ת",
                relation: "מטפל/ת ראשי/ת",
                avatarSymbol: "person.crop.circle.fill",
                role: role
            )
            self.currentUser = cloudUser
            if let pname = ctx.patientName {
                self.patient = Patient(
                    id: self.patient.id,
                    displayName: pname,
                    relationToCaregiver: self.patient.relationToCaregiver,
                    avatarSymbol: self.patient.avatarSymbol,
                    age: self.patient.age,
                    condition: self.patient.condition,
                    primaryDoctor: self.patient.primaryDoctor,
                    primaryHospital: self.patient.primaryHospital,
                    bloodType: self.patient.bloodType,
                    allergies: self.patient.allergies,
                    emergencyContactName: self.patient.emergencyContactName,
                    emergencyContactPhone: self.patient.emergencyContactPhone,
                    todaysWellness: self.patient.todaysWellness
                )
            }
            self.authState = .authenticated
        } catch {
            authErrorMessage = error.localizedDescription
            self.authState = .unauthenticated
        }
    }

    // MARK: - Existing functionality (unchanged)

    var isPatientView: Bool { activeViewer == .patient }

    func toggleViewer() {
        activeViewer = (activeViewer == .caregiver) ? .patient : .caregiver
    }

    func canRead(_ module: AppModule) -> Bool {
        effectiveUser.canRead(module)
    }

    func canWrite(_ module: AppModule) -> Bool {
        effectiveUser.canWrite(module)
    }

    var canManagePermissions: Bool {
        currentUser.isAdmin || currentUser.isPatient
    }

    var canInviteMembers: Bool {
        currentUser.isAdmin
    }

    func updatePermissions(for memberId: String, module: AppModule, level: AccessLevel) {
        guard canManagePermissions else { return }
        guard let index = members.firstIndex(where: { $0.id == memberId }) else { return }
        members[index].role = members[index].role.withUpdated(module, level: level)
        FamilyMember.all = members
    }

    var greetingName: String {
        switch activeViewer {
        case .caregiver: return currentUser.displayName
        case .patient:   return patient.displayName
        }
    }

    var greetingForCurrentHour: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "בוקר טוב"
        case 12..<17: return "צהריים טובים"
        case 17..<22: return "ערב טוב"
        default:      return "לילה טוב"
        }
    }

    var todayHebrewDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "EEEE, d בMMMM"
        return formatter.string(from: Date())
    }

    private var effectiveUser: FamilyMember {
        isPatientView ? .patient : currentUser
    }
}
