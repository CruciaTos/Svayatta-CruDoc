# CruDoc — Dentist Specialization — 0.3 & 0.4 Data Contract

Repo re-cloned and read directly for this session: `CruciaTos/Svayatta-CruDoc` @ `bf9768d` (2026-09-03). Packets 0.1, 0.2, and 0.5 were **not** formally run this session — the findings below come from direct inspection of the analogues needed to write a grounded 0.3/0.4, not from a full 0.1 sweep. Treat 0.1/0.2/0.5 as still open (see "What's still open" at the bottom) even though this doc leans on their groundwork.

## Analogues this contract is built from

- **`lib/features/homeopathy/`** — the only other specialty extension that actually exists. Its case-sheet model, repository, and local service define the working pattern: plain hand-written Dart models (no freezed/json_serializable), `doctorId`-scoped top-level Firestore collections, `uuid` v4 client-generated IDs, `FieldCipher` field-level encryption for narrative text only.
- **`lib/core/services/local_database_service.dart`** — every existing SQLite table (`patients`, `visits`, `revenue_entries`, `medicines`, `stock_transactions`, `homeopathy_case_sheets`, …). This is the ground truth for column typing, defaults, and the `syncStatus`/`pendingDelete`/`lastSyncedAt` sync triad.
- **`lib/core/services/field_cipher.dart`** — the encryption boundary: ids/timestamps/booleans/amounts/`doctorId` stay plaintext (queryable); free-text PHI gets AES-GCM'd client-side.
- **`lib/features/inventory/data/models/medicine_model.dart`** — closest analogue for doctor-owned, non-patient-linked reference data (used for the sterilization log and the procedure catalog).
- **`lib/features/revenue/data/models/invoice_model.dart`** — checked because §2 says the treatment plan should "feed the existing invoice screen." It doesn't support line items (see 0.3(e)).
- **`firestore.rules`** and **`firestore_super_admin.rules`** — checked because 0.4 requires documenting isolation, and what I found changes the risk picture (see the flag at the bottom of 0.4).
- No `clinicId` field or concept exists anywhere in the codebase — not in any Dart model, not in either rules file. Confirmed by grep across `lib/`.
- No dental/tooth code exists anywhere yet. Confirmed by grep — this is genuinely greenfield.

---

## 0.3 — Dental data contract

### Shared conventions (apply to all five record types below)

