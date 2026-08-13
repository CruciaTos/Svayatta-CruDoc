# CruDoc — Gmail + SMS Messaging Feature — Implementation Plan

Repo audited: `CruciaTos/Svayatta-CruDoc` (cloned, read directly — not from memory).
Scope: new side-nav screen in `DesktopShell` only. Doctor logs in, sends plain email / SMS to a person. No mobile shell changes.

---

## 0. Blunt findings before any of this gets built

These aren't part of the feature but affect it or are severe enough to flag now.

1. **`firestore.rules` is expired and wide-open, and it's already past the expiry date.**
   Root rules file is still the Firebase default placeholder:
   ```
   match /{document=**} {
     allow read, write: if request.time < timestamp.date(2026, 8, 7);
   }
   ```
   Today is Aug 13, 2026 — that condition is now always false. If this is the ruleset actually deployed to the project, **every Firestore read/write in the app is currently being denied.** There's a second file, `firestore_super_admin.rules` (187 lines), that looks like the real, properly-scoped ruleset (per-doctor `isDoctor()`/`isSuperAdmin()` checks, `hasModuleEnabled()` helper, real collection scoping) — but it's sitting under a different filename than what `firebase deploy` reads by default (`firestore.rules`). Looks like it was written and never wired up. This is unrelated to messaging but is worth confirming with whoever owns Firebase deploys before anything else, since it'll also block whatever new collections this feature adds. Not fixing it as part of this plan — flagging because it changes the "already secure" assumption you'd normally have from cloud_functions + firestore.
2. **`google_sign_in` (6.2.2, already a dependency) does not support Windows.** It's officially Android/iOS/Web only — confirmed via the open Flutter issue (#184242, opened Mar 2026, still unresolved) and Google's own plugin docs. `AuthService.signInWithGoogle()` today only works because the app also runs on Android/Web; the desktop build can't call it. This means Gmail login for this feature **cannot** reuse the existing `GoogleSignIn()` instance — it needs its own OAuth2 flow built for desktop (detailed in §4). This is the single biggest architecture decision in this plan, not a minor detail.
3. **`DoctorFeatureGuard.getModuleKeyForTab()` / `getTabTitle()` are already out of sync with `DesktopShell`'s tab order**, independent of this feature. `_labels` in `desktop_shell.dart` is `[Dashboard, Invoices, Patients, Inventory, Revenue, Appointments]` (indices 0–5), but the guard's switch statement maps index 1 → `'patients'`, index 2 → `'inventory'`, index 3 → `'revenue'`, index 4 → `'appointments'`, index 5 → falls to `default` (`'dashboard'`, silently always-enabled) — off by one across the board, and index 5 has no title (falls to `'Feature'`). Looks like the guard was written for the mobile shell's tab order before "Invoices" was inserted into the desktop one, and never updated. Adding tab index 6 for Messaging on top of this without fixing indices 1–5 first would just be adding a 7th bug on top of five existing ones. §7 below fixes all of it, not just the append.
4. **No SMS provider is wired anywhere in this repo.** No Twilio/MSG91/Vonage SDK, no gateway credentials, nothing in `functions/`. This is a from-scratch integration, not a "flip a flag" task.
5. **SMS to Indian numbers is not just an API integration — it's a compliance requirement.** TRAI's DLT (Distributed Ledger Technology) framework legally requires sender-ID and message-template registration for any commercial/transactional SMS sent to Indian mobile numbers. Most patient phone numbers in this app will be Indian (`Functions` region is `asia-south1`, phone auth format in `AuthService` is `+91...`). Twilio can send to India but you still need to complete India-specific registration through them; Indian-native gateways (MSG91, Kaleyra, Gupshup) build DLT registration into onboarding. **This has to be resolved with the doctor/clinic (or whoever owns the sender identity) before SMS sending can go live — no amount of code fixes this.** Flagging as a hard blocker on SMS specifically, not on Gmail.
6. **`omnichannel_messaging` already exists as a plan-gated feature module** — `SubscriptionPlan.professional` and above (`enums.dart:162`), described in the super-admin panel as *"Unified multi-channel messaging platform for sending instant WhatsApp, Email, and SMS reminders & prescriptions"* (`feature_management_provider.dart:229`). This feature should hook into that flag rather than be always-on — it's already wired into `DoctorFeatureGuard.defaultModules`, the chatbot's locked-response check, and the super-admin dashboard toggle. Building this outside that system would fragment the two feature-gating mechanisms that already exist for exactly this feature.

