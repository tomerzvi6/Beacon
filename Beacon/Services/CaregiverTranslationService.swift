import Foundation

/// Input for summary generation — a value type so the service stays
/// decoupled from SwiftData models and is trivially testable.
struct CaregiverCheckInDraft {
    var mealStatus: CaregiverMealStatus
    var hydrationStatus: CaregiverHydrationStatus
    var sleepStatus: CaregiverSleepStatus
    var painLevel: Int
    var nauseaLevel: Int
    var fatigueLevel: Int
    var medicationStatus: CaregiverMedicationStatus
    var medicationNote: String?
    var freeTextOriginal: String?
    var originalLanguage: CaregiverLanguage
}

/// Result of "translating" a check-in for the family.
struct CaregiverSummaryResult {
    var hebrewSummary: String
    var attentionLevel: CaregiverAttentionLevel
    /// Hebrew, human-readable alert reasons.
    var alertReasons: [String]
}

/// Abstraction over the translation/summarization step. The MVP ships a
/// local rule-based implementation; a future implementation can call the
/// Beacon backend (Claude) with the same signature.
protocol CaregiverTranslationServiceProtocol {
    func summarize(_ draft: CaregiverCheckInDraft) async -> CaregiverSummaryResult
}

/// Rule-based mock: builds a Hebrew summary from the structured fields,
/// appends the original free text untranslated, and flags risk keywords.
struct LocalMockCaregiverTranslationService: CaregiverTranslationServiceProtocol {

    func summarize(_ draft: CaregiverCheckInDraft) async -> CaregiverSummaryResult {
        let reasons = alertReasons(for: draft)
        let level = attentionLevel(for: draft, reasons: reasons)
        return CaregiverSummaryResult(
            hebrewSummary: hebrewSummary(for: draft),
            attentionLevel: level,
            alertReasons: reasons
        )
    }

    // MARK: - Summary

    private func hebrewSummary(for draft: CaregiverCheckInDraft) -> String {
        var parts: [String] = [
            draft.mealStatus.hebrewLabel,
            draft.hydrationStatus.hebrewLabel,
            draft.sleepStatus.hebrewLabel
        ]

        if draft.painLevel > 0 { parts.append("כאב \(draft.painLevel)/10") }
        if draft.nauseaLevel > 0 { parts.append("בחילה \(draft.nauseaLevel)/10") }
        if draft.fatigueLevel > 0 { parts.append("חולשה \(draft.fatigueLevel)/10") }

        switch draft.medicationStatus {
        case .taken:   parts.append("התרופות נלקחו")
        case .missed:  parts.append("תרופה לא נלקחה")
        case .notSure: parts.append("לא בטוח/ה אם התרופות נלקחו")
        }

        var summary = parts.joined(separator: ", ") + "."

        if let note = draft.freeTextOriginal?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            summary += " הודעה מהמטפל/ת (\(draft.originalLanguage.hebrewName)): \u{201D}\(note)\u{201D}"
        }
        return summary
    }

    // MARK: - Alerts

    private func alertReasons(for draft: CaregiverCheckInDraft) -> [String] {
        var reasons: [String] = []

        if draft.painLevel >= 7 { reasons.append("כאב גבוה (\(draft.painLevel)/10)") }
        if draft.mealStatus == .didNotEat { reasons.append("לא אכל/ה") }
        if draft.hydrationStatus == .didNotDrink { reasons.append("לא שתה/תה") }
        if draft.medicationStatus == .missed { reasons.append("תרופה לא נלקחה") }
        if draft.medicationStatus == .notSure { reasons.append("אי-ודאות לגבי נטילת תרופות") }

        if let note = draft.freeTextOriginal?.lowercased() {
            for (keywords, reason) in Self.keywordAlerts
            where keywords.contains(where: { note.contains($0) }) {
                reasons.append(reason)
            }
        }
        return reasons
    }

    private func attentionLevel(
        for draft: CaregiverCheckInDraft,
        reasons: [String]
    ) -> CaregiverAttentionLevel {
        let hasUrgentKeyword = (draft.freeTextOriginal?.lowercased()).map { note in
            Self.urgentKeywords.contains(where: { note.contains($0) })
        } ?? false

        if draft.painLevel >= 9 || hasUrgentKeyword { return .urgent }
        if !reasons.isEmpty { return .attention }
        return .ok
    }

    /// Risk keywords per concern, across supported caregiver languages.
    /// Lowercased; matched with `contains` against the lowercased note.
    private static let keywordAlerts: [(keywords: [String], reason: String)] = [
        (
            ["fall", "fell", "nahulog", "natumba", "गिर", "വീണു", "விழுந்த"],
            "אזכור של נפילה בהודעה"
        ),
        (
            ["dizzy", "dizziness", "nahihilo", "hilo", "चक्कर", "തലകറക്കം", "தலைச்சுற்றல்"],
            "אזכור של סחרחורת בהודעה"
        ),
        (
            ["fever", "lagnat", "बुख़ार", "बुखार", "പനി", "காய்ச்சல்"],
            "אזכור של חום בהודעה"
        ),
        (
            ["vomit", "threw up", "suka", "nagsuka", "उल्टी", "ഛർദ്ദി", "வாந்தி"],
            "אזכור של הקאה בהודעה"
        )
    ]

    /// Keywords that escalate straight to "urgent".
    private static let urgentKeywords: [String] = [
        "fall", "fell", "nahulog", "natumba", "गिर", "വീണു", "விழுந்த",
        "fever", "lagnat", "बुख़ार", "बुखार", "പനി", "காய்ச்சல்",
        "emergency", "ambulance", "hospital now"
    ]
}