| Concern | Decision | Why |
|---|---|---|
| `id` | `String`, UUID v4 via the `uuid` package, generated client-side, used as **both** the SQLite primary key and the Firestore document ID | Matches `patients`, `medicines`, `homeopathy_case_sheets` — never a Firestore auto-ID, anywhere in this codebase |
| `doctorId` | `String`, required, set from `FirebaseAuth.instance.currentUser!.uid` at save time, never client-editable | Sole tenant/ownership key. **No `clinicId` field** — see decision below |
| `patientId` | `String`, required only on patient-linked entries | Present on tooth chart, procedure log, treatment-plan line items. Absent on the catalog and the sterilization log (both clinic-level) |
| `createdAt` / `updatedAt` | `DateTime`, non-null | `INTEGER` (`millisecondsSinceEpoch`) in SQLite; converted to Firestore `Timestamp` at the sync boundary (matches `FirestoreSyncService`, not the raw-millis write `homeopathy_repository.dart` does directly — that's a pre-existing inconsistency, not one to copy forward) |
| Soft delete | `isDeleted: bool`, default `false` | These are event/record-style entries, closer to `visits`/`revenue_entries` (which use `isDeleted`) than to `patients` (which uses `isArchived` for a different, longer-lived-entity workflow) |
| Sync triad | `syncStatus: String` (`'synced'\|'pending'`, default `'synced'`), `pendingDelete: bool` (default `false`), `lastSyncedAt: DateTime?` | Present on every synced table in the app without exception. Repository-owned, never UI-editable |

### (a) Dental procedure catalog entry
*Clinic-level, doctor-owned reference data. Analogue: `MedicineModel`.*

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| id | String | yes | — | |
| doctorId | String | yes | — | |
| code | String | yes | — | short stable code (`SCALE`, `RCT`, `EXT`) — procedure log entries reference this, not the display name |
| name | String | yes | — | e.g. "Root Canal Treatment" |
| category | String | yes | `'general'` | free string like `MedicineModel.category`, not an enum — clinics add local categories without a code change |
| defaultPrice | double? | no | null | nullable — some clinics quote per-case |
| defaultDurationMinutes | int? | no | null | optional; feeds AI-5.2 chair-time estimation later, not used now |
| requiresToothSelection | bool | yes | true | drives whether the log UI prompts for tooth numbers (false for e.g. "Consultation") |
| isActive | bool | yes | true | soft-disable a retired/renamed procedure without deleting it |
| isDeleted / createdAt / updatedAt / sync triad | — | — | — | shared conventions above |

Encryption: **none.** Clinic configuration, not PHI.

### (b) Tooth chart entry
*Patient-linked. One row per (patient, tooth, event) — the chart is a chronological log, not a mutable per-tooth state document. "Current state" is a derived view (latest entry per tooth), computed at query time, so there's no second source of truth to keep in sync. Mirrors how `stock_transactions` logs events against a `medicineId` instead of mutating one row per medicine.*

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| id | String | yes | — | |
| doctorId | String | yes | — | |
| patientId | String | yes | — | |
| toothNumber | String | yes | — | **string, not int** — Palmer notation uses quadrant symbols; an int field would break notation portability |
| notationSystem | String | yes | `'fdi'` | `'fdi'\|'universal'\|'palmer'` — stamped per entry, not just per clinic (see notation decision below) |
| surface | String? | no | null | e.g. `mesial`, `distal`, `occlusal` |
| condition | String? | no | null | e.g. `caries`, `fractured`, `missing` — nullable, an entry can be treatment-only |
| treatment | String? | no | null | e.g. `filling`, `extraction` — free text, loosely linked to catalog `code` when applicable |
| procedureLogId | String? | no | null | FK to (c) when this entry was generated from a logged procedure — keeps the two traceable without duplicating entry |
| notes | String | yes | `''` | **encrypted** |
| recordedAt | DateTime | yes | — | clinical event time, may differ from `createdAt` if backfilled |
| isDeleted / createdAt / updatedAt / sync triad | — | — | — | shared |

Encryption: `notes` only. `condition`/`treatment`/`surface` stay plaintext — short, low-cardinality clinical values the UI needs to query/filter on (e.g. "all caries entries"), same reasoning `field_cipher.dart` itself documents.

### (c) Procedure log entry
*Patient-linked, one row per procedure performed. Analogue: `stock_transactions` (linked to a `medicineId` + optional `visitId`).*

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| id | String | yes | — | |
| doctorId | String | yes | — | |
| patientId | String | yes | — | |
| visitId | String? | no | null | nullable — matches `revenue_entries.visitId` / `stock_transactions.linkedVisitId`, both nullable |
| procedureCatalogId | String? | no | null | FK to (a); nullable so a one-off procedure not in the catalog can still be logged |
| procedureName | String | yes | — | denormalized copy of the catalog name at log time — renaming/retiring a catalog entry later never rewrites history, same denormalization `InvoiceModel.patientName` already does |
| toothNumbers | List\<String\> | yes | `[]` | zero, one, or many, per §2; empty = whole-mouth/clinic-level procedure |
| notationSystem | String | yes | `'fdi'` | same as (b) |
| status | String | yes | `'completed'` | `'planned'\|'inProgress'\|'completed'` — exists from day one because AI-3 (documentation QA, later phase) checks things like "a completed procedure has no linked visit," so the field can't be bolted on retroactively |
| notes | String | yes | `''` | **encrypted** |
| materials | String? | no | null | e.g. composite shade, anesthetic used — **encrypted** |
| performedAt | DateTime | yes | — | |
| isDeleted / createdAt / updatedAt / sync triad | — | — | — | shared |

Encryption: `notes`, `materials`. Everything else stays plaintext for filtering/display.

### (d) Sterilization log entry
*Clinic-level, explicitly NOT patient-linked per plan §2. Analogue: `medicines`/`stock_transactions` — doctor-owned, no patient reference at all.*

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| id | String | yes | — | |
| doctorId | String | yes | — | **sole scope key — no `patientId` field on this model**, matching the plan's own instruction |
| cycleDate | DateTime | yes | — | |
| operatorName | String | yes | — | plaintext — needed for compliance-report filtering/printing without a decrypt step, and a staff name isn't patient PHI |
| loadDescription | String | yes | `''` | plaintext |
| result | String | yes | `'pass'` | `'pass'\|'fail'\|'incomplete'` |
| notes | String | yes | `''` | plaintext — not patient PHI, and compliance tooling needs to read it directly |
| isDeleted / createdAt / updatedAt / sync triad | — | — | — | shared |

Encryption: **none.** Clinic-operational/compliance data, not the "patient name, phone, diagnosis, notes" `FieldCipher` exists for.

### (e) Future treatment-plan line item (Phase 2 preview — contract only)

**Constraint found while checking this:** `InvoiceModel` has a single flat `service: String` + `amount: double` field — no line-items array exists anywhere in the app today. So "feeding the existing invoice screen instead of a new one" (§2) can't mean an automatic structured hand-off yet. Phase 2 will have to choose between (i) one `InvoiceModel` per line, or (ii) one invoice with a concatenated `service` summary and a totalled `amount`. This contract is written invoice-agnostic so that decision doesn't force a model rewrite later.

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| id | String | yes | — | |
| doctorId | String | yes | — | |
| patientId | String | yes | — | |
| treatmentPlanId | String | yes | — | groups line items into one quote; the plan header itself is Phase 2 scope, not 0.3 |
| procedureCatalogId | String? | no | null | same nullable-FK pattern as (c) |
| procedureName | String | yes | — | denormalized |
| toothNumbers | List\<String\> | yes | `[]` | |
| estimatedPrice | double | yes | `0` | never AI-sourced — AI-B's own guardrail: "prices must come from the clinic catalog, never from the model" |
| sequence | int | yes | `0` | display/treatment order |
| status | String | yes | `'proposed'` | `'proposed'\|'accepted'\|'declined'\|'invoiced'` |
| isDeleted / createdAt / updatedAt / sync triad | — | — | — | shared |

Encryption: none at the line-item level. If Phase 2 adds a plan-level clinical-rationale free-text field, it should follow (b)/(c) and get encrypted.

### Tooth numbering decision

**Recommend FDI (ISO 3950, two-digit) as the default**, stamped per-entry via `notationSystem` rather than only configured once per clinic — a clinic-level default is still fine for pre-filling the input UI, but stamping each row keeps historical entries correctly interpretable even if a clinic's configured default changes later. Rationale for FDI over Universal Numbering: CruDoc's existing specialties and demo data are India-oriented, and FDI (not the US/Canada-centric Universal system) is what's taught and used in Indian dental practice. **This is a product call, not a purely technical one — flagging it for you to confirm rather than assuming it silently.**

### Direct answers to 0.3's open decision prompts
- **doctorId / clinicId / patientId representation:** `doctorId` is the only tenant key, on every record type. No `clinicId` — none exists in this codebase, so "clinic-level" (catalog, sterilization log) means "scoped to `doctorId`, no `patientId`," exactly like `medicines`/`stock_transactions`. `patientId` appears only where the plan says a record is patient-linked.
- **Soft deletion:** `isDeleted: bool`, no separate `deletedAt` tombstone — the codebase doesn't use tombstone timestamps anywhere observed; `updatedAt` already captures delete-time under the existing pattern.
- **Audit timestamps:** `createdAt`/`updatedAt` DateTime, SQLite-int / Firestore-Timestamp dual representation, as used everywhere else.

---

## 0.4 — Firestore collection paths and indexes

**Check taken:** no `firebase.json` exists anywhere in the repo (confirmed — only `.firebaserc` with the project id), and no emulator config was found. That means the packet's "otherwise" branch applies: this is a manual rules/query review, not an emulator index validation run.

### Collection paths
Flat, top-level, `doctorId`-scoped — matching `patients`, `homeopathy_case_sheets`, `medicines`, `stock_transactions` (the pattern the app's repositories actually use), **not** the nested `/users/{uid}/patients/...` shape in `firestore_super_admin.rules` (see the flag below — that shape isn't what any repository in `lib/` writes to).

- `dental_procedure_catalog/{id}`
- `tooth_chart_entries/{id}`
- `procedure_log_entries/{id}`
- `sterilization_log_entries/{id}`
- `treatment_plan_line_items/{id}` *(Phase 2)*

### Query shapes and required composite indexes
Firestore needs a composite index whenever a query combines an equality filter with an `orderBy` on a *different* field (or uses multiple equality filters) — every shape below does that, so every one needs an explicit composite index; none of these are covered by Firestore's automatic single-field indexing.

| # | Query | Composite index |
|---|---|---|
| 1 | Catalog list for a doctor, active only, alphabetical | `doctorId ASC, isActive ASC, name ASC` |
| 2 | Tooth chart history for one patient, newest first | `doctorId ASC, patientId ASC, recordedAt DESC` |
| 3 | Tooth chart filtered to one tooth (per-tooth history, §2) | `doctorId ASC, patientId ASC, toothNumber ASC, recordedAt DESC` |
| 4 | Procedure log for one patient, newest first | `doctorId ASC, patientId ASC, performedAt DESC` |
| 5 | Sterilization log, clinic-wide, newest first | `doctorId ASC, cycleDate DESC` |
| 6 | Treatment-plan line items for one plan, in order | `doctorId ASC, treatmentPlanId ASC, sequence ASC` |

No other composite indexes are defined — matching the packet's "only for queries that are actually needed."

### Tenant/doctor isolation — documented rule shape
For every collection above:
```
allow read, update, delete: if request.auth != null
  && request.auth.uid == resource.data.doctorId;
allow create: if request.auth != null
  && request.auth.uid == request.resource.data.doctorId;
```
Same doctor-ownership pattern as the one collection in `firestore_super_admin.rules` that already matches this flat, doctorId-scoped shape (`medical_documents`). Patient-linked collections add no further check beyond `doctorId` — `patientId` isn't independently cross-validated against the patient's own `doctorId` anywhere in the existing ruleset either, so this isn't a new gap, just an existing limitation carried forward. This is documentation for 0.5 to turn into actual test cases — no rules file is being written or deployed by this packet.

### 🚩 Critical flag — surfaced by this review, blocks Gate A, not resolvable by 0.3/0.4 alone
`firestore_super_admin.rules` — the file the plan's own §0 finding identifies as "looks like the real ruleset" — has **no match block for any of** `patients`, `visits`/`appointments`/`visitations`, `homeopathy_case_sheets`, `medicines`, `stock_transactions`, `revenue_entries`, or `pending_payments`. Its explicit matches model a different, nested `/users/{userId}/patients/{patientId}` shape that **no repository in `lib/` actually writes to** — every repository I checked (`patient_repository.dart`, `homeopathy_repository.dart`, `firestore_sync_service.dart`) uses flat top-level collections instead. The file's trailing clause is:
```
match /{document=**} { allow read, write: if false; }
```
**If this file is what's deployed, every existing doctor-facing collection in the app is already being denied** — not a dental-specific problem, the same practical symptom as the expired-default-rules finding in §0, just a different structural cause. Any new dental collection built on the flat top-level pattern above (chosen for consistency with the app's actual working code) will be denied too, unless a new match block using the isolation pattern above is added — and that same fix is needed for the app's *existing* collections regardless of dental work. This needs the Firebase console check 0.2 already calls for, plus a rules rewrite that matches what the code actually does — not something a documentation packet can close on its own.

---

## What's still open
- **0.1** (formal repository reconnaissance write-up) and **0.2** (confirm in the Firebase console which rules file is actually deployed) were not run as their own packets this session — do them properly before Gate A is considered closed. This doc leans on the same analogues 0.1 would have produced, but hasn't written the deliverable 0.1 itself asks for.
- **0.5** (rules test cases) is unstarted — the isolation rule shape above is the input it needs.
- The rules/collection-path mismatch flagged above is the most load-bearing open item — it affects the *existing* app, not just dental, and should probably get raised before more Phase 0 packets land on top of it.
- `firestore.indexes.json` doesn't exist in the repo yet; the six composite indexes above aren't wired into any deployment config. That's a 0.2-adjacent follow-up, not something this doc creates.
- Next packet per the plan's own dependency map: **0.5 — Rules test cases**, or, if Soham wants to defer that, **0.6 — Dart model: dental procedure catalog** (the catalog has no rules-sensitive fields, so it's the lowest-risk packet to start coding against this contract).
