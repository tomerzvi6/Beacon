import SwiftUI

/// In-app legal texts. POC drafts — clearly marked as such; replace with
/// lawyer-reviewed versions before public launch.
enum LegalDocument: String, Identifiable {
    case privacyPolicy
    case termsOfUse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy: return "מדיניות פרטיות"
        case .termsOfUse: return "תנאי שימוש"
        }
    }

    var body: String {
        switch self {
        case .privacyPolicy:
            return """
            עודכן: יולי 2026 · גרסת פיילוט

            ביקון (Beacon) היא אפליקציה לניהול טיפול רפואי משפחתי. הפרטיות של המידע הרפואי שלכם היא הבסיס לקיום שלנו, ולכן בשפה פשוטה:

            **איזה מידע נאסף**
            • פרטי חשבון: שם וכתובת מייל (דרך Apple או מייל).
            • מסמכים רפואיים שאתם בוחרים להעלות, והסיכומים שנוצרים מהם.
            • מידע שאתם מזינים ידנית: תרופות, תורים, סימפטומים, פוסטים משפחתיים ודיווחי מטפל/ת.

            **איפה המידע נשמר**
            • תרופות, משימות, יומן, פיד ודיווחי מטפל/ת — נשמרים מקומית על המכשיר שלכם בלבד.
            • מסמכים שהועלו — נשמרים בשרת מאובטח לצורך יצירת הסיכום.
            • פרטי חשבון — במערכת ההזדהות המאובטחת שלנו.

            **מה נעשה עם המידע**
            • יצירת סיכומים בעברית למסמכים שהעליתם, בעזרת מודל בינה מלאכותית (Anthropic Claude). המסמך מעובד לצורך הסיכום בלבד.
            • לעולם לא נמכור את המידע שלכם, לא נשתמש בו לפרסום, ולא נעביר אותו לגורם שלישי ללא הסכמתכם המפורשת — למעט אם נידרש על פי דין.

            **שליטה שלכם**
            • אפשר למחוק כל מסמך, תרופה או רשומה בכל רגע.
            • למחיקת חשבון מלאה — כתבו לנו ונמחק את כל הנתונים תוך 30 יום.

            **אבטחה**
            התקשורת מוצפנת (HTTPS), הגישה למסמכים מוגבלת לחשבון שלכם, וההרשאות בתוך המשפחה נקבעות על ידכם.

            זוהי גרסת פיילוט של המסמך. לשאלות: tomerzvi6@gmail.com
            """
        case .termsOfUse:
            return """
            עודכן: יולי 2026 · גרסת פיילוט

            **1. מה ביקון**
            ביקון היא כלי עזר לארגון הטיפול: מסמכים, תרופות, תורים ותיאום משפחתי.

            **2. ביקון אינה ייעוץ רפואי**
            הסיכומים באפליקציה נוצרים על ידי בינה מלאכותית ועלולים להכיל אי-דיוקים. הם אינם תחליף לייעוץ, אבחון או טיפול רפואי מקצועי. בכל שאלה רפואית יש לפנות לצוות המטפל. במצב חירום — חייגו 101.

            **3. אחריות על התוכן**
            אתם אחראים למידע שאתם מעלים ומשתפים, ולבחירת בני המשפחה שמקבלים גישה אליו. הרשאות הצפייה בתוך המשפחה נקבעות על ידכם.

            **4. גרסת פיילוט**
            האפליקציה נמצאת בשלב פיילוט. ייתכנו תקלות, שינויים ואובדן נתונים. מומלץ לשמור עותק של מסמכים חשובים גם מחוץ לאפליקציה.

            **5. שימוש הוגן**
            אין להשתמש באפליקציה למטרה שאינה ניהול טיפול משפחתי, ואין להעלות תוכן של אדם ללא הסכמתו.

            **6. סיום שימוש**
            אפשר להפסיק להשתמש ולבקש מחיקת חשבון בכל עת.

            זוהי גרסת פיילוט של המסמך. לשאלות: tomerzvi6@gmail.com
            """
        }
    }
}

struct LegalTextSheet: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(.init(document.body))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(Theme.Spacing.m)
            }
            .beaconScreenBackground()
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגור") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

#if DEBUG
#Preview("LegalTextSheet") {
    LegalTextSheet(document: .privacyPolicy)
}
#endif
