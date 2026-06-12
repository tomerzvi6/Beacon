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

    private(set) var activeCaregiver: CaregiverProfile?
    private(set) var latestCheckIn: CaregiverCheckIn?
    private(set) var recentCheckIns: [CaregiverCheckIn] = []

    init(
        context: ModelContext,
        translationService: CaregiverTranslationServiceProtocol = LocalMockCaregiverTranslationService()
    ) {
        self.context = context
        self.translationService = translationService
        refresh()
    }

    var isCaregiverLayerActive: Bool { activeCaregiver != nil }

    /// True when the dashboard should show the caregiver update card.
    var hasDashboardUpdate: Bool { activeCaregiver != nil && latestCheckIn != nil }

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
    }

    // MARK: - Family-side setup

    func activateCaregiver(
        name: String,
        relationTitle: String,
        language: CaregiverLanguage
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let existing = activeCaregiver {
            existing.displayName = trimmedName
            existing.relationTitle = relationTitle
            existing.preferredLanguage = language
        } else {
            context.insert(CaregiverProfile(
                displayName: trimmedName,
                relationTitle: relationTitle.isEmpty ? "מטפל/ת סיעודי/ת" : relationTitle,
                preferredLanguage: language
            ))
        }
        save()
    }

    func deactivateCaregiver() {
        guard let caregiver = activeCaregiver else { return }
        caregiver.isActive = false
        save()
    }

    func updateLanguage(_ language: CaregiverLanguage) {
        guard let caregiver = activeCaregiver else { return }
        caregiver.preferredLanguage = language
        save()
    }

    // MARK: - Check-in submission (caregiver side)

    @MainActor
    func submitCheckIn(_ draft: CaregiverCheckInDraft) async -> CaregiverCheckIn? {
        guard let caregiver = activeCaregiver else { return nil }

        let result = await translationService.summarize(draft)

        let checkIn = CaregiverCheckIn(
            caregiverId: caregiver.id,
            mealStatus: draft.mealStatus,
            hydrationStatus: draft.hydrationStatus,
            sleepStatus: draft.sleepStatus,
            painLevel: draft.painLevel,
            nauseaLevel: draft.nauseaLevel,
            fatigueLevel: draft.fatigueLevel,
            medicationStatus: draft.medicationStatus,
            medicationNote: draft.medicationNote,
            freeTextOriginal: draft.freeTextOriginal,
            originalLanguage: draft.originalLanguage,
            translatedSummaryHebrew: result.hebrewSummary,
            attentionLevel: result.attentionLevel,
            alertReasons: result.alertReasons
        )
        context.insert(checkIn)

        logSymptoms(from: draft, caregiverName: caregiver.displayName)
        save()
        return checkIn
    }

    /// Caregiver-reported symptoms flow into the shared `SymptomEntry`
    /// stream so they appear in the care-tracking tab alongside
    /// family-logged symptoms. Levels are 0–10 and stored as-is.
    private func logSymptoms(from draft: CaregiverCheckInDraft, caregiverName: String) {
        let note = "דווח על ידי המטפל/ת \(caregiverName)"
        if draft.painLevel > 0 {
            context.insert(SymptomEntry(type: .pain, severity: draft.painLevel, note: note))
        }
        if draft.nauseaLevel > 0 {
            context.insert(SymptomEntry(type: .nausea, severity: draft.nauseaLevel, note: note))
        }
        if draft.fatigueLevel > 0 {
            context.insert(SymptomEntry(type: .fatigue, severity: draft.fatigueLevel, note: note))
        }
    }

    // MARK: - Family-side actions on a check-in

    func acknowledge(_ checkIn: CaregiverCheckIn) {
        checkIn.isAcknowledged = true
        save()
    }

    /// Creates a follow-up task from a flagged check-in (e.g. missed
    /// medication). Returns false when an identical open task exists.
    @discardableResult
    func createFollowUpTask(for checkIn: CaregiverCheckIn) -> Bool {
        let title = checkIn.medicationStatus == .missed
            ? "לבדוק תרופה שלא נלקחה (דיווח מטפל/ת)"
            : "לבדוק את הדיווח האחרון מהמטפל/ת"
        let predicate = #Predicate<DailyTask> { $0.title == title && !$0.isCompleted }
        let existing = (try? context.fetch(FetchDescriptor<DailyTask>(predicate: predicate))) ?? []
        guard existing.isEmpty else { return false }

        context.insert(DailyTask(
            title: title,
            detail: checkIn.translatedSummaryHebrew,
            kind: .medical,
            origin: .aiSuggestion
        ))
        save()
        return true
    }

    /// Shares the Hebrew summary to the family feed.
    func shareToFeed(_ checkIn: CaregiverCheckIn, authorMemberId: String) {
        context.insert(FeedPost(
            authorMemberId: authorMemberId,
            body: "עדכון מהמטפל/ת: \(checkIn.translatedSummaryHebrew)",
            status: checkIn.needsAttention ? .concerned : .stable,
            audience: .familyOnly
        ))
        save()
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
