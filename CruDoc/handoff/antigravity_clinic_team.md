# Antigravity tasks: dental features and clinic team login

You are building two connected changes in this codebase. This whole file is
your brief. Claude (the lead) reviews your work at the GATE points and
updates this file.

- **Phase 0 (dental features): done.** See "Done" below.
- **Phases 1–7, T20–T22: done.** **T18–T19 left:** clinic login: several doctors, an admin,
  staff and custom staff roles. See Design B.

## ▶ DO NOW

Claude built T9–T17 and T20–T22 (see "Done"). Left: **T18 and T19** (who
the patient sees, doctor picker and filters), then the checks.

**Do Tasks T18 and T19, back to back.** Follow "How to work" below: write
both first, then run the Checks once at the end:
1. `flutter analyze` (no errors; `test/whatsapp_repository_test.dart` was
   already broken before this work, ignore it).
2. Run the app on Windows signed in as an existing doctor: patients,
   appointments and revenue look as before, and the Team section opens and
   lists them as Owner.
3. End to end on the dev project (ask the user for the two test phone
   numbers): invite test phone 1 as Receptionist and test phone 2 as a
   Doctor with another specialty; each signs in, joins, and sees only
   their tabs; the doctor picker shows both doctors.
Then stop at GATE 5 and report every file you changed, the Check outputs,
screenshots (Team screen, invite dialog, role editor, a receptionist's
sidebar, the doctor filter) and anything you skipped.

---

## Rules

