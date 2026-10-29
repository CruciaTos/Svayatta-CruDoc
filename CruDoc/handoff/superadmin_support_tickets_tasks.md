# Super Admin tasks: "Bug reports & feedback" tab

Repo: `CrudocSuper-admin` (Flutter web, Riverpod), next to `Svayatta-CruDoc`.
Paste the HEADER, then ONE task. Run the check. Next task only if it passes.
If a check fails twice, stop and bring the error to Claude.

## HEADER (paste before every task)

> Project: Flutter web app `CrudocSuper-admin`. It imports shared widgets
> from `package:crudoc_shared/widgets/cru/cru.dart` (CruCard, CruButton,
> CruIcons, CruType, CruSpace, CruRadius, CruSegmentedControl, `context.cru`
> colours). Never hard-code colours, font sizes or spacing; use those tokens.
> Copy the style of `lib/screens/dashboard/receptionist_lines_screen.dart`.
> Change ONLY the files named in the task. Do not reformat other code.
> Do not edit anything in `../Svayatta-CruDoc`. When done, run
> `flutter analyze lib` and fix every error you introduced.

Data you will read (written by the clinic app, `SupportTicketService`):
collection `support_tickets`, one document per report.

| field | type | notes |
|---|---|---|
| `doctorId` | String | sender's uid |
| `kind` | String | `"bug"` or `"feedback"` |
| `message` | String | up to 4000 characters |
| `status` | String | `"open"` when sent; Super Admin sets `"resolved"` |
| `createdAt` | Timestamp | server time |
| `reporterName` | String? | "Dr. Asha Patil" |
| `reporterEmail` | String? | |
| `clinicId` | String? | |
| `clinicName` | String? | |
| `role` | String? | "Owner", "Receptionist", ... |
| `platform` | String | android, ios, windows, macos, linux, web |
| `device` | String | "Android Mobile / Tablet", "Windows Desktop App", ... |
| `appVersion` | String | "1.0.0+1" |

Every optional field may be missing. Use `?.` and `??` with "—" for text.
Rules (already in `firestore.rules`): only a 2FA-verified Super Admin
(`role == 'superAdmin'`, `isTwoFAVerified == true`) can list them all and
update or delete them.

---

## Task T0: Check nothing exists yet

Search `lib/` for `support_tickets`. If a screen already reads it, stop and
bring its file names to Claude instead of doing T1-T3.

Check: you reported what you found.

## Task T1: Model

Create `lib/models/support_ticket_model.dart` with `SupportTicketModel`
holding every field above (`createdAt` as `DateTime?`), a
`factory SupportTicketModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> d)`
that never throws on a missing or wrongly typed field, and
`bool get isBug => kind == 'bug'` and `bool get isOpen => status != 'resolved'`.

Check: `flutter analyze lib` is clean.

## Task T2: Provider and actions

Create `lib/providers/support_tickets_provider.dart`:

- `supportTicketsProvider`: a `StreamProvider<List<SupportTicketModel>>` on
  `FirebaseFirestore.instance.collection('support_tickets')
  .orderBy('createdAt', descending: true).limit(300)`.
  Filter by kind/status in Dart, not in the query (no index needed).
- `Future<void> setTicketStatus(String id, String status)`: updates
  `status` and sets `resolvedAt: FieldValue.serverTimestamp()` when
  resolving (delete `resolvedAt` when reopening).

Check: `flutter analyze lib` is clean.

## Task T3: Screen and nav entry

Create `lib/screens/dashboard/support_tickets_screen.dart` and add a
"Bug reports" item to the dashboard navigation next to the other tabs.

- Top: `CruSegmentedControl` with All · Bugs · Feedback, and a second one
  with Open · Resolved · All. Show the open count in the title
  ("Bug reports · 3 open").
- One `CruCard` row per ticket: a small "Bug" (amber) or "Feedback" (blue)
  pill, the message (3 lines, tap to expand), then a quiet line:
  `reporterName · clinicName · role · platform appVersion · time ago`.
- Row action: "Mark resolved" / "Reopen" (calls `setTicketStatus`), and
  "Copy email" when `reporterEmail` is present.
- Empty state: "No bug reports or feedback yet."

Check: sign in as Super Admin, open the tab, and confirm the test report
from 29 Oct 2026 shows: kind Bug, message starting
"TEST from Claude: check that super admin sees this bug report",
platform android. Mark it resolved, then reopen it.
