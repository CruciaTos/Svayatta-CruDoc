# Patients redesign: implementation plan

Branch `feat/patients-redesign`, from `feat/dashboard-redesign` (`8389dcf`). Spec: `PROMPT.md`, `html/`, `screens/`. Rules: `.claude/rules/crudoc-ui.md` and `design/dashboard-redesign/DESIGN_SPEC.md`.

This is a UI/UX pass. Screens read existing providers only. Nothing changes in models, schemas or sync. An element with no data behind it is hidden and recorded as a GAP.

## Architecture

- **One source for every number.** `PatientsBuilder.summarize(patient, visits, now)` (pure) produces a `PatientSummary`. It is built from `patientsStreamProvider` and `allVisitsProvider`, with the dashboard clock `dashboardNowProvider`.
  - The list rows, preview pane, facts strip and visits card all read the same summary.
  - This fixes the old contradictions. "Last session" used to be the newest visit of any status, including future and cancelled ones, and "Just now" was shown for future dates.
- **List state lives in `patientsListControllerProvider`** (a Notifier that survives navigation). It holds the filter, sort, query, selection, pane open/closed per filter, scroll offset, page limit and the open details id.
  - Details replace the list inside the Patients tab; no route is pushed. Back clears `detailsId`, and the list rebuilds from the saved state.
- **`patientsListViewProvider`** turns that state into view data: counts, rows, groups, selected row and summary strips.
- **Floating chatbot button:** hidden on the Patients tab through the shell condition that already hides it on the dashboard.

## Files

