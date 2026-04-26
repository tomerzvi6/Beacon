import Foundation
import SwiftData

enum TaskKind: String, Codable, CaseIterable {
    case medical
    case logistics

    var displayLabel: String {
        switch self {
        case .medical: return "רפואי"
        case .logistics: return "לוגיסטי"
        }
    }
}

enum TaskOrigin: String, Codable {
    case manual
    case aiSuggestion
    case hospitalSync
}

@Model
final class DailyTask {
    @Attribute(.unique) var id: String
    var title: String
    var detail: String?
    var kindRaw: String
    var originRaw: String
    var claimedByMemberId: String?
    var isCompleted: Bool
    var createdAt: Date
    var dueAt: Date?

    var kind: TaskKind {
        get { TaskKind(rawValue: kindRaw) ?? .logistics }
        set { kindRaw = newValue.rawValue }
    }

    var origin: TaskOrigin {
        get { TaskOrigin(rawValue: originRaw) ?? .manual }
        set { originRaw = newValue.rawValue }
    }

    var claimedBy: FamilyMember? {
        guard let id = claimedByMemberId else { return nil }
        return FamilyMember.find(id: id)
    }

    var isClaimed: Bool { claimedByMemberId != nil }

    init(
        id: String = UUID().uuidString,
        title: String,
        detail: String? = nil,
        kind: TaskKind,
        origin: TaskOrigin = .manual,
        claimedByMemberId: String? = nil,
        isCompleted: Bool = false,
        dueAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kindRaw = kind.rawValue
        self.originRaw = origin.rawValue
        self.claimedByMemberId = claimedByMemberId
        self.isCompleted = isCompleted
        self.dueAt = dueAt
        self.createdAt = createdAt
    }
}
