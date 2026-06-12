import Foundation
import SwiftData

/// Languages supported for the home-caregiver reporting screen.
/// Adding a language = add a case here + strings in `CaregiverLocalization`.
enum CaregiverLanguage: String, Codable, CaseIterable, Identifiable {
    case english
    case tagalog
    case hindi
    case malayalam
    case tamil

    var id: String { rawValue }

    /// Native name, shown to the caregiver.
    var nativeName: String {
        switch self {
        case .english:   return "English"
        case .tagalog:   return "Tagalog"
        case .hindi:     return "हिन्दी"
        case .malayalam: return "മലയാളം"
        case .tamil:     return "தமிழ்"
        }
    }

    /// Hebrew name, shown to the family.
    var hebrewName: String {
        switch self {
        case .english:   return "אנגלית"
        case .tagalog:   return "טגלוג (פיליפינית)"
        case .hindi:     return "הינדי"
        case .malayalam: return "מלאיאלאם"
        case .tamil:     return "טמילית"
        }
    }

    /// All currently supported caregiver languages are LTR. Kept as a
    /// property so a future RTL language (e.g. Arabic) only changes here.
    var isRightToLeft: Bool { false }
}

/// A home caregiver (e.g. live-in aide) attached to the patient's care.
/// Local-only in the MVP — no account/login; the caregiver reports via a
/// focused screen opened from the family app.
@Model
final class CaregiverProfile {
    @Attribute(.unique) var id: String
    var displayName: String
    /// Free-text relation/title, e.g. "מטפלת סיעודית".
    var relationTitle: String
    var preferredLanguageRaw: String
    var isActive: Bool
    var createdAt: Date

    var preferredLanguage: CaregiverLanguage {
        get { CaregiverLanguage(rawValue: preferredLanguageRaw) ?? .english }
        set { preferredLanguageRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        displayName: String,
        relationTitle: String = "מטפל/ת סיעודי/ת",
        preferredLanguage: CaregiverLanguage = .english,
        isActive: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.relationTitle = relationTitle
        self.preferredLanguageRaw = preferredLanguage.rawValue
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
