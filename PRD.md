# Beacon PRD

Reverse-engineered from the current codebase. This document only describes
capabilities that are explicitly represented in code, schemas, routes, views,
or repository documentation.

## Product Overview

Beacon is a Hebrew, RTL-first iOS application for family coordination around a
single cancer patient's care. Its main value proposition is to give families a
shared operational hub for care tasks, medical documents, medication tracking,
symptom logging, access permissions, and supportive family communication.

The product is currently a hybrid:

- The iOS app is a SwiftUI/SwiftData MVP with four primary tabs.
- Authentication and medical documents are partially backend-connected.
- Dashboard tasks, schedule events, medications, medication doses, symptoms,
  hospital sync alerts, family feed posts, and the optional home-caregiver layer
  are still local SwiftData-backed flows.
- The backend implements a real Parser API for document upload, OCR, Claude
  parsing, document archive operations, household membership, selected care APIs,
  audit logging, and an internal AI-agent control room.

The application language and primary family-facing UX are Hebrew. The new
home-caregiver reporting screen supports English, Tagalog, Hindi, Malayalam,
and Tamil strings for a simplified caregiver-facing check-in flow.

## User Roles & Personas

### Patient

The patient is the person whose care record is being managed.

Code evidence:

- iOS: `MemberRole.patient`, `AppEnvironment.Viewer.patient`.
- Backend: `household_members.role == "patient"`.

Capabilities reflected in code:

- Full app-level read/write access in iOS permission checks.
- Treated as the ultimate access owner in settings copy and logic.
- Can approve pending patient consent in the local iOS state.
- Backend auth creates new Apple/Google users as patient members by default.
- Backend patient/co-owner roles can access restricted document trash/restore
  and caregiver/co-owner invite endpoints.

### Full-access caregiver / Admin / Co-owner

This is a trusted family caregiver with broad management privileges.

Code evidence:

- iOS: `MemberRole.admin`, `hasFullAccess`.
- Backend: `household_members.role == "co_owner"`.

Capabilities reflected in code:

- Full iOS module access.
- Can invite/manage members locally in the iOS settings screen when permitted.
- Backend co-owner can create caregiver invites and access document
  trash/restore.
- In the iOS copy, co-owners/admins remain subordinate to patient consent.

### Partial family member / Caregiver

This is a family member or caregiver with module-specific access.

Code evidence:

- iOS: `MemberRole.member(permissions:)`, `AccessLevel.none/read/readWrite`.
- Backend: `household_members.role == "caregiver"`.

Capabilities reflected in code:

- iOS module access is controlled per module: schedule, tasks, medications,
  medical vault, and feed.
- Read-only users can see data but cannot perform write actions in relevant
  screens.
- Backend caregivers cannot read private documents uploaded by others.
- Backend caregivers can only soft-delete documents they uploaded.

### Home caregiver without app account

This is the optional foreign/home caregiver layer added to the iOS app.

Code evidence:

- iOS SwiftData models: `CaregiverProfile`, `CaregiverCheckIn`.
- iOS view model: `CaregiverLayerViewModel`.
- iOS views: `CaregiverSetupSheet`, `CaregiverReportView`,
  `CaregiverUpdateCard`, `CaregiverCheckInDetailView`.

Capabilities reflected in code:

- Family can activate/deactivate a local caregiver profile.
- Caregiver has no authenticated app account and no access to the medical vault
  or broader app.
- Family opens a kiosk-style reporting screen and hands the device to the
  caregiver.
- Caregiver submits structured daily updates in their selected language.
- Family receives a Hebrew summary, alert level, structured fields, and actions
  to create a follow-up task or share to the family feed.

### Founder / internal operator

This is an internal user of the backend Streamlit control room.

Code evidence:

- `backend/agents/dashboard.py`.
- Agent models: `AgentRun`, `SupportTicket`, `AgentMetricsSnapshot`,
  `ChiefBrief`, `ChiefConversation`, `Initiative`, `PendingAgentTask`.

Capabilities reflected in code:

- Reviews agent drafts before execution.
- Approves or rejects draft push messages, support replies, reports, security
  briefs, and content drafts.
- Uses the Chief Agent tab for daily briefs, initiatives, and conversations.

## Core Features & Workflows

### 1. Authentication and session routing

The app routes users through a root auth state machine:

- `loading`: splash while checking session.
- `unauthenticated`: login screen.
- `needsOnboarding`: create a patient/family profile.
- `authenticated`: main tab UI.

Implemented sign-in paths:

- Apple Sign-In via `AuthenticationServices` and Supabase.
- Apple token exchange with the Beacon backend JWT route
  `POST /v1/auth/apple`.
