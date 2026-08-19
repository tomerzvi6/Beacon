import Foundation
import Observation
import SwiftData

/// Owns the optional "home caregiver" layer: the active caregiver profile,
/// check-in creation (including Hebrew summary + alert detection), and the
/// latest check-in surfaced on the family dashboard.
@Observable
final class CaregiverLayerViewModel {
    private let context: ModelContext
    private let translationService: CaregiverTranslationServiceProtocol
    private let caregiverService: CaregiverService
    private let taskService: TaskService
    private let feedService: FeedService
    private let symptomService: SymptomService

    private(set) var activeCaregiver: CaregiverProfile?
    private(set) var latestCheckIn: CaregiverCheckIn?
    private(set) var recentCheckIns: [CaregiverCheckIn] = []
    private(set) var activeInstructions: [CaregiverInstruction] = []
    var isSyncing: Bool = false

    init(
        context: ModelContext,
        translationService: CaregiverTranslationServiceProtocol = LocalMockCaregiverTranslationService(),
        caregiverService: CaregiverService = CaregiverService(),
        taskService: TaskService = TaskService(),
        feedService: FeedService = FeedService(),
        symptomService: SymptomService = SymptomService()
    ) {
        self.context = context
        self.translationService = translationService
        self.caregiverService = caregiverService
        self.taskService = taskService
        self.feedService = feedService
        self.symptomService = symptomService
        refresh()
    }

    var isCaregiverLayerActive: Bool { activeCaregiver != nil }

    /// True when the dashboard should show the caregiver update card.
    var hasDashboardUpdate: Bool { activeCaregiver != nil && latestCheckIn != nil }

    /// Fast local read — instant UI on appear, no network wait.
    func refresh() {
        let caregiverDescriptor = FetchDescriptor<CaregiverProfile>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        activeCaregiver = ((try? context.fetch(caregiverDescriptor)) ?? []).first

        var checkInDescriptor = FetchDescriptor<CaregiverCheckIn>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        checkInDescriptor.fetchLimit = 20
        recentCheckIns = (try? context.fetch(checkInDescriptor)) ?? []
        latestCheckIn = recentCheckIns.first

        let instructionDescriptor = FetchDescriptor<CaregiverInstruction>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        activeInstructions = (try? context.fetch(instructionDescriptor)) ?? []
    }

    /// Pulls caregiver profiles/check-ins/instructions from the backend and
    /// reconciles them into local SwiftData.
    @MainActor
    func syncWithBackend() async {
        isSyncing = true
        defer { isSyncing = false }
        async let profilesTask = try? caregiverService.listProfiles()
        async let checkInsTask = try? caregiverService.listCheckIns()
        async let instructionsTask = try? caregiverService.listInstructions()
        let (profiles, checkIns, instructions) = await (profilesTask, checkInsTask, instructionsTask)

        let fetchedProfiles = profiles ?? []
        for dto in fetchedProfiles { upsertLocalProfile(from: dto) }
        removeStale(CaregiverProfile.self, keeping: Set(fetchedProfiles.map { $0.id.uuidString })) { $0.id }

        let fetchedCheckIns = checkIns ?? []
        for dto in fetchedCheckIns { upsertLocalCheckIn(from: dto) }
        removeStale(CaregiverCheckIn.self, keeping: Set(fetchedCheckIns.map { $0.id.uuidString })) { $0.id }

        let fetchedInstructions = instructions ?? []
        for dto in fetchedInstructions { upsertLocalInstruction(from: dto) }
        removeStale(CaregiverInstruction.self, keeping: Set(fetchedInstructions.map { $0.id.uuidString })) { $0.id }

        try? context.save()
        refresh()
    }

    /// Deletes local rows whose id round-trips as a UUID (i.e. came from a
    /// prior backend sync) but is no longer in the latest fetch.
    private func removeStale<T: PersistentModel>(
        _ type: T.Type, keeping fetchedIds: Set<String>, idOf: (T) -> String
    ) {
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        for item in all where UUID(uuidString: idOf(item)) != nil && !fetchedIds.contains(idOf(item)) {
            context.delete(item)
        }
    }

