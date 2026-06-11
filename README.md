# Beacon — iOS + Backend POC

Beacon היא אפליקציית iOS בעברית וב-RTL מלא לניהול טיפול רפואי משפחתי עבור משפחות של חולי סרטן.

הפרויקט כבר אינו "Mock בלבד". הוא נמצא באמצע מעבר מ-MVP מקומי ל-POC עם backend:

- אפליקציית iOS ב-SwiftUI, iOS 17+, MVVM + SwiftData.
- Auth באפליקציה: Apple Sign-In, Email dev fallback, ותשתית Google Sign-In כשהסודות ו-URL scheme מוגדרים.
- Supabase עדיין קיים עבור Auth/משפחה ישנה, אבל נוסף גם Beacon backend JWT מול Parser API.
- מסמכים רפואיים נקראים מה-backend, לא מ-SwiftData.
- משימות, תרופות, מינונים, סימפטומים, לו"ז ופיד עדיין מקומיים ב-SwiftData.
- Parsing אמיתי למסמכים קיים ב-backend דרך OCR + Claude/Anthropic.
- כרטיס "סיכום AI חכם" העליון באפליקציה עדיין דמו סטטי מתוך `SampleAISummaries`.

## Current Status

### עובד עכשיו

- `xcodebuild` עובר על סימולטור iOS.
- ארבעת הטאבים הראשיים קיימים: לוח בקרה, תיק רפואי, מעקב טיפול, מעגל תמיכה.
- Login / onboarding / הרשאות / ניהול גישה קיימים באפליקציה.
- העלאת מסמכים, רשימת מסמכים, parse polling וסיכומים מחוברים ל-Parser API.
- Backend FastAPI כולל auth exchange, מסמכים, upload, tasks, households, symptoms, doses ו-agents.

### עדיין חלקי

- backend מקומי דורש Postgres, Python 3.11, venv וסודות.
- אין test target ל-iOS.
- בדיקות backend דורשות התקנת dependencies.
- Google Sign-In דורש `GOOGLE_CLIENT_ID` וגם URL scheme הפוך ב-`Info.plist`.
- משימות/תרופות/פיד עדיין לא עברו ל-backend.
- הזמנות והרשאות משפחתיות באפליקציה עדיין בחלקן mock/local.

## Project Structure

```text
Beacon/
├── Beacon/                 # iOS app
│   ├── App/                # RootTabView, Theme
│   ├── Models/             # SwiftData models + backend DTOs
│   ├── ViewModels/         # @Observable view models
│   ├── Views/              # SwiftUI screens
│   ├── Services/           # Auth, Google, backend docs, seeding
│   └── Networking/         # APIClient, TokenStore, APIConfig
├── backend/                # FastAPI + agents backend
│   ├── parser_api/         # user-facing API
│   ├── shared/             # SQLAlchemy models, schemas, migrations
│   ├── agents/             # Streamlit dashboard + agent graphs
│   └── tests/              # backend tests
├── docs/                   # product/architecture docs
├── project.yml             # XcodeGen spec
└── Beacon.xcodeproj/       # generated Xcode project
```

## iOS Setup

```bash
# optional, only if regenerating the project
xcodegen generate

# build
xcodebuild -project Beacon.xcodeproj \
  -scheme Beacon \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Secrets live in `Beacon/Secrets.plist` and are intentionally gitignored. Use `Beacon/Secrets.example.plist` as the template.

For simulator backend calls, `BACKEND_URL=http://localhost:8000` is fine. For a physical iPhone, set `BACKEND_URL` to a LAN IP or tunnel URL.

## Backend Setup

See [backend/LOCAL_DEV.md](/Users/tomer/projects/Beacon/backend/LOCAL_DEV.md) for the full flow.

Short version:

```bash
cd backend
python3.11 -m venv venv_parser
source venv_parser/bin/activate
pip install -e ./parser_api -e ./shared

export DATABASE_URL="postgresql+psycopg://beacon:beacon_dev@localhost:5432/beacon"
export ANTHROPIC_API_KEY="..."
export STORAGE_BACKEND=local
export LOCAL_API_BASE_URL=http://localhost:8000

alembic -c alembic.ini upgrade head
python -m shared.seed
uvicorn parser_api.main:app --reload --port 8000
```

## Data Ownership

| Area | Current source |
|---|---|
| Documents | Backend Parser API |
| Document upload/parse | Backend Parser API + storage |
| Backend suggested tasks | Backend DB |
| Dashboard tasks | SwiftData local |
| Medications/doses | SwiftData local |
| Symptoms | SwiftData local |
| Feed posts/comments | SwiftData local |
| Permissions UI | Mostly local/AppEnvironment |
| Audit in app | UserDefaults local |
| Agent dashboard | Backend DB |

## Verification

1. Build iOS with `xcodebuild`.
2. Start backend on `localhost:8000`.
3. In the app, use Apple Sign-In or Email dev fallback.
4. Open Settings → אבחון שרת and run `/health`.
5. Upload a PDF/image in Medical Vault and confirm parse status changes.
6. Run backend tests once dependencies are installed:

```bash
cd backend
source venv_parser/bin/activate
pip install -e ./parser_api[dev] -e ./shared
pytest tests
```

## Known Work

- Decide whether tasks/medications should stay local for the next milestone or move to backend.
- Connect the static AI summary card to the latest parsed backend document, or label it clearly as demo.
- Complete Google Sign-In configuration when a real `GOOGLE_CLIENT_ID` is available.
- Add iOS unit tests around ViewModels.
- Replace local UserDefaults audit with append-only backend audit.
- Keep docs aligned with code after every phase.
