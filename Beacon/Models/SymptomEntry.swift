import Foundation
import SwiftData

enum SymptomType: String, Codable, CaseIterable, Identifiable {
    case nausea
    case fatigue
    case pain
    case custom

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .nausea: return "בחילה"
        case .fatigue: return "עייפות"
        case .pain: return "כאב"
        case .custom: return "מדד חדש"
        }
    }

    var iconSymbol: String {
        switch self {
        case .nausea: return "face.dashed"
        case .fatigue: return "moon.fill"
        case .pain: return "bolt.heart.fill"
        case .custom: return "plus.circle.fill"
        }
    }
}

@Model
final class SymptomEntry {
    @Attribute(.unique) var id: String
    var typeRaw: String
    var customLabel: String?
    var severity: Int
    var note: String?
    var loggedAt: Date

    var type: SymptomType {
        get { SymptomType(rawValue: typeRaw) ?? .custom }
        set { typeRaw = newValue.rawValue }
    }

    var displayLabel: String {
        type == .custom ? (customLabel ?? "מדד") : type.displayLabel
    }

    init(
        id: String = UUID().uuidString,
        type: SymptomType,
        customLabel: String? = nil,
        severity: Int = 3,
        note: String? = nil,
        loggedAt: Date = .now
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.customLabel = customLabel
        self.severity = severity
        self.note = note
        self.loggedAt = loggedAt
    }
}
