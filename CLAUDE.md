# Beacon — הנחיות לסוכנים

## Product Context — Read This First

**The problem:** Families of cancer patients manage a critical medical-logistical load under heavy emotional stress — scattered documents, coordination between family members, medication tracking, and appointments.

**Users:** Two types, in the same app:
- **Primary caregiver** — a family member managing the patient's care
- **The patient themselves** — an active participant, not just observed

Tech level: basic. If the user knows WhatsApp and Facebook, they can use Beacon.

**The most critical flow (never break this):**
Receiving/uploading a medical document → parsing → Hebrew summary accessible to the family.
This is the heart of the app.

**Current phase:**
Formal POC with Rambam hospital — not yet started. The product is ready and waiting.
Success = families using Beacon daily to actively manage their loved one's care.

## מהו הפרויקט

אפליקציית iOS לניהול טיפול רפואי משפחתי עבור משפחות של חולי סרטן.
שפה: עברית. RTL מלא. ארכיטקטורה באפליקציה: SwiftUI + MVVM + SwiftData.

הפרויקט נמצא במצב POC היברידי:

- חלק מהדאטה עדיין מקומי ב-SwiftData.
- מסמכים רפואיים כבר מגיעים מ-Backend Parser API.
- קיימת שכבת backend תחת `backend/` עם FastAPI, Postgres/Alembic, upload, parsing, auth ו-agents.

## מצב נוכחי

- iOS app נבנה עם Xcode/XcodeGen.
- Login/onboarding קיימים באפליקציה.
- Apple Sign-In מחובר ל-Supabase Auth וגם ל-Beacon backend JWT.
- Email/password הוא fallback לפיתוח.
- Google Sign-In קיים בקוד, אבל פעיל רק כשמוגדרים `GOOGLE_CLIENT_ID` ו-URL scheme מתאים.
- תיק רפואי משתמש ב-`BackendDocumentService` מול Parser API.
- משימות, תרופות, מינונים, סימפטומים ופיד עדיין מקומיים ב-SwiftData.
- כרטיס `AISmartSummaryFeatureCard` עדיין משתמש בסיכום דמו סטטי.
- Parsing אמיתי למסמכים קיים ב-backend דרך OCR + Claude/Anthropic.

## ארכיטקטורה

```text
Beacon/
├── Beacon/
│   ├── App/              # RootTabView, Theme
│   ├── Models/           # SwiftData models + backend DTOs
│   ├── ViewModels/       # @Observable per-tab / app environment
│   ├── Views/            # SwiftUI screens
│   ├── Services/         # Auth, Google, backend docs, seeding
│   └── Networking/       # APIClient, TokenStore, APIConfig
├── backend/
│   ├── parser_api/       # FastAPI user-facing API
│   ├── shared/           # DB models, schemas, migrations
│   ├── agents/           # agent graphs + dashboard
│   └── tests/
└── docs/
```

## מוסכמות חובה

- אין לשנות נתוני seed ב-`MockDataSeeder.swift` אלא אם התבקש במפורש.
- אין לכתוב hex codes ישירות ב-Views — תמיד דרך `Theme.Palette`.
- אין לכתוב spacing numbers ישירות — תמיד דרך `Theme.Spacing` או `Theme.Layout`.
- כל ViewModel: `@Observable`, מקבל `ModelContext` בקונסטרקטור כשהוא עובד מול SwiftData.
- Views לא מכילים לוגיקה עסקית — הכל ב-ViewModel/Service.
- RTL נאכף ב-`BeaconApp` וב-Preview helpers, לא ידנית בכל View.
- אין להדפיס או להעתיק ערכי Secrets לתשובות.

## נקודות הרחבה עתידיות

| מה | איפה | הערה |
|---|---|---|
| AI service באפליקציה | `MedicalVaultViewModel` / service חדש | לחבר את כרטיס ה-AI למסמך backend אמיתי |
| Hospital sync | `HospitalSyncAlert` | כרגע התראה מקומית/זרועה |
| Multi-user roles מלאים | `AppEnvironment` + backend households | חלק מקומי, חלק backend |
| Backend tasks/meds/feed | `backend/parser_api/routes` + iOS services | עדיין לא מחובר מלא באפליקציה |
| Audit אמיתי | backend append-only table | באפליקציה כרגע UserDefaults |

## מה מותר לסוכן לעשות ללא אישור נוסף

- קריאת כל קובץ בפרויקט.
- עדכון דוקומנטציה.
- הוספת View/Component.
- הוספת פונקציה ל-ViewModel קיים.
- עדכון Theme tokens.
- הרצת `xcodebuild`.
- הרצת בדיקות backend אם הסביבה קיימת.

## מה דורש אישור מפורש מהמשתמש

- שינוי ב-`MockDataSeeder.swift`.
- שינוי ב-`project.yml`.
- הוספת dependency חדש.
- שינוי schema/migration/backend behavior משמעותי.
- שינוי ערכי Secrets.
- git push.
