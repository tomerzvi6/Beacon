import Foundation
import Observation
import SwiftData

/// Saves confirmed intake drafts (independent mode) into SwiftData and the
/// backend. Medications become a `Medication` plus scheduled
/// `MedicationDose`s; appointments become a `ScheduleEvent` on the family
/// calendar — both created on the backend first so every device in the
/// household sees them, falling back to a local-only insert if offline.
@Observable
final class IntakeViewModel {
    private let context: ModelContext
    private let medicationService: MedicationService
    private let scheduleService: ScheduleService

    init(
        context: ModelContext,
        medicationService: MedicationService = MedicationService(),
        scheduleService: ScheduleService = ScheduleService()
    ) {
        self.context = context
        self.medicationService = medicationService
        self.scheduleService = scheduleService
    }

    /// Standard Israeli dosing hours per daily frequency — the editable
    /// starting point shown in the confirmation form.
    static func defaultHours(forTimesPerDay times: Int) -> [Int] {
        switch times {
        case 1: return [8]
        case 2: return [8, 20]
        case 3: return [8, 14, 20]
        default: return [6, 12, 18, 22]
        }
    }

    /// Same defaults as concrete `Date`s (today), for time pickers.
    static func defaultTimes(forTimesPerDay times: Int) -> [Date] {
        let calendar = Calendar.current
        let now = Date()
        return defaultHours(forTimesPerDay: times).compactMap {
            calendar.date(bySettingHour: $0, minute: 0, second: 0, of: now)
        }
    }

    /// Creates the medication and its dose schedule from user-confirmed
    /// times. Times that already passed today are scheduled for tomorrow
    /// so nothing is born "missed". The initial dose rows are a local
    /// preview; the next backend sync reconciles them with the
    /// server-materialized ones for today (and self-heals the "pushed to
    /// tomorrow" one once tomorrow's materialize call creates its real row).
    @MainActor
    func saveMedication(
        name: String,
        dosageDescription: String,
        form: MedicationForm,
        doseTimes: [Date],
        usageInstructions: String,
        stockCount: Int
    ) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let dosage = dosageDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = usageInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let dosingTimes = doseTimes.map { time -> String in
            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }

        let medicationId: String
        if let dto = try? await medicationService.create(
            nameHe: trimmedName, dosage: dosage, form: form.rawValue,
            usageInstructions: instructions.isEmpty ? nil : instructions,
            stockCount: stockCount, lowStockThreshold: 5, dosingTimes: dosingTimes
        ) {
            medicationId = dto.id.uuidString
        } else {
            medicationId = UUID().uuidString
        }

        let medication = Medication(
            id: medicationId,
            name: trimmedName,
            dosageDescription: dosage,
            usageInstructions: instructions.isEmpty ? nil : instructions,
            form: form,
            stockCount: stockCount,
            dosingTimesRaw: Medication.encodeDosingTimes(doseTimes)
        )
        context.insert(medication)

        let calendar = Calendar.current
        let now = Date()
        for time in doseTimes {
            let components = calendar.dateComponents([.hour, .minute], from: time)
            guard let todaySlot = calendar.date(
                bySettingHour: components.hour ?? 8,
                minute: components.minute ?? 0,
                second: 0,
                of: now
            ) else { continue }
            let slot = todaySlot > now
                ? todaySlot
                : calendar.date(byAdding: .day, value: 1, to: todaySlot) ?? todaySlot
            let dose = MedicationDose(
                medicationName: trimmedName,
                medicationDosage: dosage,
                usageInstructions: instructions.isEmpty ? nil : instructions,
                form: form,
                scheduledAt: slot,
                status: .upcoming
            )
            context.insert(dose)
        }
        try? context.save()
    }

    /// Creates a medical appointment on the family schedule.
    @MainActor
    func saveAppointment(
        title: String,
        startsAt: Date,
        locationName: String,
        subtitle: String
    ) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let location = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)

        let dto = try? await scheduleService.create(
            title: trimmedTitle, startsAt: startsAt, kind: "medical",
            locationName: location.isEmpty ? nil : location, subtitle: note.isEmpty ? nil : note
        )

        let event = ScheduleEvent(
            id: dto?.id.uuidString ?? UUID().uuidString,
            title: trimmedTitle,
            startsAt: startsAt,
            kind: .medical,
            locationName: location.isEmpty ? nil : location,
            subtitle: note.isEmpty ? nil : note
        )
        context.insert(event)
        try? context.save()
    }
}