- Google Sign-In via the GoogleSignIn SDK and backend route
  `POST /v1/auth/google`.
- Email/password development fallback via Supabase.

Session and credential handling:

- Supabase sessions are managed by Supabase Swift.
- Beacon backend JWTs are stored in Keychain via `TokenStore`.
- `AppEnvironment` can restore a backend-only session if the JWT is present and
  not expired.
- `DiagnosticView` can probe `/health` and `/v1/households/members`.

Ambiguity:

- The code contains both Supabase family/profile flows and newer Beacon backend
  household flows. They are not fully unified.
- Google Sign-In currently passes `nonce: nil` from iOS. The backend requires a
  nonce outside the development bypass path.

### 2. Onboarding and patient profile setup

The onboarding flow collects:

- Patient name.
- Patient age.
- Hospital.
- Primary doctor.
- Blood type.
- Allergies.
- Emergency contact name and phone.
- Patient verification email.
- Local confirmation that an ID photo exists.
- Caregiver name.

Behavior reflected in code:

- Creates a local `PatientProfileDraft`.
- If the current user is the patient, patient authorization becomes approved.
- If a caregiver creates the profile, the case is marked pending patient consent.
- In preview/local paths, data is cached locally in `UserDefaults`.
- In Supabase-authenticated paths, `AuthService.createFamily` calls the
  `create_family_for_current_user` Supabase RPC.

Current limitation:

- ID-photo verification is a local boolean only. No secure document upload or
  verification workflow is implemented in iOS.

### 3. Access, permissions, and consent gating

The iOS app defines five access-controlled modules:

- Schedule.
- Tasks.
- Medications.
- Medical Vault.
- Feed.

Each module can be:

- No access.
- Read-only.
- Read/write.

Behavior reflected in code:

- `RootTabView` keeps tabs visible but shows an access-denied screen when the
  active user lacks permission.
- Pending patient consent blocks protected care modules for non-patient users,
  while allowing feed access.
- `PermissionsSettingsView` lists patient owner, full-access caregivers, and
  partial members.
- Partial member permissions can be edited locally.
- Access can be revoked locally.
- Local audit events are stored in `UserDefaults`.
- The app caps non-patient caregivers/members at five.

Backend role model:

- `household_members` is the authoritative backend membership table.
- Roles are `patient`, `co_owner`, and `caregiver`.
- Backend role checks gate co-owner invite, caregiver invite, document trash,
  and restore endpoints.

Current limitation:

- iOS permission edits are local and do not appear to call the backend
  household membership routes.
- The iOS invite UI is mock/local, while backend invite-code endpoints exist.

### 4. Main app navigation

The authenticated iOS app has four tabs:

1. Dashboard.
2. Medical Vault.
3. Proactive Care.
4. Circle of Trust.

The default tab bar is hidden and replaced with a custom Hebrew RTL bottom tab
bar. The app enforces Hebrew locale and RTL layout at `BeaconApp`.

### 5. Dashboard

The dashboard shows:

- Greeting based on current hour.
- Current Hebrew date.
- Optional latest home-caregiver update card.
- Family schedule card when schedule access is allowed.
- Today tasks card when task access is allowed.
- Permission notice cards when access is blocked.

Task actions:

- Claim a task.
- Release a task.
- Toggle completion.

Data source:

- `ScheduleEvent` and `DailyTask` are local SwiftData models seeded by
  `MockDataSeeder`.

### 6. Medical Vault

The Medical Vault is the most backend-connected iOS area.

Implemented user-facing capabilities:

- Backend document listing from `GET /v1/documents/`.
- Pull-to-refresh.
- Cursor-based pagination synthesized client-side from the last row.
- Search via backend `q` query.
- Category filter chips.
- Upload from camera, photo library, or files.
- Upload metadata sheet for category and privacy.
- Upload progress overlay.
- Duplicate upload handling based on backend hash conflict.
- Parse kickoff via `POST /v1/documents/{id}/parse`.
- Polling document status until parsed or failed.
- Document cards with parsing, failed/retry, summary, and private states.
- Document detail screen showing full parsed summary, metadata, privacy, status,
  category, and flagged-for-review warnings.

Backend document capabilities:

- Presign upload: `POST /v1/uploads/presign`.
- Local dev PUT endpoint: `PUT /v1/uploads/local/{document_id}`.
- Finalize with SHA-256 deduplication: `POST /v1/uploads/finalize`.
- Batch finalize up to 15 items.
- List documents with filters.
- Soft delete.
- Trash listing for patient/co-owner.
- Restore from trash for patient/co-owner.
- Patch filename, category, and privacy.
- Parse with OCR and Claude.
- Clean up storage after successful parse.