    @discardableResult
    private func upsertLocalProfile(from dto: CaregiverService.ProfileDTO) -> CaregiverProfile {
        let targetId = dto.id.uuidString
        let predicate = #Predicate<CaregiverProfile> { $0.id == targetId }
        let profile = (try? context.fetch(FetchDescriptor<CaregiverProfile>(predicate: predicate)))?.first
            ?? {
                let created = CaregiverProfile(id: targetId, displayName: dto.displayName)
                context.insert(created)
                return created
            }()
        profile.displayName = dto.displayName
        profile.relationTitle = dto.relationTitle
        profile.preferredLanguage = CaregiverLanguage(rawValue: dto.preferredLanguage) ?? .english
        profile.isActive = dto.isActive
        return profile
    }

    @discardableResult
    private func upsertLocalCheckIn(from dto: CaregiverService.CheckInDTO) -> CaregiverCheckIn {
        let targetId = dto.id.uuidString
        let predicate = #Predicate<CaregiverCheckIn> { $0.id == targetId }
        let checkIn = (try? context.fetch(FetchDescriptor<CaregiverCheckIn>(predicate: predicate)))?.first
            ?? {
                let created = CaregiverCheckIn(
                    id: targetId,
                    caregiverId: dto.caregiverId.uuidString,
                    mealStatus: CaregiverMealStatus(rawValue: dto.mealStatus) ?? .ateLittle,
                    hydrationStatus: CaregiverHydrationStatus(rawValue: dto.hydrationStatus) ?? .drankLittle,
                    sleepStatus: CaregiverSleepStatus(rawValue: dto.sleepStatus) ?? .sleptWell,
                    painLevel: dto.painLevel, nauseaLevel: dto.nauseaLevel, fatigueLevel: dto.fatigueLevel,
                    medicationStatus: CaregiverMedicationStatus(rawValue: dto.medicationStatus) ?? .notSure,
                    originalLanguage: CaregiverLanguage(rawValue: dto.originalLanguage) ?? .english,
                    translatedSummaryHebrew: dto.translatedSummaryHebrew
                )
                context.insert(created)
                return created
            }()
        checkIn.mealStatus = CaregiverMealStatus(rawValue: dto.mealStatus) ?? .ateLittle
        checkIn.hydrationStatus = CaregiverHydrationStatus(rawValue: dto.hydrationStatus) ?? .drankLittle
        checkIn.sleepStatus = CaregiverSleepStatus(rawValue: dto.sleepStatus) ?? .sleptWell
        checkIn.painLevel = dto.painLevel
        checkIn.nauseaLevel = dto.nauseaLevel
        checkIn.fatigueLevel = dto.fatigueLevel
        checkIn.medicationStatus = CaregiverMedicationStatus(rawValue: dto.medicationStatus) ?? .notSure
        checkIn.medicationNote = dto.medicationNote
        checkIn.freeTextOriginal = dto.freeTextOriginal
        checkIn.originalLanguage = CaregiverLanguage(rawValue: dto.originalLanguage) ?? .english
        checkIn.translatedSummaryHebrew = dto.translatedSummaryHebrew
        checkIn.attentionLevel = CaregiverAttentionLevel(rawValue: dto.attentionLevel) ?? .ok
        checkIn.alertReasons = dto.alertReasons
        checkIn.isAcknowledged = dto.isAcknowledged
        return checkIn
    }

    @discardableResult
    private func upsertLocalInstruction(from dto: CaregiverService.InstructionDTO) -> CaregiverInstruction {
        let targetId = dto.id.uuidString
        let predicate = #Predicate<CaregiverInstruction> { $0.id == targetId }
        let instruction = (try? context.fetch(FetchDescriptor<CaregiverInstruction>(predicate: predicate)))?.first
            ?? {
                let created = CaregiverInstruction(
                    id: targetId,
                    kind: CaregiverInstructionKind(rawValue: dto.kind) ?? .custom,
                    detail: dto.detail,
                    createdByName: dto.createdByName
                )
                context.insert(created)
                return created
            }()
        instruction.kindRaw = dto.kind
        instruction.detail = dto.detail
        instruction.createdByName = dto.createdByName
        instruction.isActive = dto.isActive
        return instruction
    }

