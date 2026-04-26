import Foundation

enum AppModule: String, Codable, CaseIterable, Identifiable {
    case schedule
    case tasks
    case medications
    case medicalVault
    case feed

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .schedule:     return "לוח זמנים"
        case .tasks:        return "משימות"
        case .medications:  return "תרופות ומינונים"
        case .medicalVault: return "תיק רפואי"
        case .feed:         return "מעגל תמיכה"
        }
    }

    var iconSymbol: String {
        switch self {
        case .schedule:     return "calendar"
        case .tasks:        return "checkmark.circle"
        case .medications:  return "pills.fill"
        case .medicalVault: return "briefcase.fill"
        case .feed:         return "bubble.left.and.bubble.right.fill"
        }
    }
}

enum AccessLevel: Int, Codable, CaseIterable, Identifiable, Comparable, Hashable {
    case none     = 0
    case read     = 1
    case readWrite = 2

    var id: Int { rawValue }

    var displayLabel: String {
        switch self {
        case .none:      return "ללא גישה"
        case .read:      return "צפייה בלבד"
        case .readWrite: return "צפייה ועריכה"
        }
    }

    var iconSymbol: String {
        switch self {
        case .none:      return "xmark.circle"
        case .read:      return "eye"
        case .readWrite: return "pencil.and.outline"
        }
    }

    static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum MemberRole: Codable, Equatable {
    case patient
    case admin
    case member(permissions: [String: Int])

    var isAdmin: Bool {
        if case .admin = self { return true }
        if case .patient = self { return true }
        return false
    }

    var isPatient: Bool {
        if case .patient = self { return true }
        return false
    }

    func accessLevel(for module: AppModule) -> AccessLevel {
        switch self {
        case .patient, .admin:
            return .readWrite
        case .member(let permissions):
            guard let raw = permissions[module.rawValue],
                  let level = AccessLevel(rawValue: raw) else { return .none }
            return level
        }
    }

    func withUpdated(_ module: AppModule, level: AccessLevel) -> MemberRole {
        switch self {
        case .patient, .admin:
            return self
        case .member(var permissions):
            permissions[module.rawValue] = level.rawValue
            return .member(permissions: permissions)
        }
    }

    static var defaultMember: MemberRole {
        .member(permissions: Dictionary(
            uniqueKeysWithValues: AppModule.allCases.map { ($0.rawValue, AccessLevel.read.rawValue) }
        ))
    }
}
