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
    /// Recurring daily schedule as "HH:mm,HH:mm". Empty string = no
    /// recurrence (e.g. demo-seeded meds whose doses are seeded directly).
    /// Doses are materialized from this every day — see
    /// `ProactiveCareViewModel.materializeTodaysDoses()`.
    var dosingTimesRaw: String = ""

    var form: MedicationForm {
        get { MedicationForm(rawValue: formRaw) ?? .pill }
        set { formRaw = newValue.rawValue }
    }

    var isLowStock: Bool { stockCount <= lowStockThreshold }

    /// Scheduled times as minutes-since-midnight, sorted.
    var dosingMinutes: [Int] {
        dosingTimesRaw
            .split(separator: ",")
            .compactMap { part -> Int? in
                let pieces = part.split(separator: ":")
                guard pieces.count == 2,
                      let hour = Int(pieces[0]), let minute = Int(pieces[1]),
                      (0..<24).contains(hour), (0..<60).contains(minute)
                else { return nil }
                return hour * 60 + minute
            }
            .sorted()
    }

    /// Today's `Date`s for each scheduled slot — for time pickers.
    var dosingTimesAsDates: [Date] {
        let calendar = Calendar.current
        let now = Date()
        return dosingMinutes.compactMap {
            calendar.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: now)
        }
    }

    static func encodeDosingTimes(_ times: [Date]) -> String {
        let calendar = Calendar.current
        return times
            .map { calendar.dateComponents([.hour, .minute], from: $0) }
            .sorted { ($0.hour ?? 0, $0.minute ?? 0) < ($1.hour ?? 0, $1.minute ?? 0) }
            .map { String(format: "%02d:%02d", $0.hour ?? 0, $0.minute ?? 0) }
            .joined(separator: ",")
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        dosageDescription: String,
        usageInstructions: String? = nil,
        form: MedicationForm,
        stockCount: Int,
        lowStockThreshold: Int = 5,
        dosingTimesRaw: String = ""
    ) {
        self.id = id
        self.name = name
        self.dosageDescription = dosageDescription
        self.usageInstructions = usageInstructions
        self.formRaw = form.rawValue
        self.stockCount = stockCount
        self.lowStockThreshold = lowStockThreshold
        self.dosingTimesRaw = dosingTimesRaw
    }
}