    /// True when no check-in was submitted today — drives the dashboard
    /// "hand the phone over" nudge.
    var isMissingTodaysCheckIn: Bool {
        guard activeCaregiver != nil else { return false }
        guard let latest = latestCheckIn else { return true }
        return !Calendar.current.isDateInToday(latest.createdAt)
    }

    // MARK: - Family → caregiver instructions

    @MainActor
    func addInstruction(kind: CaregiverInstructionKind, detail: String, createdByName: String) async {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        // Free-form instructions are meaningless without text.
        guard kind != .custom || !trimmed.isEmpty else { return }
        if let dto = try? await caregiverService.createInstruction(kind: kind.rawValue, detail: trimmed) {
            upsertLocalInstruction(from: dto)
        } else {
            context.insert(CaregiverInstruction(kind: kind, detail: trimmed, createdByName: createdByName))
        }
        save()
    }

    @MainActor
    func removeInstruction(_ instruction: CaregiverInstruction) async {
        if let id = UUID(uuidString: instruction.id) {
            _ = try? await caregiverService.deactivateInstruction(instructionId: id)
        }
        instruction.isActive = false
        save()
    }

    // MARK: - Family-side setup

    @MainActor
    func activateCaregiver(name: String, relationTitle: String, language: CaregiverLanguage) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let resolvedTitle = relationTitle.isEmpty ? "מטפל/ת סיעודי/ת" : relationTitle