> Project: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc`, a Flutter app on
> Firebase. Shared widgets live in `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\crudoc_shared`.
> Follow the Design sections below exactly.
> - Change ONLY the files the task names (you may create the new files it names).
>   Do not reformat or "improve" other code.
> - These files contain the user's uncommitted work: `onboarding_flow.dart`,
>   `profile_screen.dart`, `desktop_settings_screen.dart`, `loyalty_card.dart`,
>   `loyalty_card_view.dart`. Never revert, reformat or rewrite them. Add or
>   change only the lines a task names.
> - Never deploy (no `firebase deploy`, no `gcloud`). Never `git commit`/`push`.
> - Dart UI: read `CruDoc/.claude/rules/crudoc-ui.md` and follow it
>   (`context.cru` colours, `CruSpace`, `CruRadius`, `CruType`; no hard-coded
>   colours/sizes). Red is only for patient safety, so "Remove" is never red.
> - Run only the test files the task names. Never run the whole `flutter test`
>   suite (parallel runs crash on sqlite3.dll).
> - Don't delete or rewrite any dental specialty screen under
>   `lib/features/dental/specialties/`. Only how they are switched on changes.
> - The permission keys (`patients.view`, `schedule`, …) and dental feature
>   keys (`perio`, `oral_medicine`, …) are stored in Firestore. Spell them
>   exactly as in the Design tables, in Dart, TypeScript and rules alike.
> - When done, list every file you changed and paste the output of the Checks.

### How to work

- **Build first, check last.** Do every task in the DO NOW list one after
  another. Don't run `flutter analyze`, tests or builds after each task.
  Each task's **Check** says what to verify; collect them and run them all
  once, after the last task of the DO NOW list: one `flutter analyze` for
  the whole project, then the named tests, then the app run. Fix what fails
  and run them again.
- **Never wait.** Start anything slow (`flutter test`, `flutter run`,
  `flutter build`, `npm` builds, emulators) in the background and keep
  working on the next task or file while it runs. Read its output when it
  finishes. Run independent checks at the same time, except that two
  `flutter test` runs never run together (sqlite3.dll crash).
- **Don't stop mid-way.** Where a task says "STOP" because the code doesn't
  match the brief, don't guess and don't halt the whole run: leave that one
  part undone, write down what you found, and carry on with everything else.
  List every skipped part in your report.
- **The GATE lines are the only real stops.** At a GATE, report and wait for
  Claude to update this file.

---

## Done

**Phase 0 — dental features (GATE 0 passed 2026-10-07).** Dentists have no
sub-specialties any more. Each dentist picks dental features, stored as
`users/{uid}.dentalFeatures` (keys: `chairside`, `radiology`, `perio`,
`endo`, `pedo`, `ortho`, `prostho`, `surgery`, `pathology`,
`oral_medicine`, `sedation`, `public_health`). Code you may use:
`lib/features/dental/dental_features.dart` (`DentalFeature`,
`DentalFeature.defaults`), `lib/features/dental/presentation/dental_features_picker.dart`
(`DentalFeaturesPicker`), and in `lib/core/providers/specialty_provider.dart`:
`isDentalProvider`, `dentalFeaturesProvider`, `saveDentalFeatures`,
`isDentistProvider` (dentist + chairside), `hasDentalRadiologyProvider`.

**Phases 1–2 — model and security rules (GATE 1 passed 2026-10-07).**
`lib/core/clinic/` has `clinic_permission.dart` (`ClinicPermission`,
`normalizePermissions`), `clinic_models.dart` (`MemberKind`, `ClinicRole`,
`ClinicMember`, `ClinicInvite`, `Clinic`), `role_templates.dart` and
`clinic_access.dart` (`ClinicAccess`). `firestore.rules` and
`storage.rules` enforce the Design B permissions, with tests in
`tests/firestore-rules` and `tests/storage-rules`. Storage folders under
`doctors/{clinicId}/patients/{patientId}/`: `avatar/` needs
`patients.view` (write `patients.edit`), `invoices/` needs `billing`,
everything else there needs `clinical.view` (write `clinical.edit`).

**Phase 3 — Cloud Function (GATE 2 passed 2026-10-07).** Deployed to the dev
project with the new rules and indexes on 2026-10-07; two Firebase Auth test
phone numbers exist (ask the user for them).
`functions/src/clinic.ts` exports `clinicTeam` (one callable, region
`asia-south1`, field `action`), `mirrorPlanToClinic` (trigger) and
`loadCaller`. Actions and their data:

| action | data | returns |
|---|---|---|
| `ensureClinic` | clinicName, ownerName, specialty | {clinicId} |
| `myInvites` | — | {invites: [{id, clinicId, clinicName, name, kind, roleName, invitedByName, expiresAt (ISO)}]} |
| `acceptInvite` | clinicId, inviteId | {success, clinicId} |
| `invite` | clinicId, name, phone or email, kind, roleId, specialty?, modules?, dentalFeatures? | {inviteId} |
| `cancelInvite` | clinicId, inviteId | {success} |
| `updateMember` | clinicId, uid, roleId?, kind?, specialty?, modules? (null = no limit) | {success} |
| `removeMember` | clinicId, uid | {success} |
| `saveRole` | clinicId, roleId? (none = new), name, kind, perms | {roleId} |
| `deleteRole` | clinicId, roleId | {success} |

Escalation rule on the server: only the owner or an admin may give the
admin role or `team`; anyone else may only give, or edit roles holding,
permissions they have themselves.

**T7–T8 (GATE 3 passed 2026-10-07).** `lib/core/clinic/clinic_session.dart`
has `ClinicSession` (`load`, `reload`, `clear`, `access`, `member`,
`tenantId`, `stream`, `removed`, `previousClinicId`), `clinicAccessProvider`
and `activeClinicProvider`. A permission-denied read of the member doc
counts as removed. `handoff/clinic_tenant_usages.md` lists every uid usage;
its "Claude's review" section at the top decides the UNSURE rows and adds
usages the search missed.

**T9–T17, T20–T22 (built by Claude, 2026-10-07; analyze clean, unit tests
pass; not yet run on a device).**
- Tenant switch: every per-clinic read uses `ClinicSession.instance.tenantId`
  (see `handoff/clinic_tenant_usages.md`). `main.dart` `_followClinic` loads
  the clinic on sign-in, re-opens data when it changes, and on removal
  clears that clinic off the device and signs out. Local DB file per clinic
  and person (`LocalDatabaseService.scopeFor`); owners keep their old file.
- Join: `lib/core/clinic/clinic_team_api.dart`,
  `lib/features/team/presentation/join_clinic_screen.dart`, wired in
  `responsive_shell.dart` (invites before onboarding; the shell waits for
  the clinic and is keyed by it).
- Team UI: Settings → **Team** (`team_section.dart`: People, Roles,
  Activity; `invite_sheet.dart`, `member_sheet.dart`,
  `role_editor_sheet.dart`, `features_checklist.dart`,
  `activity_log_view.dart`) and Settings → **My features** for members.
  `showSettingsSection` in `desktop_settings_screen.dart` decides which
  sections show.
- Permissions in the app: `lib/core/clinic/clinic_tabs.dart` hides pages a
  role can't open (sidebar, phone tabs, voice); staff get
  `NotAvailableView` instead of an upgrade prompt; the feature guard reads
  the clinic's plan for staff; sync and first-run migration skip
  collections the person can't read; money (collections, revenue
  overview) needs `revenue`; clinical parts of the patient page and dental
  features need `clinical.view`; Edit/Delete/New visit follow
  `patients.edit` / `schedule`. Use `clinicCanProvider(ClinicPermission.x)`.
- Functions: `getImagingView` accepts any member with `clinical.view`;
  `createAppointment` / `getAvailability` write and read `doctorId` = the
  doctor's clinic and `attendingDoctorUid` = the doctor (T18 must write
  `attendingDoctorUid` in the app for this to block the right slots).
  Deployed.

---

## Design B — Clinic team (Phases 1–9)

### Goal

Today one Firebase account = one doctor = one set of data. A clinic needs
several doctors (different specialties), an admin, and staff such as
receptionists, assistants and accountants, each seeing only what their job
needs. The clinic admin can also create their own staff categories ("Lab
technician", "Front desk – evening") and tick what each one may do.

### Words

| Word | Meaning |
|---|---|
| Clinic | The account that owns the data. Doc `clinics/{clinicId}`. |
| Owner | The person who created the clinic. **`clinicId` = the owner's uid.** |
| Member | Anyone working in the clinic, owner included. Doc `clinics/{clinicId}/members/{uid}`. |
| Kind | `doctor` or `staff`. Doctors have a specialty and appear in "Doctor" pickers. |
| Role | A named set of permissions. Doc `clinics/{clinicId}/roles/{roleId}`. Custom roles are the "staff categories". |
| Permission | One of the 12 keys below. |
| Tenant id | The clinic id, as stamped in every record's existing `doctorId` field. |

### The key idea: no data migration

Every record already carries `doctorId` = the doctor's uid, and files live
under `doctors/{doctorId}/`. We **keep that field and those paths** and
redefine them to mean "the clinic". Because a clinic's id is its owner's uid,
every existing doctor is already the owner of a one-person clinic, and every
existing record already belongs to it. Nothing is rewritten.

- In code, the value written into `doctorId` comes from
  `ClinicSession.instance.tenantId` (T7), never from `currentUser.uid`.
- For an owner, `tenantId == uid`, so solo doctors behave exactly as before
  even if a usage is missed. Mistakes only show up for staff.
- New optional fields on schedule/money records: `attendingDoctorUid` (who
  the patient sees) and `createdByUid` (who typed it). Empty
  `attendingDoctorUid` means the owner.

### Solo practice stays exactly as it is

Onboarding is not changed. A doctor who picks "Solo practice" works as
today: no `clinics` doc, no member doc, no extra reads, same database file.
The only visible addition is a **Team** entry in Settings; nothing is
created until they open it (that's how a solo practice later adds a
receptionist). "Clinic" in onboarding also works as today.

### What is shared and what is per person

| Shared by the clinic | Per person |
|---|---|
| Patients and all records, appointments, queue, invoices, revenue, inventory, procedure catalog | Specialty (`users/{uid}.specialty`) and, for dentists, their dental features (`users/{uid}.dentalFeatures`: perio, ortho, prostho, radiology, …) |
| The clinic's features (its plan: `clinics/{id}.enabledModules`) | Which of those features they use: `members/{uid}.modules` |
| Clinic name and branding | Scribe notes, Gmail, devices, theme, profile |

A dentist and a homeopath in one clinic each get their own specialty
screens and their own set of tabs; two dentists can use different dental
features (one ortho + radiology, the other perio + prostho). Staff use the
clinic's specialty and the default dental features. A person's tabs are:
**clinic features ∩ what their role allows ∩ their own `modules`**
(`modules` missing = no personal limit). `modules` is a preference, not
security: the permissions decide what data they can reach.

### Decisions (fixed for this brief: C1–C6)

- **C1** All members with `clinical.view` see every patient of the clinic.
  "Own patients only" is not in this brief.
- **C2** Staff sign in with phone OTP or Google (both already exist). No
  passwords. An invite is matched to the signed-in phone number or verified
  email.
- **C3** Seats per clinic: 5 doctors, 10 staff, until plans define them
  (`clinics/{id}.seats`).
- **C4** The owner can't be removed or changed. No ownership transfer.
- **C5** Firestore and Storage rules read the member doc on every staff
  request, so a removed member loses access at once (one extra read per
  staff request; owners cost nothing extra).
- **C6** A user may be a member of several clinics; `users/{uid}.clinicId`
  is the active one. A switcher UI is not in this brief.

### Permissions

| Key | Label in UI | Group | Unlocks |
|---|---|---|---|
| `patients.view` | See patients | Patients | `patients` read; Patients tab |
| `patients.edit` | Add and edit patients | Patients | `patients` write |
| `clinical.view` | See clinical records | Clinical | dental/radiology/homeopathy/tooth chart/procedure/treatment plan read; `doctors/{id}/patients/**` files read |
| `clinical.edit` | Write clinical records | Clinical | the same, write |
| `schedule` | Appointments, queue and home visits | Front desk | `appointments`, `visitations`, `walk_in_queue` |
| `billing` | Invoices and payments | Money | `invoices`, `pending_payments`; create `revenue_entries` |
| `revenue` | Revenue and reports | Money | `revenue_entries` read; revenue charts and totals |
| `inventory` | Inventory and sterilization | Stock | `medicines`, `stock_transactions`, `sterilization_log_entries` |
| `messaging` | WhatsApp and reminders | Front desk | WhatsApp logs and connection |
| `ai` | AI assistant and voice scribe | Clinical | AI and scribe tabs |
| `team` | Manage team and roles | Admin | Team screen, invites, activity log |
| `settings` | Clinic settings and letterhead | Admin | clinic name, branding files, procedure catalog |

Implied permissions (always added on save): `patients.edit` → `patients.view`;
`clinical.view` → `patients.view`; `clinical.edit` → `clinical.view` +
`patients.view`.

Owner and the `admin` role have every permission without listing them.

### Built-in roles (seeded into every new clinic)

| roleId | Name | Kind | Permissions | Editable |
|---|---|---|---|---|
| `admin` | Admin | either | everything | No |
| `doctor` | Doctor | doctor | patients.*, clinical.*, schedule, billing, messaging, ai | Yes |
| `receptionist` | Receptionist | staff | patients.view, patients.edit, schedule, billing, messaging | Yes |
| `assistant` | Assistant / Nurse | staff | patients.view, clinical.view, schedule, inventory | Yes |
| `accountant` | Accountant | staff | patients.view, billing, revenue | Yes |

Custom roles get an auto id. Max 30 roles per clinic.
Escalation rule: only the owner or an admin may give someone the `admin`
role, or a role that contains `team`, or create/edit a role containing `team`.

### Firestore documents

```
clinics/{clinicId}                     // clinicId == owner uid
  name, specialty, ownerUid, createdAt,
  seats: {doctor: 5, staff: 10},
  enabledModules, status, expiresDate, subscriptionPlan   // mirrored from users/{ownerUid} by a trigger
clinics/{clinicId}/members/{uid}
  name, phone, email, kind: 'doctor'|'staff', roleId, roleName,
  perms: [..],            // copied from the role by the function, normalized
  active: true|false, isOwner, specialty, qualification, registrationNo,
  modules: [..] | missing,   // this person's own features (module keys); missing = all
  dentalFeatures: [..] | missing,  // a joining dentist's starting dental features (copied to their profile once)
  joinedAt, invitedBy, removedAt?, removedBy?
clinics/{clinicId}/roles/{roleId}
  name, kind, perms: [..], isSystem, updatedAt
clinics/{clinicId}/invites/{inviteId}
  clinicId, clinicName, name, phone (E.164) | email (lowercase), kind, roleId,
  roleName, specialty, modules?, dentalFeatures?, status: 'pending'|'accepted'|'cancelled',
  invitedBy, invitedByName, createdAt, expiresAt (createdAt + 7 days), acceptedBy?
users/{uid}
  + clinicId      // active clinic, written by the function only
  + memberKind    // 'owner'|'doctor'|'staff', written by the function only
```

Members, roles and invites are written **only** by the `clinicTeam` Cloud
Function. A member may edit only their own `name`, `phone`,
`qualification`, `registrationNo`, `modules` on their member doc.

### Sign-in flow

1. Sign in (Google or phone OTP), as today.
2. `ClinicSession.load(uid)` reads `users/{uid}.clinicId` (missing → `uid`)
   and the member doc → `ClinicAccess`. Then the encryption key, local
   database and sync start for that tenant.
3. If the profile needs onboarding (no specialty) and isn't a joined member:
   ask the function for pending invites. Any → **Join clinic** screen.
   None → the existing onboarding (creates a solo clinic as today).
4. The Team screen calls `ensureClinic` the first time an owner opens it, so
   existing doctors get their `clinics/{uid}` doc lazily.

### Phases

| Phase | Tasks | Ends with |
|---|---|---|
| 0 Dental features | D1–D5 | done |
| 1 Model | T1 | done |
| 2 Security rules | T2–T4 | done |
| 3 Cloud Function | T5–T6 | done |
| 4 Tenant switch in the app | T7–T9 | done |
| 5 Join a clinic | T10–T11 | done |
| 6 Team and Roles screens | T12–T14 | done |
| 7 Permission-aware app | T15–T17 | done |
| 8 Several doctors in the schedule | T18–T20 | T20 done; **GATE 5** after T18–T19 |
| 9 Removal and activity log | T21–T22 | done |

---

## Phase 8 — Several doctors in the schedule

### Task T18 — Who the patient sees

Add `attendingDoctorUid` and `createdByUid` (strings, default `''`) to the
SQLite tables `visits`, `walk_in_queue`, `revenue_entries`,
`pending_payments`, and to the Firestore `invoices` writes. Follow exactly
how `doctorId` is added in the column-migration maps in
`local_database_service.dart` (around line 943) and carried both ways in
`firestore_sync_service.dart`. New records: `createdByUid` = user uid;
`attendingDoctorUid` = the chosen doctor (T19), or the user's uid when the
user is a doctor and there's no picker.

### Task T19 — Doctor picker and filters

- `clinicDoctorsProvider` in `lib/core/clinic/clinic_doctors_provider.dart`:
  active members with `kind == doctor`, from `clinics/{tenantId}/members`;
  when the clinic doc doesn't exist, a single entry for the signed-in doctor.
- Appointment and queue forms: a "Doctor" dropdown, shown only when there is
  more than one doctor. Default: yourself if you are a doctor, else the
  first doctor.
- Appointments (every view) and Queue: a doctor filter ("All doctors",
  then each doctor), shown only with more than one doctor, in the same spot
  in every view. Doctors default to themselves; staff default to All.
  Records with an empty `attendingDoctorUid` count as the owner's.
- Revenue (`revenue` permission): a "By doctor" breakdown when there is more
  than one doctor.

## After all tasks (the user or Claude — never Antigravity)

**Deployed 2026-10-07:** rules, indexes (incl. `access_logs`), Storage
rules, `clinicTeam`, `mirrorPlanToClinic`, and the clinic-aware
`getImagingView`, `createAppointment`, `getAvailability`,
`cancelAppointment`. Nothing in T18–T19 needs a deploy.
Steps below were done on 2026-10-07 for the rules, indexes and `clinicTeam`.

1. Deploy rules and indexes first (safe for current users, owner = clinic of one):
   `firebase deploy --only firestore:rules,firestore:indexes,storage --project svayatta-crudoc-dev`.
   Storage rules that call `firestore.get` need the Storage service agent
   allowed to read Firestore: accept the prompt the CLI or console shows.
2. Functions: `firebase deploy --only functions:clinicTeam,functions:mirrorPlanToClinic,functions:createAppointment,functions:getAvailability,functions:cancelAppointment,functions:getImagingView`
   with `FUNCTIONS_DISCOVERY_TIMEOUT=90`. Watch for the known blockers in the
   main codebase (missing secrets, live functions without source).
3. `clinicTeam` is a v2 callable, so the org policy blocks it with 403 like
   the others: the user runs
   `gcloud run services update clinicteam --no-invoker-iam-check --region asia-south1 --project svayatta-crudoc-dev`.
4. Release the app after Phase 7 at the earliest (staff must never get a
   build that shows tabs their rules deny).

## Later (not in this brief)

- Clinic switcher for doctors in several clinics (data model already allows it).
- Quick user switch with a PIN on a shared front-desk PC.
- Per-doctor letterhead and prescriptions printed by staff.
- "Own patients only" option for doctors (C1).
- Per-doctor queue token numbers.
- Campaigns owned by the clinic instead of the owner's profile.
- Super Admin: list clinics, set seats per plan, count staff separately
  (`users.memberKind`).
- Two-step sign-in for owners and admins (India compliance audit item).
- Remove the "not built yet" dental pages once each feature's screens are finished.
