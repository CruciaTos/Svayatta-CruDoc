# Brief for Antigravity: Physio workspace for every login

Repo: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc` (Flutter, package `doctor_management_app`).
Written 26 Nov 2026 by Claude after reading the code. All paths are from that folder. Line numbers are guides;
search for the quoted names.

## ▶ DO NOW

Tasks 1 to 7 in order, then "Checks", then the report. Nothing else.

## What Soham wants

Today the physiotherapy features show only on a Physiotherapy login (patient page > Clinical). Make them open for
**every specialty**, the way a dentist opens Charting: its own full screen with bottom tabs on the phone, a button
on the patient page, a swipe on the patient list, a sidebar page on PC. Use the app's own design language.

## Rules

- **How to work:** do all tasks first, run the Checks once at the end, run slow commands in the background and
  carry on. If a task cannot be done as written, skip that part, note it in the report, carry on.
- Follow `.claude/rules/crudoc-ui.md`: design tokens only, one filled button per region, red only for patient
  safety, violet only for AI, amber = waiting, green = done, motion 200-250 ms easeOutCubic, no new
  "same box" transitions, no sample data.
- **"Every login" means every specialty. It does not mean every role.** Everything physio stays behind
  `clinicCanProvider(ClinicPermission.clinicalView)`. Front desk and non-clinical owners must see none of it.
  Do not change `firestore.rules`, `storage.rules` or Cloud Functions.
- Phone or PC is decided by `usesDesktopLayout(context)` (`lib/core/layout/device_layout.dart`) for new screens.
- Reuse the existing cards in `lib/features/therapy/presentation/widgets/`. Do not rewrite them, their dialogs or
  their data.
- Do **not** change how a clinic works: leave every other `isPhysiotherapyProvider` use alone (queue, schedule,
  home visits, dashboard Up next, voice, queue tools, onboarding).
- Do not break the dentist or homeopath flows. Homeopaths keep Overview | Clinical (case sheet).
- No commits, no new test files or goldens. Do not run `flutter test` on the whole project (dental tests hang).

## Model to copy (the dentist flow)

| Dentist has | Where | Physio gets |
|---|---|---|
| `openCharting(context, patient)` + `ChartingScreen` | `lib/features/dental/presentation/desktop/charting_screen.dart` l.60-90 | `openPhysio` + `PhysioScreen` |
| `_ChartingBottomBar` (`MobileNavBar.selection`, labels) | same file, l.1670 | same bar, physio tabs |
| `SwipePages` between workspaces, header stays put | same file, l.957 | same |
| `ChartingPage` + `chartingPatientIdProvider` + patient search | `charting_page.dart` | `PhysioPage` |
| `_ChartingButton` in the PC patient header | `patient_details_view.dart` l.917 | `_PhysioButton` |
| "Open chart" in the phone patient bar | same file, `_PatientDetailsBottomBar` l.1002 | "Open physio" |
| Right swipe on a phone patient row | `lib/features/mobile/mobile_patients.dart` `_rightSwipe` l.198 | physio logins |
| Row chart button on PC patient table | `lib/features/patients/presentation/widgets/list/patients_table.dart` l.63-73 | physio logins |
| Sidebar "Charting" | `lib/features/shell/components/cru_sidebar.dart` l.178 | "Physio" |

---

## Task 1: the Physio screen

New file `lib/features/therapy/presentation/physio_screen.dart`.

```dart
enum PhysioTab { assess, progress, treat, records }

Future<void> openPhysio(
  BuildContext context,
  Patient patient, {
  PhysioTab tab = PhysioTab.assess,
}); // push on the root navigator, wrapped in Theme, exactly like openCharting

