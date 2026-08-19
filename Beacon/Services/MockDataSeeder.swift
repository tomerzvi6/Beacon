import Foundation
import SwiftData

enum MockDataSeeder {
    private static let seedFlagKey = "beacon.mockData.v1.seeded"
    private static let demoModeKey = "beacon.demoData.enabled.v1"

    /// Demo data is opt-in. Fresh installs for real families stay clean;
    /// the toggle lives in the patient profile sheet (full-access users).
    static var isDemoDataEnabled: Bool {
        UserDefaults.standard.bool(forKey: demoModeKey)
    }

    /// Loads the demo data set (idempotent — clears previous demo state first).
    @MainActor
    static func enableDemoData(in context: ModelContext) {
        UserDefaults.standard.set(true, forKey: demoModeKey)
        seedIfNeeded(in: context, force: true)
    }

    /// Wipes all local care data and turns demo mode off. Used both to
    /// exit demo mode and to hand a clean device to a pilot family.
    @MainActor
    static func disableDemoData(in context: ModelContext) {
        UserDefaults.standard.set(false, forKey: demoModeKey)
        UserDefaults.standard.set(false, forKey: seedFlagKey)
        clearAll(context: context)
        try? context.save()
    }

    @MainActor
    static func seedIfNeeded(in context: ModelContext, force: Bool = false) {
        let defaults = UserDefaults.standard
        if !force && defaults.bool(forKey: seedFlagKey) { return }

        if force { clearAll(context: context) }

        seed(into: context)

        do {
            try context.save()
            defaults.set(true, forKey: seedFlagKey)
        } catch {
            assertionFailure("Beacon seed save failed: \(error)")
        }
    }