AI parsing:

- OCR uses Tesseract locally or AWS Textract by configuration.
- Claude parsing is category-routed.
- Admin documents use Haiku.
- Lab, prescription, imaging, consult, referral, and default flows use Sonnet.
- Parser returns Hebrew summaries, simple summaries, suggested tasks, detected
  category, and flagged-for-review state.
- A heuristic flags documents that appear to contain multiple PHI patterns.

Current limitation:

- The top "AI smart summary" card in iOS still uses static
  `SampleAISummaries.dashboardFeatured` data, not the latest backend document,
  even though backend parsed summaries are available.
- Backend suggested tasks are persisted as backend `Task` rows, but the iOS
  visible dashboard tasks are still local SwiftData `DailyTask` rows.

### 7. Proactive Care

The Proactive Care tab handles medications, dose status, low stock, and symptom
logging.

Implemented capabilities:

- Shows low-stock medications.
- Creates a local refill task for a low-stock medication.
- Shows a missed-dose alert.
- Marks missed dose as taken.
- Adds a local note to a missed dose.
- Lists today's upcoming/scheduled doses.
- Marks a dose as taken.
- Shows quick symptom buttons.
- Supports custom symptom logging with label, severity, and note.
- Shows recent symptoms.

Data source:

- iOS uses local SwiftData `Medication`, `MedicationDose`, and `SymptomEntry`.

Backend overlap:

- Backend has `medications`, `dose_events`, and `symptom_reports` tables.
- Backend exposes `POST /v1/symptoms/` and `POST /v1/doses/{id}/taken`.
- The current iOS Proactive Care view model does not call those backend routes.

### 8. Circle of Trust

The Circle of Trust tab is a family support feed.

Implemented capabilities:

- Compose a post when feed write permission is granted.
- Optionally publish as the patient if the current user has full access.
- Attach a status to the post.
- React with heart or hug.
- Add comments.
- Empty state when there are no posts.

Data source:

- Local SwiftData `FeedPost` and `FeedComment`.

Current limitation:

- There is no backend route or sync layer for feed posts/comments in the current
  codebase.

### 9. Home caregiver layer

This is an optional layer for a foreign/home caregiver who is physically with
the patient.

Family setup:

- Accessible from `PermissionsSettingsView`.
- Family can create/update an active caregiver profile with name, relation
  title, and preferred language.
- Family can deactivate the layer.
- Deactivation removes dashboard visibility but keeps historical check-ins.

Caregiver reporting:

- The report screen is localized for English, Tagalog, Hindi, Malayalam, and
  Tamil.
- The screen uses large buttons and sliders.
- Inputs include meal, hydration, sleep, pain, nausea, fatigue, medication
  status, and free-text note.
- The screen is intentionally LTR for the supported caregiver languages unless
  a language is marked RTL.

Family output:

- A Hebrew summary is generated by `LocalMockCaregiverTranslationService`.
- The service is rule-based, not real AI translation.
- Alert reasons are generated for high pain, missed medication, not eating, not
  drinking, uncertainty around medication, and risk keywords in supported
  languages.
- Urgent level is triggered by very high pain or urgent keywords.
- Caregiver-reported pain, nausea, and fatigue are inserted into the shared
  local `SymptomEntry` stream.
- Family can acknowledge a check-in, create a follow-up task, or share the
  Hebrew summary to the family feed.

Current limitation:

- This layer is local-only. There is no backend caregiver account, no remote
  sync, no push notification, and no real translation service yet.

### 10. Household membership and invites

Backend capabilities:

- List household members: `GET /v1/households/members`.
- Create targeted co-owner invite with 6-digit code.
- Accept co-owner invite.
- Create open caregiver invite.
- Join household as caregiver with code and household ID.
- Invite codes are stored hashed and have a configurable TTL.

iOS capabilities:

- There is a mock invite sheet showing the intended flow.
- `InviteService` still supports Supabase-style deep links
  `beacon://join?token=<UUID>`.

Current limitation:

- The backend 6-digit invite-code flow is not integrated into the iOS invite UI.
- The Supabase invite-token flow and backend invite-code flow coexist.

### 11. Account deletion and audit logging

Backend:

- `DELETE /v1/me` implements account erasure.
- If the user is the last member of a household, the backend deletes household
  PHI rows in dependency order.
- If other users remain, user references on tasks are nulled and the user is
  deleted.
- Backend writes `AuditLog` entries for auth, upload finalize, parse, task
  approval/edit/claim, symptom report, dose taken, membership joins, document
  delete/restore, and GDPR erasure.

iOS:

