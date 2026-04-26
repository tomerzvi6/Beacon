import Foundation

enum PatientWellness: String, Codable, CaseIterable, Identifiable {
    case great
    case stable
    case tired
    case rough

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .great: return "מרגיש מצוין"
        case .stable: return "מצב יציב"
        case .tired: return "עייף יותר"
        case .rough: return "יום קשה"
        }
    }

    var emoji: String {
        switch self {
        case .great: return "🌞"
        case .stable: return "🌿"
        case .tired: return "🌥️"
        case .rough: return "🌧️"
        }
    }
}

struct Patient: Identifiable, Hashable {
    let id: String
    let displayName: String
    let relationToCaregiver: String
    let avatarSymbol: String
    let age: Int
    let condition: String
    let primaryDoctor: String
    let primaryHospital: String
    let bloodType: String
    let allergies: [String]
    let emergencyContactName: String
    let emergencyContactPhone: String

    var todaysWellness: PatientWellness

    static let primary = Patient(
        id: "aba",
        displayName: "אבא (יוסף)",
        relationToCaregiver: "אב",
        avatarSymbol: "person.crop.circle.fill",
        age: 71,
        condition: "אונקולוגי - לימפומה",
        primaryDoctor: "ד״ר לוי",
        primaryHospital: "בי״ח שיבא",
        bloodType: "A+",
        allergies: ["פניצילין", "אגוזים"],
        emergencyContactName: "רונית (בת)",
        emergencyContactPhone: "050-1234567",
        todaysWellness: .stable
    )
}
