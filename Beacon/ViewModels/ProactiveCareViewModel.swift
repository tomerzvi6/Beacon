import Foundation
import Observation
import SwiftData

@Observable
final class ProactiveCareViewModel {
    private let context: ModelContext

    var doses: [MedicationDose] = []
    var medications: [Medication] = []
    var recentSymptoms: [SymptomEntry] = []

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    var missedDose: MedicationDose? {
        doses.first { $0.status == .missed }
    }

    var upcomingDoses: [MedicationDose] {
        doses.filter { $0.status != .missed }
    }

    var remainingCount: Int {
        doses.filter { $0.status == .upcoming || $0.status == .scheduledLater }.count
    }

    var lowStockMedications: [Medication] {
        medications.filter { $0.isLowStock }
    }

    func createRefillTask(for medication: Medication) {
        let title = "קנה \(medication.name) - \(medication.dosageDescription)"
        let predicate = #Predicate<DailyTask> { task in
            task.title == title
        }
        let existing = (try? context.fetch(FetchDescriptor<DailyTask>(predicate: predicate))) ?? []
        guard existing.isEmpty else { return }

        let task = DailyTask(
            title: title,
            detail: "מלאי נמוך — \(medication.stockCount) נותרו",
            kind: .logistics,
            origin: .aiSuggestion
        )
        context.insert(task)
        try? context.save()
    }

    func refresh() {
        let doseDescriptor = FetchDescriptor<MedicationDose>(
            sortBy: [SortDescriptor(\.scheduledAt, order: .forward)]
        )
        doses = (try? context.fetch(doseDescriptor)) ?? []

        let medDescriptor = FetchDescriptor<Medication>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        medications = (try? context.fetch(medDescriptor)) ?? []

        var symptomDescriptor = FetchDescriptor<SymptomEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        symptomDescriptor.fetchLimit = 10
        recentSymptoms = (try? context.fetch(symptomDescriptor)) ?? []
    }

    func markTaken(_ dose: MedicationDose) {
        dose.status = .taken
        dose.takenAt = Date()
        try? context.save()
        refresh()
    }

    func resolveMissed(_ dose: MedicationDose, markAsTaken: Bool, note: String? = nil) {
        if markAsTaken {
            dose.status = .taken
            dose.takenAt = Date()
        }
        if let note { dose.note = note }
        try? context.save()
        refresh()
    }

    func logSymptom(_ type: SymptomType, severity: Int = 3, customLabel: String? = nil) {
        let entry = SymptomEntry(
            type: type,
            customLabel: customLabel,
            severity: severity
        )
        context.insert(entry)
        try? context.save()
        refresh()
    }

    func logCustomSymptom(label: String, severity: Int, note: String?) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = SymptomEntry(
            type: .custom,
            customLabel: trimmed,
            severity: severity,
            note: note
        )
        context.insert(entry)
        try? context.save()
        refresh()
    }
}
