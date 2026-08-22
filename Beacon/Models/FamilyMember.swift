import Foundation

struct FamilyMember: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let relation: String
    let avatarSymbol: String
    var role: MemberRole
    var approvalStatus: MemberApprovalStatus = .approved
    /// household_members.id on the backend — distinct from `id` (the
    /// user's id, used everywhere else to match authorship/claims). Only
    /// permission-management calls need this row id; nil for the static
    /// demo cast and for the signed-in user's own entry.
    var membershipId: String? = nil

    var isAdmin: Bool { role.isAdmin }
    var isPatient: Bool { role.isPatient }
    var isAccessOwner: Bool { role.isAccessOwner }
    var hasFullAccess: Bool { role.hasFullAccess }
    var isPendingApproval: Bool { approvalStatus == .pendingPatientApproval }

    func canRead(_ module: AppModule) -> Bool {
        role.accessLevel(for: module) >= .read
    }

    func canWrite(_ module: AppModule) -> Bool {
        role.accessLevel(for: module) >= .readWrite
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: FamilyMember, rhs: FamilyMember) -> Bool { lhs.id == rhs.id }

    // MARK: Static members
    static let patient = FamilyMember(
        id: "aba",
        displayName: "אבא (יוסף)",
        relation: "חולה",
        avatarSymbol: "person.crop.circle.fill",
        role: .patient
    )

    static let primaryCaregiver = FamilyMember(
        id: "ronit",
        displayName: "רונית",
        relation: "בת",
        avatarSymbol: "person.crop.circle.fill",
        role: .admin
    )

    static let daniel = FamilyMember(
        id: "daniel",
        displayName: "דניאל",
        relation: "בן",
        avatarSymbol: "person.crop.circle",
        role: .member(permissions: [
            AppModule.schedule.rawValue:     AccessLevel.read.rawValue,
            AppModule.tasks.rawValue:        AccessLevel.readWrite.rawValue,
            AppModule.medications.rawValue:  AccessLevel.read.rawValue,
            AppModule.medicalVault.rawValue: AccessLevel.none.rawValue,
            AppModule.feed.rawValue:         AccessLevel.readWrite.rawValue
        ])
    )

    static let uncleMoshe = FamilyMember(
        id: "moshe",
        displayName: "דוד משה",
        relation: "דוד",
        avatarSymbol: "person.crop.circle",
        role: .member(permissions: [
            AppModule.schedule.rawValue:     AccessLevel.none.rawValue,
            AppModule.tasks.rawValue:        AccessLevel.none.rawValue,
            AppModule.medications.rawValue:  AccessLevel.none.rawValue,
            AppModule.medicalVault.rawValue: AccessLevel.none.rawValue,
            AppModule.feed.rawValue:         AccessLevel.readWrite.rawValue
        ])
    )

    static let auntRachel = FamilyMember(
        id: "rachel",
        displayName: "דודה רחל",
        relation: "דודה",
        avatarSymbol: "person.crop.circle",
        role: .member(permissions: [
            AppModule.schedule.rawValue:     AccessLevel.none.rawValue,
            AppModule.tasks.rawValue:        AccessLevel.none.rawValue,
            AppModule.medications.rawValue:  AccessLevel.none.rawValue,
            AppModule.medicalVault.rawValue: AccessLevel.none.rawValue,
            AppModule.feed.rawValue:         AccessLevel.readWrite.rawValue
        ])
    )

    static var all: [FamilyMember] = [.patient, .primaryCaregiver, .daniel, .uncleMoshe, .auntRachel]

    static func find(id: String) -> FamilyMember? {
        all.first { $0.id == id }
    }
}

enum MemberApprovalStatus: String, Codable, Hashable {
    case approved
    case pendingPatientApproval

    var displayLabel: String {
        switch self {
        case .approved: return "מאושר"
        case .pendingPatientApproval: return "ממתין לאישור מטופל"
        }
    }
}
