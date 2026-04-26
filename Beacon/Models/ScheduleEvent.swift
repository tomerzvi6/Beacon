import Foundation
import SwiftData

enum ScheduleEventKind: String, Codable, CaseIterable {
    case medical
    case routine
    case logistics

    var displayLabel: String {
        switch self {
        case .medical: return "רפואי"
        case .routine: return "שגרה"
        case .logistics: return "לוגיסטי"
        }
    }
}

@Model
final class ScheduleEvent {
    @Attribute(.unique) var id: String
    var title: String
    var startsAt: Date
    var locationName: String?
    var companionMemberId: String?
    var subtitle: String?
    var kindRaw: String

    var kind: ScheduleEventKind {
        get { ScheduleEventKind(rawValue: kindRaw) ?? .routine }
        set { kindRaw = newValue.rawValue }
    }

    var companion: FamilyMember? {
        guard let id = companionMemberId else { return nil }
        return FamilyMember.find(id: id)
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        startsAt: Date,
        kind: ScheduleEventKind,
        locationName: String? = nil,
        companionMemberId: String? = nil,
        subtitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.kindRaw = kind.rawValue
        self.locationName = locationName
        self.companionMemberId = companionMemberId
        self.subtitle = subtitle
    }
}
