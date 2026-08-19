import Foundation
import Observation
import AuthenticationServices

struct PatientProfileDraft: Codable, Equatable {
    var displayName: String
    var age: Int?
    var primaryDoctor: String
    var primaryHospital: String
    var bloodType: String
    var allergies: [String]
    var emergencyContactName: String
    var emergencyContactPhone: String
}

struct PatientApprovalDraft: Codable, Equatable {
    var verificationEmail: String
    var hasIdPhotoForVerification: Bool
}

enum PatientAuthorizationStatus: String, Codable, Equatable {
    case approvedByPatient
    case pendingPatientConsent

    var displayLabel: String {
        switch self {
        case .approvedByPatient: return "מאושר על ידי המטופל"
        case .pendingPatientConsent: return "ממתין לאישור המטופל"
        }
    }

    var allowsProtectedCareAccess: Bool {
        self == .approvedByPatient
    }
}

enum AuditAction: String, Codable {
    case familyCreated
    case patientConsentPending
    case patientConsentApproved
    case permissionUpdated
    case mockInviteOpened
    case mockInviteBlockedByLimit
    case accessRevoked
    case inviteAccepted
    case signedOut
}

struct AuditEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var occurredAt: Date
    var actorMemberId: String
    var actorDisplayName: String
    var action: AuditAction
    var targetType: String
    var targetId: String?
    var summary: String
}

private struct AuditLogger {
    private let key = "beacon.auditEvents.v1"
    private let maxEvents = 250

    func load() -> [AuditEvent] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AuditEvent].self, from: data)) ?? []
    }

    func append(_ event: AuditEvent) -> [AuditEvent] {
        var events = load()
        events.insert(event, at: 0)
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return events
    }
}

@Observable
final class AppEnvironment {
    enum Viewer: String, CaseIterable, Identifiable {
        case caregiver
        case patient

        var id: String { rawValue }

        var displayLabel: String {
            switch self {
            case .caregiver: return "תצוגת מטפל/ת"
            case .patient: return "תצוגת חולה"
            }
        }
    }

    private enum BackendSessionCache {
        static let key = "beacon.cachedBackendUser.v1"
        static let patientProfileKey = "beacon.localPatientProfile.v1"
        static let patientApprovalKey = "beacon.localPatientApproval.v1"
        static let patientAuthorizationKey = "beacon.patientAuthorizationStatus.v1"
        static let dataSourceModeKey = "beacon.dataSourceMode.v1"
    }

    static let maxCaregivers = 5

    // MARK: - Auth state
    var authState: AuthState = .loading
    var authErrorMessage: String? = nil
    var signUpSuccessMessage: String? = nil   // distinct from errors
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
    var members: [FamilyMember]
    var activeViewer: Viewer
    var patientAuthorizationStatus: PatientAuthorizationStatus
    private(set) var auditEvents: [AuditEvent]

    /// Hospital-integrated vs. independent (self-upload) build. Runtime
    /// switch so both product versions can be demoed from one install.
    var dataSourceMode: DataSourceMode {
        didSet {
            UserDefaults.standard.set(dataSourceMode.rawValue, forKey: BackendSessionCache.dataSourceModeKey)
        }
    }

    var isIndependentMode: Bool { dataSourceMode == .independent }

    /// Bumped whenever local demo data is loaded or cleared. Tab roots
    /// observe it so the visible screen refreshes immediately, without
    /// waiting for a tab switch after the profile sheet is dismissed.
    var contentRevision: Int = 0

    private let auditLogger = AuditLogger()

    // MARK: - Init paths
    /// Production initializer — empty state until session check completes.
    /// Use this from `BeaconApp`.
    static func live() -> AppEnvironment {
        AppEnvironment(authService: AuthService())
    }

    private init(authService: AuthService) {
        let initialCurrentUser = FamilyMember.primaryCaregiver
        self.authService = authService
        self.currentUser = initialCurrentUser
        self.patient = .primary
        self.members = FamilyMember.all
        self.activeViewer = initialCurrentUser.isPatient ? .patient : .caregiver
        self.patientAuthorizationStatus = AppEnvironment.cachedPatientAuthorizationStatus()
        self.auditEvents = AuditLogger().load()
        self.dataSourceMode = AppEnvironment.cachedDataSourceMode()
        installSessionExpiryHandler()
    }

