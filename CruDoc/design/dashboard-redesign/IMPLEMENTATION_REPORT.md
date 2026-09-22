# Dashboard redesign: implementation report

Branch `feat/dashboard-redesign`, based on `main` at `9b9e75a`. Spec: `DESIGN_SPEC.md`. Plan: `IMPLEMENTATION_PLAN.md`.

## 1. What was built

**Design system (phases 1–2)**
- `lib/core/theme/`: `CruColors` ThemeExtension with Day, Evening and on-ink variants (every value from spec §2.2), plus `CruType` (the Geist type scale with tabular figures), `CruRadius`, `CruSpace`, `CruSize`, `CruBreakpoint`, `CruMotion`, and `CruTheme.day()` / `.evening()`. The app uses the Day theme.
- Geist 400/500/600/700 are bundled from `assets/fonts/Geist/` and registered in `pubspec.yaml`. Nothing is fetched at runtime.
- `lib/shared/widgets/cru/` holds the shared widgets:
  - card, ink card, separator;
  - buttons (primary, secondary, inset, tinted), capsule button, icon button, link;
  - segmented control, status dot, monogram, chip, pill, icon tile, progress ring, done badge, keycap;
  - `CruPressable`: hover fill, 0.98 press scale, Enter/Space, focus ring, reduced motion;
  - `CruIcon`: the reference's stroke icons painted from their SVG paths, so they need no icon font and render the same in goldens.
- No hard-coded colours, font sizes or radii in the new widgets. Everything comes from the tokens.