---

## 1. Scope for v1 (assumptions — flag if wrong)

Because "for now simple" was the brief, this plan assumes:

- **In scope:** one new side-nav "Messaging" tab, desktop shell only. Doctor connects their Gmail once, then can send a one-off plain-text email to any name/address. Separately, can send a one-off plain-text SMS to any phone number. Basic send history (so a crash/misclick doesn't leave the doctor wondering if it sent).
- **Out of scope (call out if actually needed):** email templates, attachments, HTML/rich-text body, scheduled/recurring sends, bulk/broadcast sends to patient lists, WhatsApp (despite being named alongside SMS/Email in the module description above), read receipts, two-way SMS/reply handling, recipient picking from an address book beyond basic patient autocomplete.
- **Recipient source:** free-form entry (type an email/phone) plus optional autocomplete against existing `PatientRepository` data, matching the pattern already used in the Add Visit dialog (per prior work on this repo). Not building a separate contacts system.
- **Gmail account identity:** treated as **separate from the doctor's app-login account.** A doctor might log into CruDoc with a personal Google account but want to send from a clinic Gmail address. If they're actually always the same account in practice, §4 gets simpler (skip the separate OAuth client, just request incremental scopes on the existing sign-in) — worth confirming before building.

---

## 2. Architecture overview

```
┌─────────────────────────────────────────────────────────────────┐
│ DesktopShell (side nav)                                         │
│   └── new tab: "Messaging" (index 6, gated on omnichannel_msg)  │
│         └── DesktopMessagingScreen                              │
│               ├── Email tab                                     │
│               │     ├── not connected → GmailConnectCard        │
│               │     └── connected    → ComposeEmailForm         │
│               └── SMS tab                                       │
│                     └── ComposeSmsForm (no login needed)         │
└─────────────────────────────────────────────────────────────────┘
        │                                   │
        ▼                                   ▼
┌───────────────────────┐         ┌─────────────────────────────┐
│ GmailOAuthService      │         │ SmsService                   │
│  - loopback PKCE flow  │         │  - calls Cloud Function       │
│  - token refresh       │         │    (client never sees the     │
│  - stores refresh token│         │    SMS provider's API key)    │
│    in flutter_secure_  │         └──────────────┬────────────────┘
│    storage             │                        │
└───────────┬─────────────┘                        ▼
            ▼                          functions/src/messaging.ts
   Gmail REST API                       sendSms (callable, checks
   users.messages.send                  omnichannel_messaging claim,
   (direct from client,                 calls SMS gateway with server-
   using the doctor's own               side secret, logs result)
   OAuth token — no server
   hop needed for email)
            │                                      │
            └──────────────┬───────────────────────┘
                            ▼
              MessagingRepository.logSent()
              → local sqflite `message_log` table (offline-first,
                matches existing patients/visits pattern)
              → synced to Firestore `users/{uid}/message_logs/{id}`
```

Why email and SMS are handled differently: Gmail send is authenticated as *the doctor's own account* via OAuth — the token only lets them act as themselves, so there's nothing secret to leak by calling the Gmail API directly from the desktop client. SMS gateways (Twilio/MSG91/etc.) authenticate with a **shared account-level API key** — if that key ships inside the Windows `.exe`, anyone can pull it out of the binary and burn the clinic's SMS credits. That has to stay server-side, hence the Cloud Function hop (`cloud_functions` is already a dependency, so this isn't a new category of infrastructure — just a new function next to `appointments.ts`/`super-admin.ts`).

---

## 3. New dependencies