        if let existing = activeCaregiver, let id = UUID(uuidString: existing.id) {
            if let dto = try? await caregiverService.patchProfile(
                profileId: id, displayName: trimmedName, relationTitle: resolvedTitle,
                preferredLanguage: language.rawValue
            ) {
                upsertLocalProfile(from: dto)
            } else {
                existing.displayName = trimmedName
                existing.relationTitle = resolvedTitle
                existing.preferredLanguage = language
            }
        } else if let dto = try? await caregiverService.createProfile(
            displayName: trimmedName, relationTitle: resolvedTitle, preferredLanguage: language.rawValue
        ) {
            upsertLocalProfile(from: dto)
        } else {
            context.insert(CaregiverProfile(displayName: trimmedName, relationTitle: resolvedTitle, preferredLanguage: language))
        }
        save()
    }

    @MainActor
    func deactivateCaregiver() async {
        guard let caregiver = activeCaregiver else { return }
        if let id = UUID(uuidString: caregiver.id) {
            _ = try? await caregiverService.patchProfile(profileId: id, isActive: false)
        }
        caregiver.isActive = false
        save()
    }

    @MainActor
    func updateLanguage(_ language: CaregiverLanguage) async {
        guard let caregiver = activeCaregiver else { return }
        if let id = UUID(uuidString: caregiver.id) {
            _ = try? await caregiverService.patchProfile(profileId: id, preferredLanguage: language.rawValue)
        }
        caregiver.preferredLanguage = language
        save()
    }

    // MARK: - Check-in submission (caregiver side)

    @MainActor
    func submitCheckIn(_ draft: CaregiverCheckInDraft) async -> CaregiverCheckIn? {
        guard let caregiver = activeCaregiver, let caregiverId = UUID(uuidString: caregiver.id) else { return nil }

        let result = await translationService.summarize(draft)

        let checkIn: CaregiverCheckIn
        if let dto = try? await caregiverService.createCheckIn(
            caregiverId: caregiverId,
            mealStatus: draft.mealStatus.rawValue, hydrationStatus: draft.hydrationStatus.rawValue,
            sleepStatus: draft.sleepStatus.rawValue, painLevel: draft.painLevel,
            nauseaLevel: draft.nauseaLevel, fatigueLevel: draft.fatigueLevel,
            medicationStatus: draft.medicationStatus.rawValue, medicationNote: draft.medicationNote,
            freeTextOriginal: draft.freeTextOriginal, originalLanguage: draft.originalLanguage.rawValue,
            translatedSummaryHebrew: result.hebrewSummary, attentionLevel: result.attentionLevel.rawValue,
            alertReasons: result.alertReasons
        ) {
            checkIn = upsertLocalCheckIn(from: dto)
        } else {
            checkIn = CaregiverCheckIn(
                caregiverId: caregiver.id,
                mealStatus: draft.mealStatus, hydrationStatus: draft.hydrationStatus, sleepStatus: draft.sleepStatus,
                painLevel: draft.painLevel, nauseaLevel: draft.nauseaLevel, fatigueLevel: draft.fatigueLevel,
                medicationStatus: draft.medicationStatus, medicationNote: draft.medicationNote,
                freeTextOriginal: draft.freeTextOriginal, originalLanguage: draft.originalLanguage,
                translatedSummaryHebrew: result.hebrewSummary,
                attentionLevel: result.attentionLevel, alertReasons: result.alertReasons
            )
            context.insert(checkIn)
        }

        await logSymptoms(from: draft, caregiverName: caregiver.displayName)
        save()
        return checkIn
    }

    /// Caregiver-reported symptoms flow into the shared `SymptomEntry`
    /// stream so they appear in the care-tracking tab alongside
    /// family-logged symptoms. Levels are 0–10 and stored as-is.
    @MainActor
    private func logSymptoms(from draft: CaregiverCheckInDraft, caregiverName: String) async {
        let note = "דווח על ידי המטפל/ת \(caregiverName)"
        for (level, type) in [(draft.painLevel, SymptomType.pain), (draft.nauseaLevel, .nausea), (draft.fatigueLevel, .fatigue)]
        where level > 0 {
            if let dto = try? await symptomService.report(kind: type.rawValue, severity: level, noteHe: note) {
                context.insert(SymptomEntry(id: dto.id.uuidString, type: type, severity: level, note: note, loggedAt: dto.createdAt))
            } else {
                context.insert(SymptomEntry(type: type, severity: level, note: note))
            }
        }
    }

    // MARK: - Family-side actions on a check-in

    @MainActor
    func acknowledge(_ checkIn: CaregiverCheckIn) async {
        if let id = UUID(uuidString: checkIn.id) {
            _ = try? await caregiverService.acknowledgeCheckIn(checkInId: id)
        }
        checkIn.isAcknowledged = true
        save()
    }

    /// Creates a follow-up task from a flagged check-in (e.g. missed
    /// medication). Returns false when an identical open task exists.
    @MainActor
    @discardableResult
    func createFollowUpTask(for checkIn: CaregiverCheckIn) async -> Bool {
        let title = checkIn.medicationStatus == .missed
            ? "לבדוק תרופה שלא נלקחה (דיווח מטפל/ת)"
            : "לבדוק את הדיווח האחרון מהמטפל/ת"
        let predicate = #Predicate<DailyTask> { $0.title == title && !$0.isCompleted }
        let existing = (try? context.fetch(FetchDescriptor<DailyTask>(predicate: predicate))) ?? []
        guard existing.isEmpty else { return false }

        let created = await taskService.createAndInsert(
            title: title, detail: checkIn.translatedSummaryHebrew, kind: .medical, in: context
        )
        if created == nil {
            context.insert(DailyTask(title: title, detail: checkIn.translatedSummaryHebrew, kind: .medical, origin: .aiSuggestion))
            save()
        }
        return true
    }

    /// Shares the Hebrew summary to the family feed.
    @MainActor
    func shareToFeed(_ checkIn: CaregiverCheckIn, authorMemberId: String) async {
        let body = "עדכון מהמטפל/ת: \(checkIn.translatedSummaryHebrew)"
        let status: FeedPostStatus = checkIn.needsAttention ? .concerned : .stable
        let created = await feedService.createPostAndInsert(
            body: body, status: status.rawValue, authorOverrideMemberId: authorMemberId, in: context
        )
        if created == nil {
            context.insert(FeedPost(authorMemberId: authorMemberId, body: body, status: status, audience: .familyOnly))
            save()
        }
    }

    func caregiverName(for checkIn: CaregiverCheckIn) -> String {
        if let caregiver = activeCaregiver, caregiver.id == checkIn.caregiverId {
            return caregiver.displayName
        }
        let targetId = checkIn.caregiverId
        let descriptor = FetchDescriptor<CaregiverProfile>(
            predicate: #Predicate { $0.id == targetId }
        )
        return ((try? context.fetch(descriptor)) ?? []).first?.displayName ?? "מטפל/ת"
    }

    private func save() {
        try? context.save()
        refresh()
    }
}
