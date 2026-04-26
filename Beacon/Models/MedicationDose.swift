import Foundation
import SwiftData

enum DoseStatus: String, Codable, CaseIterable {
    case upcoming
    case taken
    case missed
    case scheduledLater

    var displayLabel: String {
        switch self {
        case .upcoming: return "עכשיו"
        case .taken: return "נלקח"
        case .missed: return "חסר"
        case .scheduledLater: return "מתוכנן לערב"
        }
    }
}

@Model
final class MedicationDose {
    @Attribute(.unique) var id: String
    var medicationName: String
    var medicationDosage: String
    var usageInstructions: String?
    var formRaw: String
    var scheduledAt: Date
    var statusRaw: String
    var takenAt: Date?
    var note: String?

    var form: MedicationForm {
        get { MedicationForm(rawValue: formRaw) ?? .pill }
        set { formRaw = newValue.rawValue }
    }

    var status: DoseStatus {
        get { DoseStatus(rawValue: statusRaw) ?? .upcoming }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        medicationName: String,
        medicationDosage: String,
        usageInstructions: String? = nil,
        form: MedicationForm,
        scheduledAt: Date,
        status: DoseStatus = .upcoming,
        takenAt: Date? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.medicationName = medicationName
        self.medicationDosage = medicationDosage
        self.usageInstructions = usageInstructions
        self.formRaw = form.rawValue
        self.scheduledAt = scheduledAt
        self.statusRaw = status.rawValue
        self.takenAt = takenAt
        self.note = note
    }
}
