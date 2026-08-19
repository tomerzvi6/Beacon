import Foundation
import SwiftData

/// Family → caregiver instructions. The structure (kind) is what gets
/// "translated" — each kind carries a pre-localized title in every
/// supported caregiver language, so no LLM is needed for the MVP. The
/// free-text `detail` is shown as typed (medication names are Latin and
/// times are numbers, so it stays readable across languages).
enum CaregiverInstructionKind: String, Codable, CaseIterable, Identifiable {
    case giveMedication
    case encourageDrinking
    case prepareForAppointment
    case fastingBeforeTest
    case callFamilyIf
    case custom

    var id: String { rawValue }

    /// Shown to the family when composing.
    var hebrewLabel: String {
        switch self {
        case .giveMedication:        return "לתת תרופה"
        case .encourageDrinking:     return "להקפיד על שתייה"
        case .prepareForAppointment: return "הכנה לתור רפואי"
        case .fastingBeforeTest:     return "צום לפני בדיקה"
        case .callFamilyIf:          return "להתקשר אלינו אם…"
        case .custom:                return "הוראה חופשית"
        }
    }

    /// Placeholder for the family's free-text parameter.
    var detailPlaceholder: String {
        switch self {
        case .giveMedication:        return "למשל: Acamol בשעה 14:00"
        case .encourageDrinking:     return "למשל: לפחות 6 כוסות היום"
        case .prepareForAppointment: return "למשל: מחר 09:00, רמב\"ם"
        case .fastingBeforeTest:     return "למשל: החל מ-22:00 הערב"
        case .callFamilyIf:          return "למשל: חום מעל 38 או כאב חזק"
        case .custom:                return "כתבו הוראה קצרה"
        }
    }

    var iconSymbol: String {
        switch self {
        case .giveMedication:        return "pills.fill"
        case .encourageDrinking:     return "drop.fill"
        case .prepareForAppointment: return "calendar.badge.clock"
        case .fastingBeforeTest:     return "fork.knife.circle"
        case .callFamilyIf:          return "phone.fill"
        case .custom:                return "text.bubble.fill"
        }
    }

    /// Title in the caregiver's language.
    func localizedTitle(for language: CaregiverLanguage) -> String {
        switch language {
        case .english:
            switch self {
            case .giveMedication:        return "Give medication"
            case .encourageDrinking:     return "Encourage drinking"
            case .prepareForAppointment: return "Doctor appointment — please prepare"
            case .fastingBeforeTest:     return "No food before the test"
            case .callFamilyIf:          return "Call the family if:"
            case .custom:                return "Note from the family"
            }
        case .tagalog:
            switch self {
            case .giveMedication:        return "Ibigay ang gamot"
            case .encourageDrinking:     return "Paalalahanan uminom ng tubig"
            case .prepareForAppointment: return "May appointment sa doktor — ihanda"
            case .fastingBeforeTest:     return "Walang pagkain bago ang test"
            case .callFamilyIf:          return "Tawagan ang pamilya kung:"
            case .custom:                return "Mensahe mula sa pamilya"
            }
        case .hindi:
            switch self {
            case .giveMedication:        return "दवा दें"
            case .encourageDrinking:     return "पानी पीने के लिए प्रोत्साहित करें"
            case .prepareForAppointment: return "डॉक्टर की अपॉइंटमेंट — तैयारी करें"
            case .fastingBeforeTest:     return "जाँच से पहले खाना नहीं"
            case .callFamilyIf:          return "परिवार को फ़ोन करें अगर:"
            case .custom:                return "परिवार की ओर से संदेश"
            }
        case .malayalam:
            switch self {
            case .giveMedication:        return "മരുന്ന് നൽകുക"
            case .encourageDrinking:     return "വെള്ളം കുടിക്കാൻ പ്രോത്സാഹിപ്പിക്കുക"
            case .prepareForAppointment: return "ഡോക്ടർ അപ്പോയിന്റ്മെന്റ് — തയ്യാറാക്കുക"
            case .fastingBeforeTest:     return "പരിശോധനയ്ക്ക് മുമ്പ് ഭക്ഷണം വേണ്ട"
            case .callFamilyIf:          return "കുടുംബത്തെ വിളിക്കുക:"
            case .custom:                return "കുടുംബത്തിൽ നിന്നുള്ള സന്ദേശം"
            }
        case .tamil:
            switch self {
            case .giveMedication:        return "மருந்து கொடுக்கவும்"
            case .encourageDrinking:     return "தண்ணீர் குடிக்க ஊக்குவிக்கவும்"
            case .prepareForAppointment: return "மருத்துவர் சந்திப்பு — தயார் செய்யவும்"
            case .fastingBeforeTest:     return "பரிசோதனைக்கு முன் உணவு வேண்டாம்"
            case .callFamilyIf:          return "குடும்பத்தை அழைக்கவும்:"
            case .custom:                return "குடும்பத்திடமிருந்து செய்தி"
            }
        }
    }

    /// Section header on the caregiver's report screen.
    static func sectionHeader(for language: CaregiverLanguage) -> String {
        switch language {
        case .english:   return "Instructions from the family"
        case .tagalog:   return "Mga bilin ng pamilya"
        case .hindi:     return "परिवार के निर्देश"
        case .malayalam: return "കുടുംബത്തിന്റെ നിർദ്ദേശങ്ങൾ"
        case .tamil:     return "குடும்பத்தின் அறிவுரைகள்"
        }
    }
}

@Model
final class CaregiverInstruction {
    @Attribute(.unique) var id: String
    var kindRaw: String
    /// Family free text (medication + hour, threshold, etc.). May be empty.
    var detail: String
    var createdByName: String
    var createdAt: Date
    var isActive: Bool

    var kind: CaregiverInstructionKind {
        get { CaregiverInstructionKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        kind: CaregiverInstructionKind,
        detail: String,
        createdByName: String,
        createdAt: Date = .now,
        isActive: Bool = true
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.detail = detail
        self.createdByName = createdByName
        self.createdAt = createdAt
        self.isActive = isActive
    }
}
