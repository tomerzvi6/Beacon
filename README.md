# Beacon — MVP iOS App

Beacon הוא אפליקציית "חדר פיקוד" לניהול טיפול רפואי וליווי משפחתי עבור משפחות של חולי סרטן. אפליקציית SwiftUI/SwiftData לפי ארכיטקטורת MVVM, עם ממשק בעברית ו־RTL מלא.

## Build instructions

הפרויקט נוצר על סביבת פיתוח חוצת פלטפורמות ומשתמש ב־[XcodeGen](https://github.com/yonaskolb/XcodeGen) כדי לייצר את קובץ ה־`Beacon.xcodeproj` מתוך `project.yml`. ה־Swift קבצים כבר מוכנים. השלבים הבאים נעשים על מכשיר Mac עם Xcode 15 ומעלה:

### מסלול A — XcodeGen (מומלץ)

```bash
# 1. התקנה (פעם אחת):
brew install xcodegen

# 2. בתוך תיקיית הריפו:
cd /path/to/Beacon2
xcodegen generate

# 3. פתיחה:
open Beacon.xcodeproj
```

כעת אפשר לבנות ולהריץ (`⌘R`) מול כל סימולטור iOS 17+.

### מסלול B — Xcode חדש ידני

1. פתח Xcode → `File > New > Project > iOS App` (לא שומרים, רק בשביל תבנית).
2. מחק את הקבצים שנוצרו אוטומטית תחת הטרגט.
3. גרור את תיקיית `Beacon/` שלמה לתוך הפרויקט, ודא שמסומן "Create groups" ושהטרגט `Beacon` מסומן.
4. גרור את `Beacon/Assets.xcassets` כ־resource.
5. ב־project settings:
   - Deployment Target: iOS 17.0
   - Development Language: Hebrew
   - Localizations: הוסף Hebrew.
6. ודא שה־Info.plist שמפנים אליו הוא `Beacon/Info.plist`.

---

## Project structure

```
Beacon2/
├── project.yml                 # XcodeGen spec
├── Beacon.xcodeproj/           # (מיוצר ע״י xcodegen generate)
└── Beacon/
    ├── BeaconApp.swift         # @main — רישום ModelContainer, RTL, seed
    ├── Info.plist
    ├── Assets.xcassets/
    │   └── Colors/             # 10 color tokens
    ├── App/
    │   ├── RootTabView.swift   # 4-tab TabView
    │   └── Theme.swift         # Typography / Palette / Spacing / Radii
    ├── Models/                 # SwiftData @Model + פלט תיכוני
    ├── ViewModels/             # @Observable ViewModels לכל טאב
    ├── Views/
    │   ├── Components/         # BeaconCard, Button, Badge, Avatar, …
    │   ├── Dashboard/          # לוח בקרה
    │   ├── MedicalVault/       # תיק רפואי
    │   ├── ProactiveCare/      # מעקב טיפול
    │   └── CircleOfTrust/      # מעגל תמיכה
    └── Services/
        ├── MockDataSeeder.swift   # זריעת נתוני דמו בעברית ב־SwiftData
        └── SampleAISummaries.swift # סיכומי AI מוכנים מראש
```

---

## Architecture

- **SwiftUI + MVVM + SwiftData (iOS 17+).**
- **`@Observable`** ViewModels. כל טאב מחזיק ViewModel משלו עם state וצירי intent (`claimTask`, `markDoseTaken`, `togglePostReaction`…). ה־Views לא מכילים לוגיקה עסקית.
- **`ModelContainer`** נוצר ב־`BeaconApp` ומוזרק לכל ה־Views דרך `.modelContainer(...)`. ה־ViewModels מקבלים `ModelContext` בקונסטרקטור.
- **Seeding:** `MockDataSeeder.seedIfNeeded(in:)` רץ פעם אחת (gated ע״י `UserDefaults` flag). קבצי Preview משתמשים ב־`MockDataSeeder.makeInMemoryPreviewContainer()`.
- **Theme tokens בלבד.** אין hex codes ומרווחים קבועים פזורים ב־Views — הכל דרך `Theme.Palette`, `Theme.Typography`, `Theme.Spacing`, `Theme.CornerRadius`.
- **RTL** נאכף במקום אחד: `.environment(\.locale, Locale(identifier: "he_IL"))` + `.environment(\.layoutDirection, .rightToLeft)` ב־`BeaconApp` ובכל `#Preview`.

---

## Features delivered (MVP)

### 1. לוח בקרה (`DashboardView`)
- ברכת פתיחה מותאמת לשעה (`בוקר טוב, רונית`).
- לוח זמנים משפחתי עם תגיות **רפואי/שגרה** ומלווה.
- משימות להיום עם כפתור **"קח על עצמך משימה"** שמשייך את המשימה למטפל/ת.

### 2. תיק רפואי (`MedicalVaultView`)
- כרטיס סנכרון חד־כיווני: **"תוצאות מעבדה חדשות התקבלו"** (בי״ח שיבא) — ניתן לסגירה.
- כרטיס Featured גדול: **סיכום AI חכם** עם כפתור **"הוסף משימות מוצעות ליומן באופן אוטומטי"** — המשימות עוברות באמת למאגר המשימות של הדאשבורד.
- שורת חיפוש + תגיות סינון (הכל / סיכומי ביקור / בדיקות דם).
- כרטיסי מסמכים עם החלפה בין **"סיכום AI מופשט"** ל**"מסמך מקורי"**.
- מסך פירוט (`DocumentDetailView`) עם Picker בין AI למקור + כפתור הוספת המשימות.

### 3. מעקב טיפול (`ProactiveCareView`)
- **התראת מינון חסר** בראש המסך (אוקסיקונטין 08:00) עם "סמן כנלקח עכשיו" / "הוסף הערה".
- רשימת תרופות להיום + תג **"X נותרו"**.
- כרטיסי מינון בזמנים 12:00 / 18:00 עם מצב דינמי (`upcoming` / `taken` / `scheduledLater`).
- **דיווח מהיר** עם שלושה כפתורים אייקוניים — בחילה / עייפות / כאב — + "הוסף מדד חדש".
- מדדים שנרשמו שורדים ב־SwiftData בין הפעלות.

### 4. מעגל תמיכה (`CircleOfTrustView`)
- כרטיס **פרסום עדכון** עם בורר סטטוס (מצב יציב / זקוקים למנוחה / משתפרים / מודאגים).
- חיווי **"גלוי למשפחה בלבד"**.
- פוסטים עם תגוביות, מונה לבבות וחיבוקים.
- **הגבלת אינטראקציה**: משתמש שאינו `primaryCaregiver` רואה רק כפתורי רגש (❤ / 🤗) ולא יכול להגיב בטקסט. לצורך MVP הדמו מוגדר עם `currentUser = primaryCaregiver`, אבל ה־VM והעיצוב כבר תומכים בהחלפת תפקיד.

---

## Design notes

### Colors (Assets)

| Token | Hex | Usage |
|---|---|---|
| `BeaconDeepTeal` | `#16475A` | כפתורי CTA, כותרות |
| `BeaconSoftBlue` | `#C5DCE0` | תגיות רפואיות, משטחים משניים |
| `BeaconSage` | `#DCEEDD` | תגיות שגרה, הצלחות, כפתור "קח על עצמך" |
| `BeaconSageDark` | `#5C8A6E` | טקסט על Sage |
| `BeaconCoralBg` | `#FBE4E4` | רקע התראה אדומה |
| `BeaconCoralAccent` | `#B22D3F` | accent של התראה אדומה, כפתור "סמן כנלקח" |
| `BeaconBackground` | `#EFF4F4` | רקע מסך |
| `BeaconCardBackground` | `#FFFFFF` | רקע כרטיס |
| `BeaconTextPrimary` | `#1F3845` | טקסט ראשי |
| `BeaconTextSecondary` | `#6F7E84` | טקסט משני |

### Typography

מבוסס System font (SF) עם Rounded design לכותרות גדולות — מעניק תחושה רכה, ידידותית, ומטפל יפה בעברית. גדלים מעט גדולים מהברירת־מחדל (17–30pt) לטובת עומס קוגניטיבי נמוך.

---

## Verification checklist

1. פתח את הפרויקט ב־Xcode ובנה (`⌘B`) מול `iPhone 15 (iOS 17+)`.
2. הרץ (`⌘R`). האפליקציה צריכה להיפתח ישירות בטאב **"לוח בקרה"** בעברית + RTL.
3. החלף בין 4 הטאבים וודא שאין קריסות.
4. **לוח בקרה**: לחץ "קח על עצמך משימה" — המשימה משתנה ומציגה את רונית כמטפלת.
5. **מעקב טיפול**: לחץ "קח עכשיו" במינון 12:00 — הכרטיס משתנה למצב "נלקח".
6. **מעקב טיפול**: לחץ על "בחילה" / "עייפות" / "כאב" — toast "נרשם", והפריט שורד restart.
7. **תיק רפואי**: פתח כרטיס מסמך ← ראה Picker AI vs Original. לחץ "הוסף משימות מוצעות ליומן" — חזור לדאשבורד וודא שהמשימות נוספו.
8. **מעגל תמיכה**: לחץ ❤ על פוסט — המונה עולה ושורד restart.
9. פתח Xcode Canvas (`⌥⌘↩︎`) לכל אחד מה־`#Preview` — ודא שהעברית מוצגת RTL כהלכה.

---

## Known TODOs / future hooks

- **תבנית אייקון אפליקציה** — `AppIcon.appiconset` ריק, יש להוסיף PNGs.
- **AI אמיתי** — `SampleAISummaries` משמש כ־façade. החלפה ל־Claude / OpenAI דורשת הזרקת `AIServiceProtocol` לתוך `MedicalVaultViewModel`.
- **סנכרון בית חולים אמיתי** — `HospitalSyncAlert` כעת זרוע ידנית. במהלך backend עתידי, ניתן לרשום webhook → `ModelContext.insert(...)`.
- **הרשאות / רב־משתמש** — `AppEnvironment.currentUser` הוא נקודת ההחלפה היחידה להחלפת תפקיד בזמן ריצה (e.g. מעגל חיצוני שרואה רק אימוג׳י).
