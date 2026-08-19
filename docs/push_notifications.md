# Push notifications (APNs) — activation checklist

All the code is written and working (build succeeds, backend tests pass).
What's left needs an **Apple Developer Program membership ($99/year)** —
nothing here is a code task.

## What's already done

- Backend: `parser_api/services/apns_service.py` sends alert pushes over
  APNs' HTTP/2 API; `parser_api/services/notify.py` fans a push out to a
  household (minus whoever triggered it); wired into `POST /v1/feed/` (new
  post) and `POST /v1/caregivers/checkins` (flagged check-in). All unit
  tested (`tests/test_apns_service.py`) except real delivery to Apple.
- Backend: `PUT /v1/me/push-token` saves a device's APNs token onto
  `users.push_token` (that column already existed).
- iOS: `Services/PushService.swift` posts the token after the OS hands one
  over; `App/PushAppDelegate.swift` + `BeaconApp.swift` request notification
  permission and call `registerForRemoteNotifications()` once signed in;
  `Beacon.entitlements` declares `aps-environment`, wired into
  `project.yml`'s `CODE_SIGN_ENTITLEMENTS`.
- Confirmed: none of this affects Simulator builds — entitlements are
  locally self-signed there with no provisioning-profile check. The build
  is clean today with `xcodebuild ... -destination 'platform=iOS
  Simulator,...'`.

## What only the paid account unlocks

1. **Push Notifications capability on the App ID.** In
   [developer.apple.com](https://developer.apple.com) → Certificates,
   Identifiers & Profiles → Identifiers → find (or create) the App ID for
   `com.beacon.app` → enable **Push Notifications**.
2. **APNs Auth Key.** Same portal → Keys → create a new key → check **Apple
   Push Notifications service (APNs)** → download the `.p8` file (Apple
   only lets you download it once — save it somewhere safe, e.g. the
   backend's secrets manager, never in git). Note the **Key ID** shown next
   to it.
3. **Team ID.** Top-right of the developer portal, or Membership Details —
   a 10-character string.
4. **Set these on the backend deployment** (never commit them):
   - `APNS_KEY_ID` — the Key ID from step 2.
   - `APNS_TEAM_ID` — the Team ID from step 3.
   - `APNS_AUTH_KEY` — the full contents of the `.p8` file, including the
     `-----BEGIN/END PRIVATE KEY-----` lines.
   - `APNS_BUNDLE_ID` — defaults to `com.beacon.app`, only set if that
     changes.
   - `APNS_ENVIRONMENT` — `sandbox` while testing via Xcode/TestFlight,
     `production` once shipped through the App Store (App Review builds
     with production APNs regardless of this setting — this only affects
     which host *your* backend calls).

   Once all three of `APNS_KEY_ID` / `APNS_TEAM_ID` / `APNS_AUTH_KEY` are
   set, `APNsService.is_configured()` flips to `true` and sends stop being
   a logged no-op.
5. **A real device to test on.** The Simulator cannot receive real remote
   push, ever — this needs an actual iPhone, signed with the paid team so
   the Push Notifications entitlement is actually in the provisioning
   profile. (Personal, free-account device installs cannot carry this
   capability — see the separate TestFlight/deployment conversation for why
   the paid account is unavoidable here too.)

## After that

Nothing else to build — sign in on two devices, post to the feed from one,
the other should get a push within a few seconds. If it doesn't: check the
backend logs for `apns_send_failed` (Apple rejected the request — usually a
stale/wrong bundle ID or environment mismatch) or `apns_send_error` (network
issue reaching Apple).
