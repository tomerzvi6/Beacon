import Foundation
import Observation

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

    var currentUser: FamilyMember
    var patient: Patient
    var activeViewer: Viewer
    var members: [FamilyMember]

    init(
        currentUser: FamilyMember = .primaryCaregiver,
        patient: Patient = .primary,
        activeViewer: Viewer = .caregiver,
        members: [FamilyMember] = FamilyMember.all
    ) {
        self.currentUser = currentUser
        self.patient = patient
        self.activeViewer = activeViewer
        self.members = members
    }

    var isPatientView: Bool { activeViewer == .patient }

    func toggleViewer() {
        activeViewer = (activeViewer == .caregiver) ? .patient : .caregiver
    }

    // MARK: Permission helpers
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

    // MARK: Greeting
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

    // MARK: Private
    private var effectiveUser: FamilyMember {
        isPatientView ? .patient : currentUser
    }
}
