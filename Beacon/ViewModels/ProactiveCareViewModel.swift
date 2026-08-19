import Foundation
import Observation
import SwiftData

@Observable
final class ProactiveCareViewModel {
    private let context: ModelContext
    private let medicationService: MedicationService
    private let taskService: TaskService
    private let symptomService: SymptomService

    var doses: [MedicationDose] = []
    var medications: [Medication] = []
    var recentSymptoms: [SymptomEntry] = []
    var isSyncing: Bool = false

    init(
        context: ModelContext,
        medicationService: MedicationService = MedicationService(),
        taskService: TaskService = TaskService(),
        symptomService: SymptomService = SymptomService()
    ) {
        self.context = context
        self.medicationService = medicationService
        self.taskService = taskService
        self.symptomService = symptomService
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

    @MainActor
    func createRefillTask(for medication: Medication) async {
        let title = "קנה \(medication.name) - \(medication.dosageDescription)"
        let predicate = #Predicate<DailyTask> { task in
            task.title == title
        }
        let existing = (try? context.fetch(FetchDescriptor<DailyTask>(predicate: predicate))) ?? []
        guard existing.isEmpty else { return }

        let detail = "מלאי נמוך — \(medication.stockCount) נותרו"
        let created = await taskService.createAndInsert(
            title: title, detail: detail, kind: .logistics, origin: .aiSuggestion, in: context
        )
        if created == nil {
            context.insert(DailyTask(title: title, detail: detail, kind: .logistics, origin: .aiSuggestion))
            try? context.save()
        }
    }

    /// Fast local read — instant UI on appear, no network wait.
    func refresh() {
        let medDescriptor = FetchDescriptor<Medication>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        medications = (try? context.fetch(medDescriptor)) ?? []

        materializeTodaysDoses()

        let doseDescriptor = FetchDescriptor<MedicationDose>(
            sortBy: [SortDescriptor(\.scheduledAt, order: .forward)]
        )
        doses = (try? context.fetch(doseDescriptor)) ?? []

        var symptomDescriptor = FetchDescriptor<SymptomEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        symptomDescriptor.fetchLimit = 10
        recentSymptoms = (try? context.fetch(symptomDescriptor)) ?? []

        syncReminders()
    }

    /// Pulls medications, today's doses (materialized server-side so every
    /// device sees the same generated slots), and recent symptoms from the
    /// backend, reconciling them into local SwiftData. `refresh()`'s own
    /// local materialization runs afterwards and is a no-op for any slot
    /// this already created, since it dedups by medication name + minute.
    @MainActor
    func syncWithBackend() async {
        isSyncing = true
        defer { isSyncing = false }

        let medDTOs = (try? await medicationService.list()) ?? []
        for dto in medDTOs { upsertLocalMedication(from: dto) }
        removeStale(Medication.self, keeping: Set(medDTOs.map { $0.id.uuidString })) { $0.id }

        _ = try? await medicationService.materializeToday()
        let doseDTOs = (try? await medicationService.listDoses()) ?? []
        let nameById = Dictionary(uniqueKeysWithValues: medDTOs.map { ($0.id, $0.nameHe) })
        for dto in doseDTOs {
            upsertLocalDose(from: dto, medicationName: nameById[dto.medicationId] ?? "")
        }
        reconcileTodaysDoses(keeping: Set(doseDTOs.map { $0.id.uuidString }))

        let symptomDTOs = (try? await symptomService.list(limit: 30)) ?? []
        for dto in symptomDTOs { upsertLocalSymptom(from: dto) }
        // Symptom reports have no edit/delete endpoint — append-only, no reconciliation needed.

        try? context.save()
        refresh()
    }

    @discardableResult
    private func upsertLocalMedication(from dto: MedicationService.MedicationDTO) -> Medication {
        let targetId = dto.id.uuidString
        let predicate = #Predicate<Medication> { $0.id == targetId }
        let med = (try? context.fetch(FetchDescriptor<Medication>(predicate: predicate)))?.first
            ?? {
                let created = Medication(
                    id: targetId, name: dto.nameHe, dosageDescription: dto.dosage ?? "",
                    form: MedicationForm(rawValue: dto.form) ?? .pill, stockCount: dto.stockCount
                )
                context.insert(created)
                return created
            }()
        med.name = dto.nameHe
        med.dosageDescription = dto.dosage ?? ""
        med.usageInstructions = dto.usageInstructions
        med.form = MedicationForm(rawValue: dto.form) ?? .pill
        med.stockCount = dto.stockCount
        med.lowStockThreshold = dto.lowStockThreshold
        med.dosingTimesRaw = dto.dosingTimes.joined(separator: ",")
        return med
    }