    /// Reacts when any backend call comes back 401 — the token can go bad
    /// mid-session for reasons the user had no part in (server restarted
    /// with a fresh signing key in dev, a session was revoked). Without
    /// this, every screen's own sync silently no-ops on the error and the
    /// family just sees stale/empty data with no explanation of why.
    private func installSessionExpiryHandler() {
        APIClient.onUnauthorized = { [weak self] in
            Task { @MainActor in
                self?.handleSessionExpired()
            }
        }
    }

    @MainActor
    private func handleSessionExpired() {
        guard authState == .authenticated || authState == .needsOnboarding else { return }
        TokenStore.clear()
        clearCachedBackendUser()
        backendUser = nil
        authState = .unauthenticated
        authErrorMessage = "ההתחברות פגה. יש להתחבר מחדש."
    }

    /// Preview / mock initializer — bypasses Supabase entirely.
    /// Default values match the previous behavior so existing previews
    /// using `AppEnvironment()` continue to work unchanged.
    init(
        currentUser: FamilyMember = .primaryCaregiver,
        patient: Patient = .primary,
        members: [FamilyMember] = FamilyMember.all,
        activeViewer: Viewer? = nil,
        authState: AuthState = .authenticated,
        dataSourceMode: DataSourceMode = .independent
    ) {
        self.authService = nil
        self.currentUser = currentUser
        self.patient = patient
        self.members = members
        self.activeViewer = activeViewer ?? (currentUser.isPatient ? .patient : .caregiver)
        self.authState = authState
        self.patientAuthorizationStatus = .approvedByPatient
        self.auditEvents = AuditLogger().load()
        self.dataSourceMode = dataSourceMode
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
            if restoreBackendOnlySession() {
                self.authState = .authenticated
                return
            }
            self.authState = .unauthenticated
            return
        }

        await loadUserContextAndRoute(using: authService)
        // Silent launch check — if the backend call failed, show a clean
        // login screen without a confusing error the user didn't trigger.
        if authState == .unauthenticated {
            authErrorMessage = nil
        }
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