- Local audit events are stored in `UserDefaults` for local access actions.

Current limitation:

- The iOS app does not expose the backend erasure endpoint in the visible UI.
- Local iOS audit and backend audit are separate systems.

### 12. Internal AI-agent control room

The backend includes an internal Streamlit dashboard and scheduled AI agents.

Agents represented in code:

- Guardian: daily security/privacy auditor.
- Customer Success: proactive nudges and reactive support replies.
- Product: weekly usage analysis and recommendations.
- Creative: weekly/on-demand content drafting.
- Chief Agent: daily synthesis, initiatives, and chat with cited context.

Control room behavior:

- Agent drafts are stored in `agent_runs`.
- Human approval is required before execution.
- Approved push/support/report actions are executed by `agents.executor`.
- Chief Agent can use whitelisted tools over non-PHI aggregate views and agent
  outputs.
- Chief Agent can queue tasks for operational agents through
  `pending_agent_tasks`.
- Scheduler runs agents on cron-like cadences and purges soft-deleted documents
  after 30+ days.

Current limitation:

- This is an internal/admin surface, not part of the iOS user experience.
- Some agent queries reference aggregate views that must exist in the deployed
  database.

## Data Models & Entities

### iOS local SwiftData entities

`ScheduleEvent`

- Care schedule item with title, start time, kind, optional location, companion,
  and subtitle.

`DailyTask`

- Family task with title, detail, kind, origin, created date, optional due date,
  claimed member, and completion state.

`Medication`

- Medication profile with name, dosage, usage instructions, form, stock count,
  and low-stock threshold.

`MedicationDose`

- Scheduled dose snapshot with medication name/dosage, form, scheduled time,
  status, optional taken time, and note.

`SymptomEntry`

- Symptom log with type, severity, optional custom label, note, and timestamp.

`HospitalSyncAlert`

- Local alert for hospital-origin updates with title, body, source hospital,
  timestamp, unread state, and optional linked document ID.

`FeedPost` and `FeedComment`

- Family feed post/comment models with author, body, status, audience, reaction
  counts, timestamps, and comments.

`CaregiverProfile`

- Local active/inactive home caregiver profile with display name, relation,
  preferred language, and creation date.

`CaregiverCheckIn`

- Local structured caregiver report with meal/hydration/sleep, symptom levels,
  medication status, original language/text, Hebrew summary, attention level,
  alert reasons, and acknowledgement state.

### iOS DTOs for backend data

`BackendUser`

- Mirrors backend auth user response with ID, household ID, role, and full name.

`BackendHouseholdMember`

- Mirrors backend household member output.

`BackendDocument`

- Mirrors backend document output including document status, category,
  privacy, flagged-for-review metadata, parsed summaries, and timestamps.

`PendingUploadFile`

- In-memory selected file pending upload.

`BackendPresignResponse`, `BackendFinalizeResponse`, `BackendParseResponse`

- API response DTOs used in the document upload and parse flow.

### Backend PHI and care entities

`Household`

- Tenant/care record container. Holds encrypted patient name field and links to
  users, members, documents, tasks, medications, and symptom reports.

`User`

- Authenticated backend identity with Apple or Google provider ID, display
  name, legacy role, household ID, push token, locale, and creation date.

`HouseholdMember`

- Authoritative backend membership row with role `patient`, `co_owner`, or
  `caregiver`.

`HouseholdInvite`

- Hashed 6-digit invite code for co-owner or caregiver membership.

`Document`

- Medical document metadata and parsed content, including upload source,
  storage URI, mime type, filename, status, category, summary fields, OCR text,
  content hash, privacy, soft-delete fields, and PHI flagging.

`Task`

- Backend task suggested from parsed documents or later approved/claimed/edited.
  Contains status, due date, audit fields, and edit history.

`Medication` and `DoseEvent`

- Backend medication schedule and dose-tracking tables.

`SymptomReport`

- Backend symptom event with kind, severity, note, and timestamp.

`AuditLog`

- Append-style backend audit row for security, care, document, membership, and
  account actions.

### Backend agent entities

`AgentRun`

- Stores operational agent input summaries, output drafts, approval state, and
  execution result.

`SupportTicket`

- Support inbox item with subject/body/status and draft response.

`AgentMetricsSnapshot`

- Stores reports/metrics snapshots from approved agent outputs.

`DocChunk`

- RAG corpus chunk with vector embedding for public/support documentation.

`Initiative`

- Founder-initiated thread tracked by Chief Agent.

`ChiefBrief`

- Daily synthesized Chief Agent brief with citations.

`ChiefConversation`

- Conversation messages between founder and Chief Agent.

