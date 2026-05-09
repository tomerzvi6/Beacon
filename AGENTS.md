# Beacon — הנחיות לסוכנים

## מהו הפרויקט

אפליקציית iOS (SwiftUI, iOS 17+) לניהול טיפול רפואי עבור משפחות של חולי סרטן.
שפה: עברית. RTL מלא. ארכיטקטורה: MVVM + SwiftData.

## מצב נוכחי

- MVP מלא עם **נתוני Mock בלבד** — אין backend אמיתי
- Supabase מחובר כ-dependency אבל לא בשימוש עדיין
- AI summaries הם static strings מתוך `SampleAISummaries.swift` — לא Codex API אמיתי

## ארכיטקטורה

```
Beacon/
├── App/              # RootTabView (4 טאבים), Theme tokens
├── Models/           # SwiftData @Model — DailyTask, Medication, MedicalDocument, SymptomEntry, FeedPost
├── ViewModels/       # @Observable per-tab — DashboardVM, MedicalVaultVM, ProactiveCareVM, CircleOfTrustVM
├── Views/
│   ├── Dashboard/
│   ├── MedicalVault/
│   ├── ProactiveCare/
│   └── CircleOfTrust/
└── Services/
    ├── MockDataSeeder.swift      # זריעת נתוני דמו — מופעל פעם אחת בלבד (UserDefaults flag)
    └── SampleAISummaries.swift   # Façade זמני לסיכומי AI
```

## מוסכמות חובה

- **אין לשנות נתוני seed** ב-`MockDataSeeder.swift` אלא אם התבקש במפורש
- **אין לכתוב hex codes** ישירות ב-Views — תמיד דרך `Theme.Palette`
- **אין לכתוב spacing numbers** ישירות — תמיד דרך `Theme.Spacing`
- כל ViewModel: `@Observable`, מקבל `ModelContext` בקונסטרקטור
- Views לא מכילים לוגיקה עסקית — הכל ב-ViewModel
- RTL נאכף ב-`BeaconApp` בלבד, לא בכל View

## נקודות הרחבה עתידיות (אל תממש לבד)

| מה | איפה | הערה |
|---|---|---|
| Codex / AI אמיתי | `AIServiceProtocol` (לא קיים עדיין) | להזריק ל-`MedicalVaultViewModel` |
| Hospital sync | `HospitalSyncAlert` | כרגע זרוע ידנית |
| Multi-user / roles | `AppEnvironment.currentUser` | נקודת החלפה יחידה |
| Backend Supabase | `supabase_schema.sql` ב-docs/ | Schema מוכן, לא מחובר |

## מה מותר לסוכן לעשות ללא אישור

- קריאת כל קובץ בפרויקט
- הוספת View חדש / Component
- הוספת פונקציה ל-ViewModel קיים
- עדכון Theme tokens
- הרצת `swift build`

## מה דורש אישור מפורש מהמשתמש

- שינוי ב-`MockDataSeeder.swift`
- שינוי ב-`project.yml`
- הוספת dependency חדש
- כל שינוי שנוגע ל-Supabase / backend
- git push