    /// Sign in with Google → exchange the Google id_token for a Beacon
    /// JWT. Unlike Apple Sign-In, no parallel Supabase identity is
    /// established here — Phase 9.1.5 ships Google as a backend-only
    /// path. Successful sign-in routes straight to `.authenticated`.
    @MainActor
    func signInWithGoogle() async {
        authErrorMessage = nil
        backendAuthErrorMessage = nil
        do {
            let result = try await GoogleSignInService().signIn()
            let response = try await backendAuthService.exchangeGoogleToken(
                idToken: result.idToken,
                nonce: result.nonce
            )
            self.backendUser = response.user
            cacheBackendUser(response.user)
            self.applyBackendUserToDisplay(response.user)
            self.authState = .authenticated
        } catch let error as APIError {
            backendAuthErrorMessage = error.diagnosticDescription
            authErrorMessage = error.userMessage
        } catch let error as GoogleSignInError {
            authErrorMessage = error.localizedDescription
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    /// Map a `BackendUser` onto the legacy `currentUser` / `patient`
    /// fields so the existing UI keeps rendering until we replace those
    /// data paths in later phases. Reused by both Apple and Google flows.
    @MainActor
    private func applyBackendUserToDisplay(_ user: BackendUser) {
        self.supabaseUserId = user.id
        let role: MemberRole = (user.role == "patient") ? .patient
                              : (user.role == "co_owner") ? .admin
                              : .defaultMember
        let relation = user.role == "patient" ? "חולה" : "מטפל/ת"
        self.currentUser = FamilyMember(
            id: user.id.uuidString,
            displayName: user.full_name.isEmpty ? "מטפל/ת" : user.full_name,
            relation: relation,
            avatarSymbol: "person.crop.circle.fill",
            role: role
        )
        self.activeViewer = role.isPatient ? .patient : .caregiver
        if user.role == "patient" {
            updatePatientAuthorizationStatus(.approvedByPatient)
            applyPatientProfile(
                cachedPatientProfile()
                    ?? PatientProfileDraft(
                        displayName: user.full_name.isEmpty ? patient.displayName : user.full_name,
                        age: nil,
                        primaryDoctor: "",
                        primaryHospital: "",
                        bloodType: "",
                        allergies: [],
                        emergencyContactName: "",
                        emergencyContactPhone: ""
                    ),
                displayNameOverride: user.full_name.isEmpty ? nil : user.full_name
            )
        } else {
            patientAuthorizationStatus = AppEnvironment.cachedPatientAuthorizationStatus()
            if let profile = cachedPatientProfile() {
                applyPatientProfile(profile)
            }
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
            cacheBackendUser(response.user)
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
        signUpSuccessMessage = nil
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
        signUpSuccessMessage = nil
        do {
            try await authService.signUpWithEmail(email: email, password: password)
            guard await authService.currentSession() != nil else {
                authState = .unauthenticated
                signUpSuccessMessage = "ההרשמה נוצרה. בדוק/י את המייל שלך ואשר/י את החשבון, ואז התחבר/י."
                return
            }
            await loadUserContextAndRoute(using: authService)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    func createFamily(patientName: String, caregiverName: String) async {
        let profile = PatientProfileDraft(
            displayName: patientName,
            age: nil,
            primaryDoctor: "",
            primaryHospital: "",
            bloodType: "",
            allergies: [],
            emergencyContactName: "",
            emergencyContactPhone: ""
        )
        await createFamily(patientProfile: profile, caregiverName: caregiverName)
    }

    @MainActor
    func createFamily(
        patientProfile: PatientProfileDraft,
        caregiverName: String,
        approvalDraft: PatientApprovalDraft? = nil
    ) async {
        authErrorMessage = nil
        let trimmedCaregiverName = caregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPatientName = patientProfile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPatientName.isEmpty, !trimmedCaregiverName.isEmpty else { return }

        let normalizedProfile = PatientProfileDraft(
            displayName: trimmedPatientName,
            age: patientProfile.age,
            primaryDoctor: patientProfile.primaryDoctor.trimmingCharacters(in: .whitespacesAndNewlines),
            primaryHospital: patientProfile.primaryHospital.trimmingCharacters(in: .whitespacesAndNewlines),
            bloodType: patientProfile.bloodType.trimmingCharacters(in: .whitespacesAndNewlines),
            allergies: patientProfile.allergies
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            emergencyContactName: patientProfile.emergencyContactName.trimmingCharacters(in: .whitespacesAndNewlines),
            emergencyContactPhone: patientProfile.emergencyContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let authorizationStatus: PatientAuthorizationStatus = currentUser.isPatient
            ? .approvedByPatient
            : .pendingPatientConsent

        guard let authService else {
            cachePatientProfile(normalizedProfile)
            if let approvalDraft { cachePatientApprovalDraft(approvalDraft) }
            applyPatientProfile(normalizedProfile)
            updatePatientAuthorizationStatus(authorizationStatus)
            recordAudit(
                .familyCreated,
                targetType: "patient_case",
                summary: authorizationStatus == .approvedByPatient
                    ? "Patient case created by the patient."
                    : "Pending patient case created by a caregiver."
            )
            authState = .authenticated
            return
        }

        if await authService.currentSession() == nil, backendUser != nil {
            cachePatientProfile(normalizedProfile)
            if let approvalDraft { cachePatientApprovalDraft(approvalDraft) }
            applyPatientProfile(normalizedProfile)
            updatePatientAuthorizationStatus(authorizationStatus)
            recordAudit(
                .familyCreated,
                targetType: "patient_case",
                summary: authorizationStatus == .approvedByPatient
                    ? "Backend-only patient case created by the patient."
                    : "Backend-only pending patient case created by a caregiver."
            )
            authState = .authenticated
            return
        }

        do {
            _ = try await authService.createFamily(
                patientName: normalizedProfile.displayName,
                caregiverName: trimmedCaregiverName
            )
            cachePatientProfile(normalizedProfile)
            if let approvalDraft { cachePatientApprovalDraft(approvalDraft) }
            applyPatientProfile(normalizedProfile)
            updatePatientAuthorizationStatus(authorizationStatus)
            recordAudit(
                authorizationStatus == .approvedByPatient ? .familyCreated : .patientConsentPending,
                targetType: "patient_case",
                summary: authorizationStatus == .approvedByPatient
                    ? "Patient case created and marked approved."
                    : "Patient case created and marked pending consent."
            )
            await loadUserContextAndRoute(using: authService)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    func signOut() async {
        authErrorMessage = nil
        // Always clear backend + Google state, even in preview/mock mode.
        TokenStore.clear()
        GoogleSignInService.signOut()
        self.backendUser = nil
        self.backendAuthErrorMessage = nil
        self.supabaseUserId = nil
        clearCachedBackendUser()
        clearCachedPatientState()
        recordAudit(.signedOut, targetType: "session", summary: "User signed out.")

        guard let authService else {
            self.authState = .unauthenticated
            return
        }
        do {
            try await authService.signOut()
            self.authState = .unauthenticated
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    /// Join an existing family with the six-digit code the organiser shared.
    ///
    /// Routing deliberately does NOT go through `loadUserContextAndRoute`
    /// here. That helper asks Supabase whether the user has a family, but
    /// membership created by this call lives in the Beacon backend — Supabase
    /// would still answer "no family" and bounce the user back into
    /// onboarding, right after they successfully joined.
    @MainActor
    func joinHousehold(code: String) async -> Bool {
        authErrorMessage = nil
        do {
            let result = try await HouseholdService().join(code: code)

            // The backend swapped our token for one scoped to the new
            // household; mirror the new identity locally so every screen
            // reads the family we just joined.
            if let previous = backendUser {
                let updated = BackendUser(
                    id: previous.id,
                    household_id: result.member.householdId,
                    role: result.member.role,
                    full_name: previous.full_name
                )
                backendUser = updated
                cacheBackendUser(updated)
            }

            let role: MemberRole = result.member.role == "patient" ? .patient
                                 : result.member.role == "co_owner" ? .admin
                                 : .defaultMember
            currentUser = FamilyMember(
                id: result.member.userId.uuidString,
                displayName: currentUser.displayName,
                relation: role.isPatient ? "חולה" : "מטפל/ת",
                avatarSymbol: "person.crop.circle.fill",
                role: role
            )
            activeViewer = role.isPatient ? .patient : .caregiver
            updatePatientAuthorizationStatus(.approvedByPatient)
            recordAudit(
                .inviteAccepted,
                targetType: "household",
                targetId: result.member.householdId.uuidString,
                summary: "Joined household with invite code."
            )
            contentRevision += 1
            authState = .authenticated
            return true
        } catch {
            authErrorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func acceptInvite(token: UUID) async {
        guard let authService else { return }
        authErrorMessage = nil
        do {
            _ = try await authService.acceptInvite(token: token)
            recordAudit(
                .inviteAccepted,
                targetType: "invite",
                targetId: token.uuidString,
                summary: "Invite accepted."
            )
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
                                  : (ctx.role == "admin" || ctx.role == "co_owner") ? .admin
                                  : .defaultMember
            if role.isPatient || role == .admin {
                // Patients and co-owners (primary caregivers who manage the family) get
                // full access automatically — no separate patient-consent gate in MVP.
                updatePatientAuthorizationStatus(.approvedByPatient)
            } else {
                patientAuthorizationStatus = AppEnvironment.cachedPatientAuthorizationStatus()
            }
            let relation = role.isPatient ? "חולה" : "מטפל/ת"
            let cloudUser = FamilyMember(
                id: ctx.userId.uuidString,
                displayName: ctx.displayName ?? "מטפל/ת",
                relation: relation,
                avatarSymbol: "person.crop.circle.fill",
                role: role
            )
            self.currentUser = cloudUser
            self.activeViewer = role.isPatient ? .patient : .caregiver
            if let pname = ctx.patientName {
                if let profile = cachedPatientProfile() {
                    applyPatientProfile(profile, displayNameOverride: pname)
                } else {
                    self.patient = patientWithUpdatedProfile(displayName: pname)
                }
            }
            self.authState = .authenticated
        } catch {
            authErrorMessage = error.localizedDescription
            self.authState = .unauthenticated
        }
    }

    /// Replaces the static demo cast (`FamilyMember.all`) with the real
    /// household roster from the backend, so a feed post or claimed task
    /// authored on another family member's device shows their real name
    /// instead of failing to resolve. Best-effort: on failure, keeps
    /// whatever member list is already loaded rather than surfacing an error
    /// for what is, from the caller's perspective, a background refresh.
    @MainActor
    func refreshFamilyMembers() async {
        guard let backendUser else { return }
        do {
            let remoteMembers = try await HouseholdService().members()
            var updated: [FamilyMember] = remoteMembers.compactMap { member in
                // Keep the signed-in user's own live entry (local permission
                // edits shouldn't be clobbered by the server's coarser role).
                guard member.userId != backendUser.id else { return nil }
                let role: MemberRole = member.role == "patient" ? .patient
                                      : member.role == "co_owner" ? .admin
                                      : .defaultMember
                return FamilyMember(
                    id: member.userId.uuidString,
                    displayName: member.displayName.isEmpty ? "בן/בת משפחה" : member.displayName,
                    relation: role.isPatient ? "חולה" : "מטפל/ת",
                    avatarSymbol: "person.crop.circle",
                    role: role
                )
            }
            updated.append(currentUser)
            self.members = updated
            FamilyMember.all = updated
        } catch {
            // Keep the previous list — see doc comment above.
        }
    }

    // MARK: - Domain access

    var isPatientView: Bool { activeViewer == .patient }

    func toggleViewer() {
        activeViewer = activeViewer == .caregiver ? .patient : .caregiver
    }

    func canRead(_ module: AppModule) -> Bool {
        guard patientAuthorizationAllowsAccess(to: module) else { return false }
        return effectiveUser.canRead(module)
    }

    func canWrite(_ module: AppModule) -> Bool {
        guard patientAuthorizationAllowsAccess(to: module) else { return false }
        return effectiveUser.canWrite(module)
    }

    var canManagePermissions: Bool {
        currentUser.hasFullAccess
    }

    var canInviteMembers: Bool {
        currentUser.hasFullAccess
    }

    var caregiverCount: Int {
        members.filter { !$0.isPatient }.count
    }

    var remainingCaregiverSlots: Int {
        max(Self.maxCaregivers - caregiverCount, 0)
    }

    var canAddCaregiver: Bool {
        caregiverCount < Self.maxCaregivers
    }

    func updatePermissions(for memberId: String, module: AppModule, level: AccessLevel) {
        guard canManagePermissions else { return }
        guard let index = members.firstIndex(where: { $0.id == memberId }) else { return }
        guard !members[index].isPatient else { return }
        guard currentUser.isPatient || !members[index].hasFullAccess else { return }
        members[index].role = members[index].role.withUpdated(module, level: level)
        FamilyMember.all = members
        recordAudit(
            .permissionUpdated,
            targetType: "family_member",
            targetId: memberId,
            summary: "\(module.rawValue) permission changed to \(level.rawValue)."
        )
    }

    func revokeAccess(for memberId: String) {
        guard canManagePermissions else { return }
        guard let member = members.first(where: { $0.id == memberId }) else { return }
        guard !member.isPatient else { return }
        guard currentUser.isPatient || !member.hasFullAccess else { return }
        members.removeAll { $0.id == memberId }
        FamilyMember.all = members
        recordAudit(
            .accessRevoked,
            targetType: "family_member",
            targetId: memberId,
            summary: "Family member access revoked immediately."
        )
    }

    func approvePatientConsent() {
        guard currentUser.isPatient || currentUser.role == .admin else { return }
        updatePatientAuthorizationStatus(.approvedByPatient)
        recordAudit(
            .patientConsentApproved,
            targetType: "patient_case",
            summary: "Patient approved access to the care record."
        )
    }

    func recordMockInviteOpened() {
        recordAudit(
            .mockInviteOpened,
            targetType: "invite",
            summary: "Mock invite flow opened."
        )
    }

    func recordMockInviteBlockedByLimit() {
        recordAudit(
            .mockInviteBlockedByLimit,
            targetType: "invite",
            summary: "Mock invite blocked because caregiver limit was reached."
        )
    }

    var greetingName: String {
        switch activeViewer {
        case .caregiver: return currentUser.displayName
        case .patient: return patient.displayName
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
        currentUser
    }

    private func patientAuthorizationAllowsAccess(to module: AppModule) -> Bool {
        if currentUser.isPatient { return true }
        if patientAuthorizationStatus.allowsProtectedCareAccess { return true }
        return module == .feed
    }

    @MainActor
    private func restoreBackendOnlySession() -> Bool {
        guard let token = TokenStore.read() else { return false }
        // Reject expired tokens — all API calls would return 401 anyway
        if let exp = TokenStore.expirationDate(of: token), exp < Date() {
            TokenStore.clear()
            clearCachedBackendUser()
            return false
        }
        guard let user = cachedBackendUser() else { return false }
        backendUser = user
        applyBackendUserToDisplay(user)
        return true
    }

    @MainActor
    private func applyPatientProfile(
        _ profile: PatientProfileDraft,
        displayNameOverride: String? = nil
    ) {
        patient = patientWithUpdatedProfile(
            displayName: displayNameOverride ?? profile.displayName,
            age: profile.age,
            primaryDoctor: profile.primaryDoctor,
            primaryHospital: profile.primaryHospital,
            bloodType: profile.bloodType,
            allergies: profile.allergies,
            emergencyContactName: profile.emergencyContactName,
            emergencyContactPhone: profile.emergencyContactPhone
        )
    }

    private func patientWithUpdatedProfile(
        displayName: String? = nil,
        age: Int? = nil,
        primaryDoctor: String? = nil,
        primaryHospital: String? = nil,
        bloodType: String? = nil,
        allergies: [String]? = nil,
        emergencyContactName: String? = nil,
        emergencyContactPhone: String? = nil
    ) -> Patient {
        Patient(
            id: patient.id,
            displayName: displayName?.isEmpty == false ? displayName! : patient.displayName,
            relationToCaregiver: patient.relationToCaregiver,
            avatarSymbol: patient.avatarSymbol,
            age: age ?? patient.age,
            condition: patient.condition,
            primaryDoctor: primaryDoctor?.isEmpty == false ? primaryDoctor! : patient.primaryDoctor,
            primaryHospital: primaryHospital?.isEmpty == false ? primaryHospital! : patient.primaryHospital,
            bloodType: bloodType?.isEmpty == false ? bloodType! : patient.bloodType,
            allergies: allergies?.isEmpty == false ? allergies! : patient.allergies,
            emergencyContactName: emergencyContactName?.isEmpty == false ? emergencyContactName! : patient.emergencyContactName,
            emergencyContactPhone: emergencyContactPhone?.isEmpty == false ? emergencyContactPhone! : patient.emergencyContactPhone,
            todaysWellness: patient.todaysWellness
        )
    }

    private func cacheBackendUser(_ user: BackendUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: BackendSessionCache.key)
    }

    private func cachedBackendUser() -> BackendUser? {
        guard let data = UserDefaults.standard.data(forKey: BackendSessionCache.key) else {
            return nil
        }
        return try? JSONDecoder().decode(BackendUser.self, from: data)
    }

    private func clearCachedBackendUser() {
        UserDefaults.standard.removeObject(forKey: BackendSessionCache.key)
    }

    private func clearCachedPatientState() {
        UserDefaults.standard.removeObject(forKey: BackendSessionCache.patientProfileKey)
        UserDefaults.standard.removeObject(forKey: BackendSessionCache.patientApprovalKey)
        UserDefaults.standard.removeObject(forKey: BackendSessionCache.patientAuthorizationKey)
        patientAuthorizationStatus = .approvedByPatient
    }

    private func cachePatientProfile(_ profile: PatientProfileDraft) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: BackendSessionCache.patientProfileKey)
    }

    private func cachedPatientProfile() -> PatientProfileDraft? {
        guard let data = UserDefaults.standard.data(forKey: BackendSessionCache.patientProfileKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PatientProfileDraft.self, from: data)
    }

    private func cachePatientApprovalDraft(_ approvalDraft: PatientApprovalDraft) {
        guard let data = try? JSONEncoder().encode(approvalDraft) else { return }
        UserDefaults.standard.set(data, forKey: BackendSessionCache.patientApprovalKey)
    }

    private func updatePatientAuthorizationStatus(_ status: PatientAuthorizationStatus) {
        patientAuthorizationStatus = status
        UserDefaults.standard.set(status.rawValue, forKey: BackendSessionCache.patientAuthorizationKey)
    }

    private static func cachedPatientAuthorizationStatus() -> PatientAuthorizationStatus {
        guard let raw = UserDefaults.standard.string(forKey: BackendSessionCache.patientAuthorizationKey),
              let status = PatientAuthorizationStatus(rawValue: raw) else {
            return .approvedByPatient
        }
        return status
    }

    /// Independent (self-upload) is the default until a hospital
    /// integration actually exists.
    private static func cachedDataSourceMode() -> DataSourceMode {
        guard let raw = UserDefaults.standard.string(forKey: BackendSessionCache.dataSourceModeKey),
              let mode = DataSourceMode(rawValue: raw) else {
            return .independent
        }
        return mode
    }

    private func recordAudit(
        _ action: AuditAction,
        targetType: String,
        targetId: String? = nil,
        summary: String
    ) {
        let event = AuditEvent(
            id: UUID(),
            occurredAt: Date(),
            actorMemberId: currentUser.id,
            actorDisplayName: currentUser.displayName,
            action: action,
            targetType: targetType,
            targetId: targetId,
            summary: summary
        )
        auditEvents = auditLogger.append(event)
    }
}