**Theme and shared (extended, no second set)**
- `lib/core/theme/cru_colors.dart`: adds `paneShadow` (the HTML's shadow-2).
- `lib/core/theme/cru_tokens.dart`: new radii (strip 16, panel 14, largeTile 15, thinBar 3), sizes (rows 64/62, pane 420, pills, tiles, date tile, stepper) and breakpoints `splitPane` 1200 and `phone` 800.
- `lib/core/theme/cru_type.dart`: adds `title2`, `amount`, `input`, `note`, `lead`, `chip`, `step`, `dateMonth` and `dateDay`.
- `lib/shared/widgets/cru/cru_icons.dart`: adds whatsapp, close, arrowUpRight, importExport, download and sparkleSingle.
- `lib/shared/widgets/cru/cru_button.dart`:
  - `CruButtonKind.outline`
  - `CruCapsuleButton` gains `kind` (inset/tinted/surface), `icon`, `height` and `large`
  - new `CruSquareButton`
  - `CruLink.leading`
- `lib/shared/widgets/cru/cru_extras.dart` (new): `CruProgressBar`, `CruInfoPill` and `CruDateTile`.
- `lib/features/dashboard/presentation/widgets/glance_card.dart`: the cell pieces become public (`GlanceStrip`, `GlanceLabel`, `GlanceMetric`, `GlanceCaption`, `GlanceCellSkeleton`) so the facts strip reuses them.

**Patients domain and data**
- `lib/features/patients/domain/patients_models.dart`: `PatientFilter`, `PatientSort`, `VisitRowStatus`, `PatientSummary`, `PatientGroup` and the strip data.
- `lib/features/patients/domain/patients_builder.dart`: `PatientsBuilder` (summaries, filters, counts, search, sort, grouping, strips) and `PatientFormat`.
- `lib/features/patients/data/providers/patients_list_providers.dart`: `patientSummariesProvider`, `patientSummaryProvider(id)`, `patientsListControllerProvider` and `patientsListViewProvider`.

**Patients UI (new)**
- `lib/features/patients/presentation/patients_screen.dart`: the Patients tab. It shows the list, or details when `detailsId` is set.
- `lib/features/patients/presentation/widgets/list/`: header, search and sort, filter chips, table, compact list, group header, summary strip, preview pane, narrow sheet, first-week panel, skeleton rows and the reminders sheet.
- `lib/features/patients/presentation/patient_details_view.dart` and `widgets/details/`: top bar, identity header, facts strip, treatment plan and stepper, payments block, clinical notes, visits card and medical history.
- `lib/features/patients/presentation/patient_actions.dart`: Call (`tel:`), WhatsApp (`WhatsAppTemplateService.buildDirectWhatsAppUrl`), New visit (`showScheduleVisitSheet`), Edit (`showDesktopAddEditPatientDialog`), Record payment and Update visit (`showSessionDetailsSheet`).

**Wiring and removal**
- `lib/features/shell/presentation/desktop_shell.dart`:
  - tab 1 now uses `PatientsScreen`
  - the chatbot button is hidden on Patients
- `lib/features/dashboard/presentation/dashboard_actions.dart`: `openPatient` pushes the new details view.
- Delete `desktop_patient_records_screen.dart` and `desktop_patient_details_screen.dart` once nothing references them.
- Mobile `patient_details.dart` and dental details: "Last session" now uses the latest completed visit that has started, fixing the same contradiction.

**Tests:** `test/patients/`, with builder unit tests, layout tests at 1440/1280/1024/800 and goldens at 1440 px for every screen in `screens/`, using fake providers and bundled Geist.

## Element → data source

| Element | Source | Notes |
|---|---|---|
| Header "N patients · N new this month" | `patientsStreamProvider` (count, `createdAt` in this month) | |
| Import / Export, "Import from Excel", "Download the template" | **GAP** | No import or export code and no CSV/XLSX package. Buttons stay and say it isn't available yet. |
| Add patient | `showDesktopAddEditPatientDialog` → `PatientRepository.createPatient` | |
| Search (name, phone ignoring spaces, patient ID, condition) | `PatientsBuilder.matchesQuery` using `core/utils/search_normalisation.dart` | ID matches the UUID prefix (≥ 4 characters) |
| Chip All | patients count | |
| Chip Last 7 days | last completed visit within 7 days (`allVisitsProvider`) | |
| Chip Follow-up overdue | booked visit whose time passed, not recorded, nothing booked since | `Visit.followUpDate` is a **GAP** (see the dashboard report); this uses real bookings instead |
| Chip Balance due | `Patient.packageBalance > 0` | |
| Chip In treatment | ≥ 1 completed visit and a visit booked ahead | There's no treatment-plan status for every specialty |
| Chip New this month | `Patient.createdAt` | |
| Row monogram, name | `Patient.fullName` | |
| Row patient ID ("P-0418") | **GAP** | IDs are UUIDs with no sequential number. Hidden; the row shows the phone only. |
| Row phone (5+5) | `Patient.phone` | |
| Age · sex | `Patient.age`, `Patient.gender` | |
| Condition | `Patient.diagnosis` | |
| Treatment "session x of y" | **GAP** (no per-patient plan with a total) | Shows the latest completed visit's `treatmentType` and "N visits" instead |
| Last visit date and time | latest completed started `Visit` | |
| Next visit / Overdue since | earliest scheduled `Visit` ahead; otherwise the unrecorded past booking | |
| Balance | `Patient.packageBalance` | |
| Grouping (Seen today / Past 7 days / Earlier) | last completed visit | |
| Showing N of M, load more | in-memory paging of the summaries | |
| Balance strip "₹X outstanding · N patients" | sum of `packageBalance` | "oldest due D days" is a **GAP**: no due date on the balance |
| Follow-up strip "N patients · longest overdue D days" | overdue bookings | |
| Send reminders / Message all | a sheet with per-patient WhatsApp links (`buildDirectWhatsAppUrl`) | no bulk sending without review |
| Compact row right side | last visit / balance / days overdue | balance "since <date>" is a **GAP** |
| Pane allergy chip | homeopathy `HomeopathyCaseSheet.medicalHistory.allergies` (`homeopathyCaseSheetProvider`) | Otherwise **GAP** (`Patient.allergies`). Hidden, because "No known allergies" would be a claim nobody checked. |
| Pane phone chip, Call, WhatsApp | `Patient.phone`, `url_launcher` | |
| Pane New visit | `showScheduleVisitSheet` | |
| Pane Balance due amount | `packageBalance` | |
| Pane "₹paid of ₹total paid" and progress bar | **GAP** | No package total and no ledger linking payments to a balance |
| Pane Record payment | a dialog → `PatientRepository.updatePatient({'packageBalance': …})` + `RevenueRepository.createRevenueEntry` | |
| Pane Send a payment reminder | WhatsApp link with a reminder text | |
| Pane Paid in full · ₹total | "No balance due" with a green check | the total paid is a **GAP** |
| Pane Follow-up overdue block + Book follow-up | overdue booking; `showScheduleVisitSheet` | |
| Pane Treatment: plan name and progress bar | **GAP** | Replaced by "Visits: N completed · Next: <date, time>" |
| Pane Last note | latest `Visit.therapistNotes` (time = visit time) | |
| Details top bar: Edit, "…", New visit | edit dialog; menu (dental chart / case sheet when the specialty has one, delete); schedule sheet | |
| Details "Patient since" | `Patient.createdAt` | |
| Facts: treatment ring "x of y sessions done" | **GAP** for the total | Dentists with plan line items get a ring for items done (invoiced) of total; everyone else sees "N visits done" with no ring |
| Facts: Next visit, Last visit | summary | |
| Facts: Balance due "of ₹total package" | balance **amount only**; "of ₹total package" is a **GAP** | |
| Treatment plan card and stepper | dentists: `patientTreatmentPlanProvider` (line items: invoiced = done, the first accepted/proposed = next, declined hidden) | Plan name, start date, step dates and "booked" are **GAPs**. Card hidden for other specialties. |
| Package block | `packageBalance` | paid and total are **GAPs**; the block shows the balance and Record payment |
| Clinical notes list | `Visit.therapistNotes` per visit, newest first | |
| Scribe tag "Dictated with Scribe · reviewed by <doctor>" | a confirmed `ConsultationNote` for that visit (`notesForVisitProvider`) + `doctorIdentityProvider` | |
| Note composer | today's visit → `VisitRepository.updateVisit(id, {'therapistNotes': …})`; no visit today → `PatientRepository.updateDoctorsNote` | |
| Scribe mic | opens Scribe for the patient (existing Scribe screens) | |
| Visits card: Upcoming / Past, status, Update | summary visits; `PatientsBuilder.visitStatus`; `showSessionDetailsSheet` | |
| Medical history: Condition | `Patient.diagnosis` | |
| Medical history: Allergies, Medications, Systemic | homeopathy case sheet (allergies, pastMedications, pastIllnesses) | **GAP** for other specialties |
| Medical history: Tobacco, Last X-ray | **GAP** | |
| "Recorded at registration · updated <date>" | "Updated <date>" from the case sheet / `Patient.updatedAt` | "Recorded at registration" is a **GAP** |

## Phases (per the user: write everything, verify once at the end)

1. This plan.
2. Shared pieces (the theme and shared-widget additions above).
3. Patients list: table, filters, search, sort, grouping.
4. Split mode, preview pane, work-through filters, keyboard, state restore, narrow sheet.
5. First-week state.
6. Patient details.
7. Goldens at 1440 px against `screens/`.

After that: `flutter analyze` and the tests, then fixes, then one commit per phase.
