import Foundation
import SwiftData

// MARK: - Structured statuses

enum CaregiverMealStatus: String, Codable, CaseIterable, Identifiable {
    case ateWell
    case ateLittle
    case didNotEat

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .ateWell:   return "אכל/ה טוב"
        case .ateLittle: return "אכל/ה מעט"
        case .didNotEat: return "לא אכל/ה"
        }
    }

    var iconSymbol: String {
        switch self {
        case .ateWell:   return "fork.knife"
        case .ateLittle: return "fork.knife.circle"
        case .didNotEat: return "xmark.circle"
        }
    }
}

enum CaregiverHydrationStatus: String, Codable, CaseIterable, Identifiable {
    case drankEnough
    case drankLittle
    case didNotDrink

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .drankEnough: return "שתה/תה מספיק"
        case .drankLittle: return "שתה/תה מעט"
        case .didNotDrink: return "לא שתה/תה"
        }
    }

    var iconSymbol: String {
        switch self {
        case .drankEnough: return "drop.fill"
        case .drankLittle: return "drop"
        case .didNotDrink: return "slash.circle"
        }
    }
}

enum CaregiverSleepStatus: String, Codable, CaseIterable, Identifiable {
    case sleptWell
    case sleptPoorly

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .sleptWell:   return "ישן/ה טוב"
        case .sleptPoorly: return "ישן/ה רע"
        }
    }

    var iconSymbol: String {
        switch self {
        case .sleptWell:   return "moon.zzz.fill"
        case .sleptPoorly: return "moon.zzz"
        }
    }
}

enum CaregiverMedicationStatus: String, Codable, CaseIterable, Identifiable {
    case taken
    case missed
    case notSure

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .taken:   return "תרופות נלקחו"
        case .missed:  return "תרופה לא נלקחה"
        case .notSure: return "לא בטוח/ה לגבי תרופות"
        }
    }

    var iconSymbol: String {
        switch self {
        case .taken:   return "pills.fill"
        case .missed:  return "exclamationmark.triangle.fill"
        case .notSure: return "questionmark.circle"
        }
    }
}

/// How much family attention a check-in needs.
enum CaregiverAttentionLevel: String, Codable, CaseIterable, Comparable {
    case ok
    case attention
    case urgent

    private var rank: Int {
        switch self {
        case .ok: return 0
        case .attention: return 1
        case .urgent: return 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    var hebrewLabel: String {
        switch self {
        case .ok:        return "מצב רגוע"
        case .attention: return "דורש תשומת לב"
        case .urgent:    return "דחוף"
        }
    }
}

// MARK: - Check-in model

/// A single report from the home caregiver. Stores the structured fields,
/// the original free text in the caregiver's language, and the Hebrew
/// summary generated for the family.
@Model
final class CaregiverCheckIn {
    @Attribute(.unique) var id: String
    var caregiverId: String
    var createdAt: Date

    var mealStatusRaw: String
    var hydrationStatusRaw: String
    var sleepStatusRaw: String
    var painLevel: Int        // 0–10
    var nauseaLevel: Int      // 0–10
    var fatigueLevel: Int     // 0–10

    var medicationStatusRaw: String
    var medicationNote: String?

    var freeTextOriginal: String?
    var originalLanguageRaw: String
    var translatedSummaryHebrew: String

    var attentionLevelRaw: String
    /// Hebrew, human-readable reasons the check-in was flagged.
    var alertReasons: [String]
    /// Set by the family from the detail view ("סמן כטופל").
    var isAcknowledged: Bool

    var mealStatus: CaregiverMealStatus {
        get { CaregiverMealStatus(rawValue: mealStatusRaw) ?? .ateLittle }
        set { mealStatusRaw = newValue.rawValue }
    }

    var hydrationStatus: CaregiverHydrationStatus {
        get { CaregiverHydrationStatus(rawValue: hydrationStatusRaw) ?? .drankLittle }
        set { hydrationStatusRaw = newValue.rawValue }
    }

    var sleepStatus: CaregiverSleepStatus {
        get { CaregiverSleepStatus(rawValue: sleepStatusRaw) ?? .sleptWell }
        set { sleepStatusRaw = newValue.rawValue }
    }

    var medicationStatus: CaregiverMedicationStatus {
        get { CaregiverMedicationStatus(rawValue: medicationStatusRaw) ?? .notSure }
        set { medicationStatusRaw = newValue.rawValue }
    }

    var originalLanguage: CaregiverLanguage {
        get { CaregiverLanguage(rawValue: originalLanguageRaw) ?? .english }
        set { originalLanguageRaw = newValue.rawValue }
    }

    var attentionLevel: CaregiverAttentionLevel {
        get { CaregiverAttentionLevel(rawValue: attentionLevelRaw) ?? .ok }
        set { attentionLevelRaw = newValue.rawValue }
    }

    var needsAttention: Bool { attentionLevel > .ok }

    init(
        id: String = UUID().uuidString,
        caregiverId: String,
        createdAt: Date = .now,
        mealStatus: CaregiverMealStatus,
        hydrationStatus: CaregiverHydrationStatus,
        sleepStatus: CaregiverSleepStatus,
        painLevel: Int,
        nauseaLevel: Int,
        fatigueLevel: Int,
        medicationStatus: CaregiverMedicationStatus,
        medicationNote: String? = nil,
        freeTextOriginal: String? = nil,
        originalLanguage: CaregiverLanguage,
        translatedSummaryHebrew: String,
        attentionLevel: CaregiverAttentionLevel = .ok,
        alertReasons: [String] = [],
        isAcknowledged: Bool = false
    ) {
        self.id = id
        self.caregiverId = caregiverId
        self.createdAt = createdAt
        self.mealStatusRaw = mealStatus.rawValue
        self.hydrationStatusRaw = hydrationStatus.rawValue
        self.sleepStatusRaw = sleepStatus.rawValue
        self.painLevel = painLevel
        self.nauseaLevel = nauseaLevel
        self.fatigueLevel = fatigueLevel
        self.medicationStatusRaw = medicationStatus.rawValue
        self.medicationNote = medicationNote
        self.freeTextOriginal = freeTextOriginal
        self.originalLanguageRaw = originalLanguage.rawValue
        self.translatedSummaryHebrew = translatedSummaryHebrew
        self.attentionLevelRaw = attentionLevel.rawValue
        self.alertReasons = alertReasons
        self.isAcknowledged = isAcknowledged
    }
}