Add to `pubspec.yaml`:

```yaml
dependencies:
  # ... existing ...
  
  # Local loopback server for the OAuth2 redirect during Gmail desktop login.
  # (No new package needed — dart:io's HttpServer covers this, see §4.)
  
  # Nothing new required for Gmail send either — reuse existing `http` package
  # for both the OAuth token exchange and the Gmail REST call. Deliberately
  # NOT adding `googleapis` — it's a heavy generated client for one endpoint,
  # and the rest of this repo prefers hand-rolled models (see patient.dart's
  # comment on skipping freezed). A raw POST to
  # https://gmail.googleapis.com/gmail/v1/users/me/messages/send is ~20 lines.

  # SMS: nothing new client-side either — SMS goes through a Cloud Function,
  # so the client only needs the `cloud_functions` package already present.
```

**Net new Flutter dependencies: zero.** Everything needed (`http`, `flutter_secure_storage`, `cloud_functions`, `url_launcher`) is already in `pubspec.yaml`. This keeps the diff small and avoids the Windows-support question mark that would come with a third-party desktop-OAuth package like `google_sign_in_all_platforms`.

Cloud Functions side (`functions/package.json`) needs the chosen SMS gateway's Node SDK, e.g. `twilio` or `msg91-sdk` — depends on §0.5's open decision.

---

## 4. Gmail desktop login — OAuth2 Authorization Code + PKCE, loopback redirect

This is the part that doesn't exist in this codebase yet and needs building from scratch, since `google_sign_in` is off the table for Windows.