**Dashboard (phases 3–4)**
- `lib/features/dashboard/domain/dashboard_builder.dart` is a pure function. It turns repository data (today's queue, visits, patients, revenue, medicines) and `now` into view models, and has 72 unit tests.
- `dashboard_providers.dart` combines only existing providers. Widgets never touch SQLite or Firestore; profile and plan data also go through providers.
- **Header:** date line, time-aware greeting, search ("Search patients or ask CruDoc"; patient matches open the record, anything else opens the assistant with the question pre-filled), Add patient, New visit (queue check-in).
- **At a glance:** Seen today (ring), Waiting now with average wait, and Collected today compared with the same weekday last week.
- **Up next:** earliest waiting token, in the same order `QueueRepository.callNext` uses. Shows the token, wait pill, name, "23 y · Female · Returning · Last visit 14 Aug, seasonal allergy", and reason for visit. Buttons: Start consultation (calls the token and starts the consultation), View history, and a "…" menu (skip, cancel token, open queue). When nobody is waiting, a neutral "No one waiting · Next booking at …" card replaces it.
- **Today's schedule:** today's visits and queue tokens in time order, with an All / Waiting / Done filter. Seen patients collapse into one row, and a later evening session collapses too. There's an Evening session divider and a "That's the last booking for today" row with Add a walk-in.
- **Needs attention** (Day): low-stock and expiring medicines. **Collections:** last 7 days, with today's bar in accent and closed days as a stub.
- **Wrap up the day** (Evening): patients left, AI Scribe drafts to review, tomorrow's bookings.
- **Sidebar:** Today / Patients / Clinic groups, a clinic switcher (replaces the specialty card), the waiting count on Queue, the plan line with Upgrade, and an account menu (appearance, settings, help, collapse, log out). It collapses to icons below 960 px or with Ctrl+B.
- **Appearance:** Auto / Day / Evening, in the account menu and in Settings → Desktop Shell. Auto switches to Evening at 17:00 and back to Day at 05:00, animated.
- **Keyboard:** Ctrl/⌘ K focuses search. Enter starts the Up next consultation when nothing else has focus.
- **Removed from the dashboard:** the old dashboard file, including the static "AI Smart Insights" and the static "Pending Tasks" ("Interview", "Team Meeting"), the grey animated background, the floating chat button (the dashboard now uses Ask CruDoc), the mobile-app download card, and the specialty card.

**Visual check (phase 5):** golden tests render Day at 1440×1148 and Evening at 1440×988, at 1.5×, so each golden has the same pixel size as `screens/*.png`. After the fixes, every card's position and size matches `day.png` exactly. Evening is within 0.7 px, which is measurement noise. The only differences are heights removed on purpose by hidden gaps (§2). Regenerate with `flutter test --update-goldens --tags golden`.

## 2. Gaps: hidden elements and proposed model changes

Token numbers, the waiting status and wait times are **not** gaps: the queue feature already stores them (`QueueEntry.tokenNumber`, `status`, `checkedInAt`).

| Gap | Hidden on the dashboard | Proposed change: field, type, where it gets set |
|---|---|---|
| Follow-up dates | Glance "Follow-ups due · N overdue"; Needs attention and Wrap up "follow-ups overdue" rows | `Visit.followUpDate: DateTime?`. Set when a consultation is completed (from the doctor's reviewed Scribe note: `ConsultationNoteRepository.confirmNote` copies `note.followUpDate`), or when booking a follow-up. Add `VisitRepository.watchFollowUpsDue(from, to)`. Overdue means the date has passed and no later visit is booked. |
| Allergies | Allergy chip / "No known allergies" on Up next | `Patient.allergies: List<String>` (stored as JSON, like `diagnosis`) and `Patient.allergiesReviewedAt: DateTime?`, so that "no known allergies" means someone checked, not just an empty list. Set in the add/edit patient form and at check-in. |
| Pre-consultation vitals | The whole "Alerts and vitals" block: BP, Temp, SpO₂, Weight, "Recorded 11:41 by front desk" | New `VitalsRecord` { `patientId`, `queueEntryId?`, `visitId?`, `bpSystolic: int?`, `bpDiastolic: int?`, `temperatureF: double?`, `spo2: int?`, `pulse: int?`, `weightKg: double?`, `recordedAt: DateTime`, `recordedBy: String` }. Recorded by the front desk in `CheckInDialog`. `ConsultationNote.vitals` doesn't fit: it's captured during the consultation and has no SpO₂ or weight. |
| Lab results | Needs attention "HbA1c result · 7.9% (Review)" | New `LabResult` { `patientId`, `testName`, `value: double`, `unit`, `referenceRange?`, `resultAt: DateTime`, `reviewedAt: DateTime?` }. Set when a lab report is entered or uploaded (the medical-document OCR could fill it). The previous value comes from the prior result. |
| Payment method | Collections "UPI ₹x · Cash ₹y"; Wrap up "Match today's cash" | `RevenueEntry.paymentMethod: PaymentMethod?` (cash / upi / card / other; null for old entries). Set in `VisitRepository.recordPayment` and bill generation (Settings already has a default payment mode). |
| Visit purpose | Schedule "· Follow-up" label (shows Returning / New patient / Walk-in / Home visit instead, from real history) | `Visit.purpose: VisitPurpose?` (newConsult / followUp / review / procedure). Set when booking. |
| Arrival time for booked visits | Nothing hidden. Today a booked visit enters the queue as `waiting` with `checkedInAt` = appointment time, before the patient arrives, so the dashboard counts it as waiting only after its time has passed, measuring the wait from the appointment time. | `QueueEntry.arrivedAt: DateTime?`, set by a "Mark arrived" action on the Queue screen. |
| Clinic hours | Wrap up "· clinic closes at 8:00 PM"; the evening session divider shows the booked range ("5:30 to 6:10 PM") instead of session hours; Auto appearance uses the default 17:00 start and 05:00 end | `clinicHours` on the doctor profile (`users/{uid}`): { `morningStart`, `eveningStart`, `closeTime` }, set in Settings → Practice. |
| AI insights | The Insights card (the static "AI Smart Insights" were removed) | New `Insight` { `text`, `basis` (e.g. "From visit records"), `actionType`, `generatedAt`, `model`, `dismissedAt?` }, written by a scheduled job (e.g. a Cloud Function using Firebase AI) from real records. Violet is reserved for AI output, so the card stays hidden until insights come from that job, not from rule-based numbers. |
| End-of-day close | "Close the day" button | New `DayClose` { `date`, `closedAt`, `cashCounted: double?`, `notes` }, set by an end-of-day flow. |
| Prescriptions to sign | Replaced by **"N scribe notes to review"**: AI Scribe drafts (`ConsultationNoteStatus.draft`) for today's visits. That is real data, with the label changed to match it. | `Prescription.signedAt: DateTime?` if signing becomes a real step. |
| Stock run-out estimate | "about 4 days left" (shows "reorder level 20" instead) | No model change: a repository query for units dispensed in the last 30 days per medicine, from `StockTransactionModel`. |
| Mobile-app download link | Not added to the account menu. The old card had no link or action. | A download URL in Remote Config. |

The daily-dashboard fallbacks in `DoctorProfileHelper` ("Dr. Vinit Parab", "CruDoc Healthcare") are placeholder values. The dashboard uses new `tryFormatDoctorName` / `tryFormatClinicName` methods, which return null instead, and hides the name. Other screens keep the old behaviour.

## 3. Spec items not matched, and why

1. **The 800 px layout isn't reachable in the app.** `ResponsiveShell` switches to the mobile shell below 900 px. The desktop dashboard is built and tested at 800 px (sidebar collapsed, single column), but it only shows at that width if `kDesktopBreakpoint` is lowered. Lowering it would expose the other desktop screens at widths they weren't built for, so I left it.
2. **Evening is scoped to the shell and dashboard.** The other screens paint their own light panels and rely on default dark text, so an app-wide dark theme would make them unreadable. They get the Day palette through the theme; in the evening they sit, still in Day, inside the Evening shell.
3. **Contrast:** Day `greenText #248A3D` on white is 4.40:1, not the ≥ 4.5:1 the spec claims. I kept the spec value; a test pins it.
4. **Collected-today "down" colour:** §4 says redText when collections are down, but §1 reserves red for allergies and safety. I followed §1: down shows ↓ in the neutral label2 colour.
5. **Evening "Tomorrow" tile:** the mock-up uses teal, which §1 reserves for lab results, so it's neutral.
6. **Corners:** continuous (superellipse) corners, as the spec asks. The mock-ups use CSS circular corners, so the corner curves differ very slightly.
7. **Font rendering:** Flutter shapes Geist a hair wider than the browser. For example "New visit" is 1.3 px wider, so Add patient sits 1.3 px left. ⌘ isn't in Geist; on macOS the system font draws it.
8. **Start consultation:** the repository can only call the next token in its own order (`callNext`). If that isn't the Up next patient (for example, a booked visit with a lower token number that hasn't arrived), the dashboard opens the Queue screen with a message instead of calling someone else. Proposal: `QueueRepository.call(entryId)`.
9. **Enter to start:** Enter only starts the consultation when nothing else has focus. Otherwise it would take Enter away from every text field in the desktop shell.
10. **Kept beyond the spec:** the dental quick-actions row stays for dentists (below the schedule), because removing it would drop a working feature. The floating chat button stays on non-dashboard screens, where there's no Ask CruDoc search. Ask CruDoc pre-fills the question in the assistant; it doesn't send it.
11. **Not visually verified:** the other desktop screens now sit on the neutral canvas (the animated background is gone), with the same padding as before. They build and their tests pass, but I couldn't screenshot them: they need Firebase and SQLite at runtime.

## 4. Quality checks

- **`flutter analyze`:** 105 issues (0 errors, 11 warnings, 94 infos), all pre-existing. The baseline had 118 (0 errors, 13 warnings, 105 infos); the drop comes from deleting old code. There are **0 issues in the 48 files this branch adds or changes.**
- **New tests:** 110, all passing:
  - builder: 72;
  - layout at 1440 / 1280 / 1024 / 800 px, Day and Evening, with no overflow: 15;
  - shared widgets: 8;
  - theme tokens and contrast: 8;
  - appearance and wrap-up: 5;
  - goldens: 2.
- **Existing tests:** all tests outside the two dental files pass: 247 in total, new ones included. In `dental_phase2_catalog_and_procedure_test.dart` and `dental_phase3_4_5_test.dart`, five widget tests never complete, **on `main` too** (checked in a clean worktree of `9b9e75a`):
  - DentalProcedureCatalogScreen;
  - DentalProcedureLogSheet;
  - DentalTreatmentPlanSheet;
  - DentalSterilizationScreen;
  - DentalQuickActionsRow.

  On `main`, "treatment plan line items can be created, updated, and reordered" also failed; on this branch it passed. The hangs leave the shared test database in a bad state, so which neighbouring tests fail varies between runs. Run the suite with `flutter test --timeout 90s` so it finishes.

## 5. Commits

| Commit | What |
|---|---|
| `9b9e75a` | (on `main`, before branching) your uncommitted queue-screen work and lockfile |
| `ef606e1` | Phase 1: tokens, theme and Geist |
| `14bedab` | Phase 2: shared widgets |
| `055e43b` | Phase 3: dashboard on real data (Day); also contains the dental quick-actions row |
| `29aef0f` | Phase 4: Evening appearance, Wrap up, appearance setting |
| `3ac287e` | Phase 5: golden tests and visual fixes |
| `b88f622` | Phase 6: removed the old dashboard, the unused duplicate provider and the old specialty card |
| (next) | This report |