`PendingAgentTask`

- Queue of Chief Agent instructions for operational agents.

### Supabase legacy schema

The repository includes `docs/supabase_schema.sql`, and `AuthService` still uses
Supabase tables/RPCs:

- `families`
- `profiles`
- `family_members`
- `invite_tokens`
- `create_family_for_current_user`
- `accept_invite`

This is a separate family/membership model from the newer backend
`households`/`household_members` model.

## Technical Stack

### iOS

- Swift 5.9.
- iOS 17+.
- SwiftUI.
- SwiftData.
- Observation framework with `@Observable` ViewModels.
- MVVM-style organization.
- AuthenticationServices for Apple Sign-In.
- Supabase Swift SDK.
- GoogleSignIn and GoogleSignInSwift.
- URLSession-based backend API client.
- Keychain storage for Beacon backend JWT.
- PhotosUI, file importer, and camera picker for document intake.
- XcodeGen via `project.yml`.
- Asset catalog color tokens through `Theme.Palette`.

### Backend Parser API

- Python 3.11+.
- FastAPI.
- Uvicorn.
- Pydantic v2.
- Pydantic Settings.
- SQLAlchemy 2.0.
- PostgreSQL.
- Alembic migrations.
- psycopg.
- pgvector.
- python-jose JWT handling.
- Anthropic SDK.
- AWS S3 or local disk storage.
- AWS Textract or Tesseract OCR.
- Pillow and pdf2image for local OCR.
- slowapi dependency present.
- pytest for backend tests.

### Backend Agents

- Streamlit control room.
- LangGraph agent graphs.
- Anthropic / LangChain Anthropic dependencies.
- APScheduler.
- SQLAlchemy/PostgreSQL shared data layer.
- pgvector embeddings for agent search.
- HTTPX for outbound execution helpers.

### Infrastructure and configuration

- iOS secrets come from `Beacon/Secrets.plist`.
- Backend config comes from environment variables and `.env`.
- Parser API defaults local storage and localhost backend URL for development.
- Backend refuses to boot in non-development environments if the JWT signing key
  remains the development default.

## Current State / TODOs

### Implemented and usable in current code

- Four-tab Hebrew RTL iOS app shell.
- Apple, Google, and email-dev sign-in paths in iOS code.
- Root auth routing and onboarding.
- Local patient profile, consent, permissions, and audit state.
- Local dashboard schedule/tasks.
- Backend-backed medical document listing/upload/finalize/parse/polling.
- Backend OCR + Claude document parsing.
- Backend document deduplication, privacy, soft delete, trash, restore, and
  flagged-for-review logic.
- Local medication/dose/symptom tracking.
- Local family feed.
- Optional local home-caregiver reporting layer.
- Backend household member and invite-code endpoints.
- Backend account erasure endpoint.
- Backend agent control room, scheduler, and Chief Agent tables/tools.

### Partially implemented or disconnected

- Supabase family/membership and backend household/membership coexist.
- iOS settings invite flow is mock, while backend invite-code endpoints exist.
- iOS module permission edits are local and not synced to backend.
- iOS dashboard tasks are local, while backend suggested tasks are created from
  parsed documents.
- iOS Proactive Care remains local despite backend symptom and dose endpoints.
- iOS feed remains local and has no backend route.
- The Medical Vault's prominent AI summary card is static sample data.
- Home-caregiver reports are local-only and use rule-based summary generation.
- Hospital sync alert is seeded/local only.
- Backend document delete/trash/restore/patch exists, but current iOS Medical
  Vault UI mainly exposes upload/list/parse/detail/retry.
- Google Sign-In production nonce handling appears incomplete on the iOS side.
- No iOS test target is visible in the project configuration.

### Areas needing product/technical clarification

- Which identity and household model is the future source of truth:
  Supabase `families/family_members` or backend `households/household_members`.
- Whether backend `caregiver` means a logged-in family caregiver, the foreign
  home caregiver, or both. The current iOS home-caregiver layer is explicitly
  no-account/local, while backend caregiver is an authenticated household role.
- Whether document-derived backend suggested tasks should replace or sync into
  local `DailyTask`.
- Whether medications, doses, symptoms, and feed should migrate to backend for
  multi-device/family sync.
- How patient consent should be legally verified beyond the current local email
  and ID-photo checkbox.
- Whether the home-caregiver reporting screen should become a real separate
  account/session, a shared-device kiosk mode, or a secure invite link.
- Whether static AI summary demo content should be removed, relabeled, or wired
  to `featuredDocument`.
- What data the internal agents are allowed to access in production, and which
  aggregate views must be guaranteed by migrations/deployment.