**Google Cloud Console setup (one-time, outside the codebase):**
1. In the same GCP project backing this Firebase project, go to APIs & Services → Credentials → Create Credentials → OAuth client ID → **Desktop app** type (not Web). Desktop-app clients don't require a confidential client secret to be treated as secure — PKCE covers that, which sidesteps exactly the "embedding a client secret in the binary" problem called out in the open Flutter issue in §0.2.
2. Enable the **Gmail API** for the project.
3. Add scope `https://www.googleapis.com/auth/gmail.send` (send-only — deliberately not requesting read/modify access, since this feature never needs to read the doctor's mailbox).
4. Add `http://localhost` (any port) as an authorized redirect URI — this is standard for the installed-app/loopback flow (RFC 8252).
5. If the app is in "Testing" publishing status, add each doctor's Gmail as a test user, or submit for verification once this goes past internal testing — unverified apps show a Google warning screen and cap at 100 users.

**Client-side flow (`GmailOAuthService`, new file under `lib/features/messaging/data/services/`):**

1. Generate a PKCE `code_verifier` (random 43–128 char string) and its `code_challenge` (SHA-256, base64url).
2. Start a local `HttpServer.bind(InternetAddress.loopbackIPv4, 0)` (port 0 = OS picks a free port) — listen for exactly one request on `/`.
3. Build the Google auth URL with `response_type=code`, `client_id`, `redirect_uri=http://localhost:<port>`, `scope=gmail.send`, `code_challenge`, `code_challenge_method=S256`, `access_type=offline` (needed to get a refresh token), `prompt=consent`.
4. Open it via `url_launcher`'s `launchUrl()` — this opens the doctor's system default browser (Chrome/Edge), where they log into Google normally. This is deliberately *not* an embedded webview — Google actively blocks OAuth from embedded/non-standard browser frames as a phishing countermeasure, so the loopback-server-plus-system-browser pattern isn't a stylistic choice, it's the only one Google will accept for a desktop app.
5. Google redirects to `http://localhost:<port>/?code=...`. The waiting `HttpServer` catches that request, extracts `code`, responds with a plain "You can close this tab and return to CruDoc" HTML page, then closes the server.
6. Exchange the code for tokens: `POST https://oauth2.googleapis.com/token` with `code`, `code_verifier`, `client_id`, `redirect_uri`, `grant_type=authorization_code`. Response has `access_token` (short-lived, ~1hr), `refresh_token`, `expires_in`.
7. Store `refresh_token` (and the connected Gmail address, read from the token's `id_token` or a follow-up `userinfo` call) in `flutter_secure_storage` — this is already used elsewhere in the app (`auth_service.dart` clears it on sign-out) and backs onto Windows Credential Manager / macOS Keychain / libsecret, so no new secure-storage story needed.
8. On every send, check if the cached `access_token` is expired; if so, silently refresh via `grant_type=refresh_token` before calling Gmail.
9. "Disconnect" button in the UI just deletes the stored refresh token and revokes it (`POST https://oauth2.googleapis.com/revoke`).

One UX note: Windows Defender Firewall may prompt on first run when the app binds a local listening port. Worth a one-line note in the connect screen ("Windows may ask for network permission — that's the local sign-in redirect, not internet access for the app generally") so it doesn't look like a red flag to the doctor.

---

## 5. Gmail send implementation

`GmailApiService` (new file, same `data/services/` folder):

```
POST https://gmail.googleapis.com/gmail/v1/users/me/messages/send
Authorization: Bearer <access_token>
Content-Type: application/json

{ "raw": "<base64url-encoded RFC 2822 message>" }
```

The raw message is a plain MIME message built from `To`, `Subject`, and a `text/plain` body — no need for a MIME-building package, it's a fixed small template:

```
To: {recipient}
Subject: {subject}
Content-Type: text/plain; charset="UTF-8"

{body}
```
...base64url-encoded (`base64Url.encode(utf8.encode(message))`, strip padding per Gmail's requirement).

Known limits worth surfacing in the UI or docs, not code: personal Gmail accounts cap at ~500 sends/day; Google Workspace accounts at ~2000/day. Fine for one-off sends, worth flagging if this ever grows toward bulk/broadcast.

---

## 6. SMS send implementation

Client side is thin by design — `SmsService.send(phone, message)` just calls:

```dart
final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
    .httpsCallable('sendSms')
    .call({'to': phone, 'body': message});
```

(matches the existing `setGlobalOptions({region: 'asia-south1', ...})` in `functions/src/index.ts`).

Server side — new `functions/src/messaging.ts`, exported from `index.ts` alongside `appointments`/`super-admin`:

- `onCall` function `sendSms`.
- Verify `context.auth` exists (reject anonymous calls) — same pattern as the existing callables in `super-admin.ts`.
- Verify the caller's custom claims include the `omnichannel_messaging` module (mirrors `hasModuleEnabled()` already defined in `firestore_super_admin.rules` — same check, enforced again server-side so client-side gating isn't the only line of defense).
- Basic validation: E.164 phone format, message length (segment-count warning if >160 chars for a single SMS).
- Call the chosen SMS gateway's API with the account credentials pulled from Firebase Functions secret config (`firebase functions:secrets:set`), never from Firestore or the client.
- Return `{success, providerMessageId}` or throw an `HttpsError` the client can surface.
- Log the attempt (success/failure, no full message body needed server-side — the client already has it for the local log) for audit/debugging.

This is a new file, doesn't touch `appointments.ts` or `super-admin.ts` — keeps the addition scope-constrained.

---

## 7. Side nav integration — exact changes

**`lib/features/shell/presentation/desktop_shell.dart`:**

```dart
static const List<String> _labels = [
  'Dashboard', 'Invoices', 'Patients', 'Inventory', 'Revenue', 'Appointments',
  'Messaging',                                                    // new
];

static const List<IconData> _icons = [
  Icons.grid_view_rounded, Icons.receipt_long_outlined, Icons.groups_rounded,
  Icons.inventory_2_outlined, Icons.payments_outlined, Icons.calendar_today_outlined,
  Icons.mail_outline_rounded,                                     // new
];

Widget _buildScreen(int index) {
  switch (index) {
    // ...existing cases 0–5...
    case 6:
      return const DesktopMessagingScreen();                      // new
    default:
      return const SizedBox.shrink();
  }
}
```

**`lib/core/utils/doctor_feature_guard.dart`** — fixing the pre-existing off-by-one from §0.3 *and* adding the new tab in the same pass, since patching only index 6 on top of a broken mapping would leave tabs 1–5 still wrong:

```dart
static String getModuleKeyForTab(int tabIndex) {
  switch (tabIndex) {
    case 0: return 'dashboard';
    case 1: return 'revenue';        // was defaulting wrong — Invoices ties to revenue
    case 2: return 'patients';
    case 3: return 'inventory';
    case 4: return 'revenue';
    case 5: return 'appointments';
    case 6: return 'omnichannel_messaging';   // new
    default: return 'dashboard';
  }
}

static String getTabTitle(int tabIndex) {
  switch (tabIndex) {
    case 0: return 'Dashboard';
    case 1: return 'Invoices';
    case 2: return 'Patient Records';
    case 3: return 'Inventory Management';
    case 4: return 'Revenue & Financials';
    case 5: return 'Appointments & Events';
    case 6: return 'Messaging';               // new
    default: return 'Feature';
  }
}
```
(Index-to-label mapping above is my best guess reading `_labels`' actual order — confirm against whatever "Invoices" is really meant to gate on before merging; the point is that this needs a full pass, not an append.)

Add `'omnichannel_messaging'` module check is already inherited for free since it's already in `DoctorFeatureGuard.defaultModules` — no changes needed there. Since it's a `professional`-plan-and-above feature per `enums.dart`, doctors on `starter` won't have it in their `enabledModules` from Firestore, so `isTabEnabled` will correctly show `MobileFeatureDisabledView` for them, same as any other locked module — no new gating code needed, just the two edits above.

---

## 8. New feature folder — matches existing convention exactly

Following the `features/patients/` layout (`data/models`, `data/providers`, `data/repo`, `data/services`, `presentation`):

```
lib/features/messaging/
├── data/
│   ├── models/
│   │   ├── email_message.dart        # plain class, no freezed — matches Patient
│   │   ├── sms_message.dart
│   │   └── message_log_entry.dart    # unified log record (channel, recipient, status, sentAt)
│   ├── services/
│   │   ├── gmail_oauth_service.dart  # §4
│   │   ├── gmail_api_service.dart    # §5
│   │   ├── sms_service.dart          # §6 (thin, calls Cloud Function)
│   │   └── message_log_local_service.dart  # sqflite table, mirrors local_database_service.dart pattern
│   ├── repo/
│   │   └── messaging_repository.dart # orchestrates: send → log locally → sync to Firestore
│   └── providers/
│       └── messaging_providers.dart  # riverpod: gmailConnectionProvider, sendEmailProvider, sendSmsProvider
└── presentation/
    ├── desktop_messaging_screen.dart # tab container: Email | SMS
    ├── gmail_connect_card.dart       # "Connect Gmail" / connected-as chip + disconnect
    ├── compose_email_form.dart
    ├── compose_sms_form.dart
    └── message_log_list.dart         # simple recent-sends list
```

---

## 9. Data model sketch

```dart
// data/models/message_log_entry.dart
class MessageLogEntry {
  final String id;
  final String doctorId;
  final MessageChannel channel;      // enum: email, sms
  final String recipient;            // email address or E.164 phone
  final String? subject;             // null for SMS
  final String body;
  final MessageStatus status;        // enum: sent, failed
  final String? errorMessage;
  final DateTime sentAt;
}
```

**Firestore:** `users/{doctorId}/message_logs/{logId}` — sibling to the existing `patients`/`appointments` subcollections seen in `firestore_super_admin.rules`. Add there:

```
match /message_logs/{logId} {
  allow read: if isAdminOrDoctor(userId);
  allow create: if isDoctor(userId) && hasModuleEnabled('omnichannel_messaging');
  allow update, delete: if false; // logs are append-only
}
```

(nested inside the existing `match /users/{userId} { ... }` block, alongside `patients`/`appointments`/`medical_records`/`revenue`.)

**Local:** new `message_log` sqflite table, columns mirroring the model, added to `local_database_service.dart`'s schema next to `patients`/`visits`. **Gmail refresh token and SMS never touch Firestore or this local DB — only the log metadata does.** The refresh token lives exclusively in `flutter_secure_storage`.

---

## 10. Error handling / edge cases to design for

- **Offline sends:** this app is offline-first (local sqflite + Firestore sync) for patients/visits, but email/SMS sending fundamentally requires connectivity at send time — there's no "queue and send when back online" for these the way there is for a Firestore write. Simplest v1 behavior: check `connectivity_plus` (already a dependency) before attempting send, show a clear "you're offline" state rather than silently queuing.
- **Gmail token revoked externally** (doctor revokes CruDoc's access from their Google Account settings): refresh call fails with `invalid_grant` → treat as disconnected, prompt re-connect, don't crash the compose screen.
- **SMS gateway failure** (invalid number, insufficient credits, DLT template mismatch): surface the gateway's error message from the Cloud Function's `HttpsError` directly — don't swallow it, since DLT-related rejections need to be actionable for the doctor/clinic admin.
- **Basic input validation:** email regex + phone E.164 check client-side before attempting send, to avoid burning a Cloud Function invocation (and SMS credit) on an obviously malformed number.
- **Duplicate-send guard:** disable the Send button on tap until the call resolves — no debounce logic currently visible elsewhere in the repo to copy, so this is a plain `isSending` local state flag.

---

## 11. Testing

Existing test coverage is minimal (`test/widget_test.dart` default counter test, one encryption unit test — no mocking library in `pubspec.yaml`). Matching that low-ceremony baseline rather than introducing a new testing framework wholesale:

- Add `mocktail` as a dev dependency (lighter than `mockito`, no code-gen step, nothing to fight with `build_runner` which is already used for freezed/json_serializable elsewhere).
- `GmailApiService` / `SmsService`: mock the `http.Client` / `FirebaseFunctions` call, assert request shape (headers, body encoding) and response parsing — not live network calls.
- `MessagingRepository`: test the log-then-sync orchestration with a fake local service + fake Firestore, similar in spirit to `doctor_encryption_service_test.dart`'s isolated-unit style.
- Explicitly **not** testing the OAuth loopback flow end-to-end (needs a real browser + real Google login, not practical in CI) — worth a manual test checklist item instead.

---

## 12. Suggested build order

1. **Cloud Console + Firebase setup** (§4 step 1, SMS provider account) — unblocks everything else, do first.
2. **Gmail OAuth flow** (`GmailOAuthService`) — build and manually verify the loopback + token exchange works standalone before touching UI.
3. **Gmail send** (`GmailApiService`) — verify a real email lands, from a throwaway script/test harness.
4. **SMS Cloud Function** (`messaging.ts`) — deploy, verify a real SMS lands via `firebase functions:shell` or a curl against the callable before wiring the client.
5. **Data layer + local log table + Firestore rules** (§9).
6. **UI** — connect card, compose forms, log list.
7. **Side nav + guard fix** (§7) — wire it in last, once the screen actually works standalone, so the off-by-one fix doesn't get tangled with feature-still-in-progress debugging.
8. **Feature-flag verification** — confirm a `starter`-plan doctor correctly sees the locked state, a `professional`+ doctor doesn't.

---

## Open decisions needed before coding starts

1. **SMS provider** — Twilio (needs separate India DLT onboarding) vs. an India-native gateway (MSG91/Kaleyra/Gupshup, DLT baked into signup). Affects the Cloud Function's SDK choice and the compliance timeline.
2. **Is the Gmail-send account the same as the doctor's app-login Google account, or genuinely separate?** Changes whether §4 needs its own OAuth client at all, or can request incremental `gmail.send` scope on the existing sign-in.
3. **Who owns/deploys the real Firestore rules** (§0.1) — separate issue, but blocks trusting any new rule additions this feature needs until it's resolved.
4. **Confirm the actual intended "Invoices" gating** in §7's guard fix — I inferred `revenue` from context, not from a stated mapping; worth a real answer rather than my guess before that ships.
