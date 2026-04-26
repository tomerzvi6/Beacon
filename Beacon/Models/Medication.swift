import Foundation
import SwiftData

enum MedicationForm: String, Codable, CaseIterable {
    case pill
    case injection
    case syrup
    case patch

    var iconSymbol: String {
        switch self {
        case .pill: return "pills.fill"
        case .injection: return "syringe.fill"
        case .syrup: return "drop.fill"
        case .patch: return "bandage.fill"
        }
    }
}

@Model
final class Medication {
    @Attribute(.unique) var id: String
    var name: String
    var dosageDescription: String
    var usageInstructions: String?
    var formRaw: String
    var stockCount: Int
    var lowStockThreshold: Int

    var form: MedicationForm {
        get { MedicationForm(rawValue: formRaw) ?? .pill }
        set { formRaw = newValue.rawValue }
    }

    var isLowStock: Bool { stockCount <= lowStockThreshold }

    init(
        id: String = UUID().uuidString,
        name: String,
        dosageDescription: String,
        usageInstructions: String? = nil,
        form: MedicationForm,
        stockCount: Int,
        lowStockThreshold: Int = 5
    ) {
        self.id = id
        self.name = name
        self.dosageDescription = dosageDescription
        self.usageInstructions = usageInstructions
        self.formRaw = form.rawValue
        self.stockCount = stockCount
        self.lowStockThreshold = lowStockThreshold
    }
}
