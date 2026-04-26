import Foundation

enum SampleAISummaries {
    static let oncologyVisit = AISummary(
        id: "oncology-visit-20231012",
        headline: "סיכום ביקור אונקולוג — 12.10.2023",
        summaryText: "הרופא דיווח על שיפור מתון במדדי הדם לעומת הביקור הקודם. הטיפול הנוכחי (תרופה X) ממשיך להיות יעיל, ולא נדרש שינוי במינון כרגע.",
        keyPoints: [
            "המטופלת מדווחת על הטבה כללית בתחושה.",
            "בדיקות הדם עדיין מראות מעט ירידה בברזל.",
            "המלצה: להמשיך בטיפול הנוכחי. לחזור לביקורת בעוד 3 חודשים עם בדיקות דם חוזרות."
        ],
        recommendation: "להמשיך בטיפול הנוכחי ולהקפיד על מנוחה.",
        suggestedTasks: [
            .init(id: "sug-onco-1", title: "לקבוע בדיקות דם חוזרות", detail: "יש לבצע כ-10 ימים לפני תור הביקורת הבא."),
            .init(id: "sug-onco-2", title: "לתאם תור ביקורת אונקולוגית", detail: "למועד של עוד כ-3 חודשים.")
        ]
    )

    static let bloodTest = AISummary(
        id: "blood-test-20231010",
        headline: "תוצאות בדיקת דם מקיפה",
        summaryText: "רוב הערכים נמצאים בטווח התקין. קיימת ירידה קלה בברזל ובוויטמין D, המלווה בתחושת עייפות מדווחת.",
        keyPoints: [
            "המוגלובין: 11.8 — מעט מתחת לטווח התקין.",
            "ויטמין D: נמוך מהרצוי.",
            "תפקוד כבד וכליות: תקין."
        ],
        recommendation: "לשקול תוסף ברזל וויטמין D בהמלצת הרופא המטפל.",
        suggestedTasks: [
            .init(id: "sug-blood-1", title: "לקנות תוספי ברזל וויטמין D", detail: "לאחר אישור מהרופא המטפל.")
        ]
    )

    static let prescriptionImage = AISummary(
        id: "prescription-20231005",
        headline: "צילום מרשם תרופות — אוקטובר",
        summaryText: "המרשם כולל תרופה למניעת בחילות ותרופה משככת כאבים. יש להקפיד על מועדי הנטילה.",
        keyPoints: [
            "זופרן — לפני הטיפול ולפי הצורך.",
            "פרצטמול — לפי הצורך, לא יותר מ-4 פעמים ביממה."
        ],
        recommendation: nil,
        suggestedTasks: [
            .init(id: "sug-rx-1", title: "לחדש מרשם בסופר-פארם", detail: "המרשם הנוכחי תקף עוד שבועיים.")
        ]
    )

    static let dashboardFeatured = oncologyVisit

    static func summary(for key: String) -> AISummary? {
        switch key {
        case oncologyVisit.id: return oncologyVisit
        case bloodTest.id: return bloodTest
        case prescriptionImage.id: return prescriptionImage
        default: return nil
        }
    }
}