class PhysioScreen extends ConsumerStatefulWidget {
  const PhysioScreen({super.key, required this.patient,
      this.initialTab = PhysioTab.assess, this.embedded = false, this.picker});
}
```

| Tab label | Cards, in this order |
|---|---|
| Assess | `ScreeningCard`, `MuscleChartCard`, `RomCard`, `SpecialTestsCard` |
| Progress | `GoalsCard`, `ProgressCard`, `OutcomeScalesCard` |
| Treat | `HepCard`, `ModalityCard`, `SessionsCard` |
| Records | `PhysioPhotosCard` |

- `ScreeningBanner(patient: patient)` sits above the tabs' content on every tab (safety, always visible). It must
  stay outside the swiping area.
- Header: reuse what `ChartingScreen` shows for title, back and patient name (`chartingTitle` at l.1194 is the
  pattern; write a physio one titled "Physio"). Show the allergy pill the way `ChartingScreen` does (l.296),
  with the allergy source `patient_details_view.dart` l.342-365 uses (homeopaths: case sheet; dentists: oral
  medicine history; others: no pill). Do not add anything else to the header.
- Phone: `SwipePages<PhysioTab>` (`lib/shared/widgets/swipe_pages.dart`, `keepAlive: true`) plus a floating
  `MobileNavBar.selection(showLabels: true, ...)` positioned exactly as `ChartingScreen` does it (l.1105-1122).
  Items: Assess, Progress, Treat, Records. Each tab scrolls; bottom padding `MobileMetrics.bottom(context)` so
  the last card clears the bar. Use the phone backdrop the way `ChartingScreen` does.
- PC: `CruSegmentedControl<PhysioTab>` under the header, same `SwipePages`; use `DetailsColumns` for two columns
  when wide (Assess: muscle chart left, the rest right).
- Cards are separated by `CruSpace.cardGap`.
- `lib/features/therapy/presentation/widgets/muscle_chart_card.dart` hosts a web view: check that swiping tabs
  does not steal its rotate gesture. If it does, copy how `ChartingScreen` handles its 3D view.
- Icon: add `PhysioIcons.physio` in a new `physio_icons.dart` beside the screen, declared the same way as
  `HomeopathyIcons` (`lib/features/homeopathy/presentation/widgets/homeopathy_icons.dart`). A simple stroked
  standing figure. Use it everywhere below.

## Task 2: patient page (`lib/features/patients/presentation/patient_details_view.dart`)

1. Add `final canPhysio = clinical;` near `isPhysio` (l.336).
2. PC header actions (l.764): add `_PhysioButton(patient: p, compact: compact)` for `canPhysio`, after the
   dentist buttons. Copy `_ChartingButton`: secondary style; inside the shell set `physioPatientIdProvider` and go
   to `DesktopTab.physio` (Task 5), otherwise `openPhysio`.
3. Physio logins no longer have a Clinical page (one way to reach each thing, like dentists):
   `final tabs = [_Tab.overview, if (isHomeopath) _Tab.clinical];` and `hasClinical` follows. Delete the
   `if (isPhysio)` branch of `clinicalScreen()` and the imports that become unused.
4. Phone bottom bar (`_PatientDetailsBottomBar`). Show the bar when
   `phone && open == null && (canPhysio || canBook)`. Add `canPhysio`, `isPhysio`, `onOpenPhysio`.

   | Login | Pill contents, left to right |
   |---|---|
   | Dentist | (+) New visit, (physio) circle, **Open chart** capsule |
   | Physio | (+) New visit, **Open physio** capsule |
   | Other clinical (homeopath, general, ...) | (physio) circle, **New visit** capsule |
   | No clinical access | **New visit** capsule (as today) |

   Circles are `_PillCircle` (needs `canBook` for the + ones); the filled one is `_PillCapsule`. If `canBook` is
   false, drop the New visit control and, for "Other clinical", make the capsule **Open physio**. Never two
   capsules.
5. Red flags on Overview: put `ScreeningBanner(patient: p)` at the top of both `overview` and `phoneOverview`
   (under the poster on phone) when `canPhysio`. It already draws nothing without flags and brings its own bottom
   gap, so add no extra spacing.

## Task 3: phone patient list (`lib/features/mobile/mobile_patients.dart`)

1. `_rightSwipe`: order is tooth chart (dentist with clinical access, unchanged), then
   **Physio** (`isPhysiotherapyProvider` and clinical access: label `Physio`, icon `PhysioIcons.physio`, tone
   `MobileTone.teal`, `openPhysio(mobileRoot(context), s.patient)`), then Call as today.
   Update the doc comment above it.
2. Long-press sheet `_actionsSheet`: add `MobileSheetAction(label: 'Physio', ...)` just above "Open record" for
   anyone with clinical access, all specialties.

## Task 4: pop-ups and notes

1. `lib/features/patients/presentation/widgets/details/visit_session_dialog.dart` l.257 and l.435: "Session
   photos" shows when clinical access AND (physio login OR the patient has at least one physio record).
2. `lib/features/therapy/presentation/widgets/soap_phrase_bar.dart` l.58: same condition instead of
   `isPhysiotherapyProvider` only. The widget needs the patient id; pass it from `session_note_screen.dart` l.314.
3. For "has a physio record" add one provider, `patientHasPhysioProvider(patientId)`, in
   `lib/features/therapy/`: true if any `patientRecordsProvider((patientId: ..., kind: k))` is non-empty for the
   per-patient physio kinds in `dental_records_repo.dart` l.63-129 (not `physioExercise` or
   `physioHepTemplate`, which belong to no patient).

## Task 5: PC sidebar page

1. `lib/features/dashboard/presentation/dashboard_actions.dart`, `DesktopTab`: add `physio` with the next unused
   number (one above the current highest).
2. `cru_sidebar.dart`: add `_NavItem(DesktopTab.physio, 'Physio', PhysioIcons.physio)` in the Patients group
   right after Charting, for every specialty. Add it to the maps/lists near l.74-90 the same way Charting is.
3. `lib/core/clinic/clinic_tabs.dart` `clinicAllowsDesktopTab`: `physio` requires `clinicalView` (add it to the
   Files condition). `DentalFeature.forTab` must return null for it.
4. New `physio_page.dart` next to the screen, copying `charting_page.dart`: `physioPatientIdProvider`, the
   patient search, back to Patients when none is picked. Make `_PatientSearch` public in `charting_page.dart` and
   reuse it; do not copy it.
5. `desktop_shell.dart`: add `case DesktopTab.physio: return const PhysioPage();` and include the tab wherever
   `DesktopTab.charting` gets special handling (also check `voice_navigation.dart`, `voice_ai_bridge.dart`,
   `core_tools.dart` l.38 for exhaustive tab lists; add "physio" there).
6. Phone "More" (`mobile_more.dart` l.145-175): Physio needs a patient, so hide it from More exactly as
   Charting is hidden.
7. `patients_table.dart`: physio logins that do not get the chart button get a physio button in the same column,
   same behaviour.

## Task 6: Recalls for every clinical login

Physio package recall suggestions and homeopathy follow-up recalls are saved today but those logins cannot open
Recalls.

1. `cru_sidebar.dart`: move the `Recalls` `_NavItem` out of the `chairside` block so every login gets it.
   Treatment plans stays dental.
2. `lib/features/dental/dental_features.dart` `forTab`: remove `DesktopTab.recalls`. Leave recalls in
   `DesktopTab.isDental`, which is what makes `clinicAllowsDesktopTab` require `clinicalView` for it.
3. `lib/features/dental/records/recalls.dart`: dental recall rules must **never** be created for a non-dentist.
   `ensureRecallRules` (l.145) seeds default dental rules when read. In `RecallsScreen`, watch
   `recallSuggestionsProvider` (l.727) only when `isDentalProvider`, and show the "Rules" button only then. Guard
   the other readers the same way: `recallRulesProvider` at l.368, l.458 and l.1012, and `ensureRecallRules` in
   `recall_rule_sync.dart` l.62. A non-dentist types the recall reason.
4. `test/features/dental/dental_features_test.dart` l.92 expects recalls to be blocked: update only that
   expectation to match.

## Task 7: clean up

Search `lib` for text that tells the user to find physio things under "Clinical" and fix it. Remove unused imports.

---

## Checks (once, at the end)

1. `flutter analyze` on the files you touched: no new issues.
2. `flutter test test/features/dental/dental_features_test.dart test/features/physio_goals_test.dart test/features/physio_screening_test.dart test/features/modality_log_test.dart`
3. `flutter build apk --release` (never stop it midway), then
   `adb -s 51171XEKB7K14E install -r build/app/outputs/flutter-apk/app-release.apk`
   (adb is in `%LOCALAPPDATA%\Android\Sdk\platform-tools`). Skip the install if the phone is not connected.

## Report

Per task: done / skipped (why), files changed, check output pasted as it is. Say "not checked on the phone" for
anything you did not see on the phone. Then stop.

**GATE:** stop after the report. No commit until Soham says so.