    @discardableResult
    private func upsertLocalDose(from dto: MedicationService.DoseDTO, medicationName: String) -> MedicationDose {
        let targetId = dto.id.uuidString
        let predicate = #Predicate<MedicationDose> { $0.id == targetId }
        let med = medications.first { $0.id == dto.medicationId.uuidString }
        let dose = (try? context.fetch(FetchDescriptor<MedicationDose>(predicate: predicate)))?.first
            ?? {
                let created = MedicationDose(
                    id: targetId, medicationName: medicationName,
                    medicationDosage: med?.dosageDescription ?? "", usageInstructions: med?.usageInstructions,
                    form: med?.form ?? .pill, scheduledAt: dto.scheduledAt
                )
                context.insert(created)
                return created
            }()
        dose.medicationName = medicationName
        dose.medicationDosage = med?.dosageDescription ?? dose.medicationDosage
        dose.usageInstructions = med?.usageInstructions
        dose.form = med?.form ?? dose.form
        dose.scheduledAt = dto.scheduledAt
        dose.status = DoseStatus(rawValue: dto.status) ?? .upcoming
        dose.takenAt = dto.takenAt
        dose.note = dto.noteHe
        return dose
    }

    /// Only reconciles today's window — historical taken doses (kept as
    /// history, per `deleteFutureDoses`) must survive even though the
    /// backend's list defaults to today and won't return them.
    private func reconcileTodaysDoses(keeping fetchedIds: Set<String>) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? Date()
        let all = (try? context.fetch(FetchDescriptor<MedicationDose>())) ?? []
        for dose in all
        where dose.scheduledAt >= todayStart && dose.scheduledAt < todayEnd
            && UUID(uuidString: dose.id) != nil && !fetchedIds.contains(dose.id) {
            context.delete(dose)
        }
    }

    @discardableResult
    private func upsertLocalSymptom(from dto: SymptomService.SymptomDTO) -> SymptomEntry {
        let targetId = dto.id.uuidString
        let predicate = #Predicate<SymptomEntry> { $0.id == targetId }
        if let existing = (try? context.fetch(FetchDescriptor<SymptomEntry>(predicate: predicate)))?.first {
            return existing
        }
        let type = SymptomType(rawValue: dto.kind) ?? .custom
        let entry = SymptomEntry(
            id: targetId, type: type, customLabel: type == .custom ? dto.kind : nil,
            severity: dto.severity ?? 3, loggedAt: dto.createdAt
        )
        context.insert(entry)
        return entry
    }

    private func removeStale<T: PersistentModel>(
        _ type: T.Type, keeping fetchedIds: Set<String>, idOf: (T) -> String
    ) {
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        for item in all where UUID(uuidString: idOf(item)) != nil && !fetchedIds.contains(idOf(item)) {
            context.delete(item)
        }
    }

    /// Creates today's doses from each medication's recurring schedule
    /// (skipping slots that already exist), and flags doses that are more
    /// than two hours overdue as missed. Runs on every refresh, so the
    /// medication board keeps living day after day — and is a safe no-op
    /// for slots already materialized server-side by `syncWithBackend()`.
    private func materializeTodaysDoses() {
        let calendar = Calendar.current
        let now = Date()

        let existing = (try? context.fetch(FetchDescriptor<MedicationDose>())) ?? []
        var didChange = false

        for medication in medications where !medication.dosingMinutes.isEmpty {
            for minutes in medication.dosingMinutes {
                guard let slot = calendar.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0,
                    of: now
                ) else { continue }
                let alreadyExists = existing.contains {
                    $0.medicationName == medication.name &&
                    calendar.isDate($0.scheduledAt, equalTo: slot, toGranularity: .minute)
                }
                guard !alreadyExists else { continue }
                context.insert(MedicationDose(
                    medicationName: medication.name,
                    medicationDosage: medication.dosageDescription,
                    usageInstructions: medication.usageInstructions,
                    form: medication.form,
                    scheduledAt: slot,
                    status: .upcoming
                ))
                didChange = true
            }
        }

        // Two hours of grace before an untouched dose becomes "missed".
        let missedCutoff = now.addingTimeInterval(-2 * 3600)
        for dose in existing where dose.status == .upcoming && dose.scheduledAt < missedCutoff {
            dose.status = .missed
            didChange = true
        }

        if didChange { try? context.save() }
    }

    private func syncReminders() {
        let upcoming = doses.filter { $0.status == .upcoming }
        guard !upcoming.isEmpty else { return }
        Task {
            await DoseReminderService.requestAuthorizationIfNeeded()
            await DoseReminderService.syncReminders(for: upcoming)
        }
    }

    // MARK: - Medication management (edit / delete)

    @MainActor
    func updateMedication(
        _ medication: Medication,
        name: String,
        dosageDescription: String,
        form: MedicationForm,
        doseTimes: [Date],
        usageInstructions: String,
        stockCount: Int
    ) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedDosage = dosageDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = usageInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let dosingTimes = doseTimes.map { time -> String in
            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }

        deleteFutureDoses(medicationName: medication.name)

        if let id = UUID(uuidString: medication.id) {
            // Note: the backend does not yet clean up dose events generated
            // under the old schedule — only local future doses are rebuilt
            // here. A stale slot from before the edit may briefly reappear
            // from another device until it's marked taken/missed.
            _ = try? await medicationService.update(
                medicationId: id, nameHe: trimmedName, dosage: trimmedDosage, form: form.rawValue,
                usageInstructions: instructions.isEmpty ? nil : instructions,
                stockCount: stockCount, dosingTimes: dosingTimes
            )
        }

        medication.name = trimmedName
        medication.dosageDescription = trimmedDosage
        medication.usageInstructions = instructions.isEmpty ? nil : instructions
        medication.form = form
        medication.stockCount = stockCount
        medication.dosingTimesRaw = Medication.encodeDosingTimes(doseTimes)
        try? context.save()
        refresh()   // re-materializes today's doses from the new schedule
    }

    @MainActor
    func deleteMedication(_ medication: Medication) async {
        deleteFutureDoses(medicationName: medication.name)
        if let id = UUID(uuidString: medication.id) {
            _ = try? await medicationService.delete(medicationId: id)
        }
        context.delete(medication)
        try? context.save()
        refresh()
    }

    /// Future doses are rebuilt from the schedule; past ones stay as history.
    private func deleteFutureDoses(medicationName: String) {
        let now = Date()
        let all = (try? context.fetch(FetchDescriptor<MedicationDose>())) ?? []
        for dose in all
        where dose.medicationName == medicationName && dose.scheduledAt > now && dose.status != .taken {
            DoseReminderService.cancelReminder(doseId: dose.id)
            context.delete(dose)
        }
    }

    @MainActor
    func markTaken(_ dose: MedicationDose) async {
        if let id = UUID(uuidString: dose.id) {
            _ = try? await medicationService.markTaken(doseId: id)
        }
        dose.status = .taken
        dose.takenAt = Date()
        DoseReminderService.cancelReminder(doseId: dose.id)
        // Taking a dose consumes stock — keeps the low-stock nudge honest.
        if let medication = medications.first(where: { $0.name == dose.medicationName }),
           medication.stockCount > 0 {
            medication.stockCount -= 1
            if let medId = UUID(uuidString: medication.id) {
                _ = try? await medicationService.update(medicationId: medId, stockCount: medication.stockCount)
            }
        }
        try? context.save()
        refresh()
    }

    @MainActor
    func resolveMissed(_ dose: MedicationDose, markAsTaken: Bool, note: String? = nil) async {
        if markAsTaken {
            if let id = UUID(uuidString: dose.id) {
                _ = try? await medicationService.markTaken(doseId: id, noteHe: note)
            }
            dose.status = .taken
            dose.takenAt = Date()
        }
        if let note { dose.note = note }
        try? context.save()
        refresh()
    }

    @MainActor
    func logSymptom(_ type: SymptomType, severity: Int = 3, customLabel: String? = nil) async {
        let kindForWire = type == .custom ? (customLabel ?? "מדד") : type.rawValue
        if let dto = try? await symptomService.report(kind: kindForWire, severity: severity, noteHe: nil) {
            upsertLocalSymptom(from: dto)
        } else {
            context.insert(SymptomEntry(type: type, customLabel: customLabel, severity: severity))
        }
        try? context.save()
        refresh()
    }

    @MainActor
    func logCustomSymptom(label: String, severity: Int, note: String?) async {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let dto = try? await symptomService.report(kind: trimmed, severity: severity, noteHe: note) {
            let entry = upsertLocalSymptom(from: dto)
            entry.note = note
        } else {
            context.insert(SymptomEntry(type: .custom, customLabel: trimmed, severity: severity, note: note))
        }
        try? context.save()
        refresh()
    }
}