    @MainActor
    static func seed(into context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // MARK: Schedule events (Dashboard)
        context.insert(ScheduleEvent(
            title: "ביקורת אונקולוגית",
            startsAt: calendar.date(byAdding: .hour, value: 9, to: today)!,
            kind: .medical,
            locationName: "בי״ח איכילוב, מחלקה א׳",
            companionMemberId: FamilyMember.daniel.id,
            subtitle: "09:00 בוקר"
        ))
        context.insert(ScheduleEvent(
            title: "נטילת תרופות - סבב 2",
            startsAt: calendar.date(byAdding: .minute, value: 13 * 60 + 30, to: today)!,
            kind: .routine,
            subtitle: "2 כדורים לאחר ארוחה"
        ))

        // MARK: Today tasks (Dashboard)
        context.insert(DailyTask(
            title: "קניית תרופות מבית המרקחת",
            detail: "מרשם חדש מחכה בסופר-פארם",
            kind: .logistics,
            origin: .manual,
            dueAt: calendar.date(byAdding: .hour, value: 18, to: today)
        ))
        context.insert(DailyTask(
            title: "תיאום שיחה עם האונקולוג",
            detail: "לקבוע תור לשבוע הבא",
            kind: .medical,
            origin: .manual
        ))

        // MARK: Medications (Proactive Care)
        let oxycontin = Medication(
            name: "אוקסיקונטין",
            dosageDescription: "10 מ״ג",
            usageInstructions: "פעמיים ביום, כל 12 שעות",
            form: .pill,
            stockCount: 2
        )
        let paracetamol = Medication(
            name: "פרצטמול",
            dosageDescription: "1000 מ״ג",
            usageInstructions: "לפי הצורך",
            form: .pill,
            stockCount: 14
        )
        let zofran = Medication(
            name: "זופרן",
            dosageDescription: "8 מ״ג",
            usageInstructions: "למניעת בחילות",
            form: .injection,
            stockCount: 3
        )
        context.insert(oxycontin)
        context.insert(paracetamol)
        context.insert(zofran)

        // MARK: Medication doses for today
        context.insert(MedicationDose(
            medicationName: oxycontin.name,
            medicationDosage: oxycontin.dosageDescription,
            usageInstructions: oxycontin.usageInstructions,
            form: .pill,
            scheduledAt: calendar.date(byAdding: .hour, value: 8, to: today)!,
            status: .missed
        ))
        context.insert(MedicationDose(
            medicationName: paracetamol.name,
            medicationDosage: "2 כדורים (1000 מ״ג)",
            usageInstructions: "אחרי אוכל",
            form: .pill,
            scheduledAt: calendar.date(byAdding: .hour, value: 12, to: today)!,
            status: .upcoming
        ))
        context.insert(MedicationDose(
            medicationName: zofran.name,
            medicationDosage: "זריקה 1 (8 מ״ג)",
            usageInstructions: "למניעת בחילות",
            form: .injection,
            scheduledAt: calendar.date(byAdding: .hour, value: 18, to: today)!,
            status: .scheduledLater
        ))

        // MARK: Hospital sync alert
        context.insert(HospitalSyncAlert(
            title: "תוצאות מעבדה חדשות התקבלו",
            body: "לחץ לצפייה בעדכון האחרון מבי״ח שיבא",
            sourceHospital: "בי״ח שיבא"
        ))

        // Phase 9.3: medical documents are no longer seeded locally —
        // they come from the Beacon backend (GET /v1/documents/).
        // The Medical Vault renders an empty state on a fresh install
        // until the user uploads or has a household with existing docs.

        // MARK: Home caregiver (demo) — active profile + this morning's
        // check-in + two standing instructions, so the caregiver loop is
        // demonstrable end-to-end out of the box.
        let maria = CaregiverProfile(
            displayName: "Maria",
            relationTitle: "מטפלת סיעודית",
            preferredLanguage: .tagalog
        )
        context.insert(maria)

        context.insert(CaregiverCheckIn(
            caregiverId: maria.id,
            createdAt: calendar.date(byAdding: .minute, value: 8 * 60 + 30, to: today)!,
            mealStatus: .ateLittle,
            hydrationStatus: .drankEnough,
            sleepStatus: .sleptWell,
            painLevel: 3,
            nauseaLevel: 2,
            fatigueLevel: 4,
            medicationStatus: .taken,
            freeTextOriginal: "Medyo pagod siya pagkatapos ng almusal, pero maganda ang mood niya.",
            originalLanguage: .tagalog,
            translatedSummaryHebrew: "אכל/ה מעט, שתה/תה מספיק, ישן/ה טוב, כאב 3/10, בחילה 2/10, חולשה 4/10, התרופות נלקחו. הודעה מהמטפלת (טגלוג): ”קצת עייף אחרי ארוחת הבוקר, אבל במצב רוח טוב.”",
            attentionLevel: .ok
        ))

        context.insert(CaregiverInstruction(
            kind: .giveMedication,
            detail: "Acamol בשעה 14:00",
            createdByName: FamilyMember.primaryCaregiver.displayName
        ))
        context.insert(CaregiverInstruction(
            kind: .callFamilyIf,
            detail: "חום מעל 38 או כאב חזק",
            createdByName: FamilyMember.primaryCaregiver.displayName
        ))

        // MARK: Feed posts
        let post1 = FeedPost(
            authorMemberId: FamilyMember.primaryCaregiver.id,
            body: "בוקר טוב לכולם. הלילה עבר בשלום, אבא ישן טוב והתעורר במצב רוח מצוין. אכלנו ארוחת בוקר קלה ועכשיו אנחנו נחים קצת לפני הפיזיותרפיה. תודה לכולם על ההודעות החמות!",
            status: .stable,
            postedAt: calendar.date(byAdding: .hour, value: -2, to: Date())!,
            heartCount: 12,
            hugCount: 4,
            audience: .familyOnly,
            comments: [
                FeedComment(
                    authorMemberId: FamilyMember.uncleMoshe.id,
                    body: "חדשות נהדרות! תמסרי לו דרישת שלום חמה ממני. את עושה עבודה מדהימה מיכל.",
                    postedAt: calendar.date(byAdding: .hour, value: -1, to: Date())!
                ),
                FeedComment(
                    authorMemberId: FamilyMember.auntRachel.id,
                    body: "איזה יופי. נבוא לבקר מחר אחה״צ להביא עוגה.",
                    postedAt: calendar.date(byAdding: .minute, value: -45, to: Date())!
                )
            ]
        )
        context.insert(post1)

        let post2 = FeedPost(
            authorMemberId: FamilyMember.primaryCaregiver.id,
            body: "היום היה יום קצת עמוס בבדיקות ואנחנו עייפים. נשמח לשקט היום בערב. תודה על ההבנה.",
            status: .needsRest,
            postedAt: calendar.date(byAdding: .day, value: -1, to: Date())!,
            heartCount: 8,
            hugCount: 2,
            audience: .familyOnly
        )
        context.insert(post2)
    }

    @MainActor
    static func clearAll(context: ModelContext) {
        try? context.delete(model: DailyTask.self)
        try? context.delete(model: ScheduleEvent.self)
        try? context.delete(model: MedicationDose.self)
        try? context.delete(model: Medication.self)
        try? context.delete(model: SymptomEntry.self)
        try? context.delete(model: HospitalSyncAlert.self)
        try? context.delete(model: FeedComment.self)
        try? context.delete(model: FeedPost.self)
        try? context.delete(model: CaregiverProfile.self)
        try? context.delete(model: CaregiverCheckIn.self)
        try? context.delete(model: CaregiverInstruction.self)
    }

    @MainActor
    static func makeInMemoryPreviewContainer() -> ModelContainer {
        let schema = Schema([
            ScheduleEvent.self,
            DailyTask.self,
            Medication.self,
            MedicationDose.self,
            SymptomEntry.self,
            HospitalSyncAlert.self,
            FeedPost.self,
            FeedComment.self,
            CaregiverProfile.self,
            CaregiverCheckIn.self,
            CaregiverInstruction.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        seed(into: container.mainContext)
        return container
    }
}
