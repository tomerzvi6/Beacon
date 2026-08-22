import Foundation

/// Hebrew is a grammatically gendered language — every place the app
/// addresses or describes the patient needs to pick the right verb/adjective
/// form. Defaults to `.male` only to match this file's pre-existing demo
/// patient; onboarding always asks explicitly for a real patient.
enum PatientGender: String, Codable, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .male: return "זכר"
        case .female: return "נקבה"
        }
    }
}

enum PatientWellness: String, Codable, CaseIterable, Identifiable {
    case great
    case stable
    case tired
    case rough

    var id: String { rawValue }

    func displayLabel(for gender: PatientGender) -> String {
        switch (self, gender) {
        case (.great, .male): return "מרגיש מצוין"
        case (.great, .female): return "מרגישה מצוין"
        case (.stable, _): return "מצב יציב"
        case (.tired, .male): return "עייף יותר"
        case (.tired, .female): return "עייפה יותר"
        case (.rough, _): return "יום קשה"
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
    let gender: PatientGender
    let condition: String
    let primaryDoctor: String
    let primaryHospital: String
    /// קופת חולים — many patients only have this, not a specific hospital
    /// file (e.g. no hospital-based treatment yet). Both are optional.
    let healthFund: String
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
        gender: .male,
        condition: "אונקולוגי - לימפומה",
        primaryDoctor: "ד״ר לוי",
        primaryHospital: "בי״ח שיבא",
        healthFund: "",
        bloodType: "A+",
        allergies: ["פניצילין", "אגוזים"],
        emergencyContactName: "רונית (בת)",
        emergencyContactPhone: "050-1234567",
        todaysWellness: .stable
    )
}
