# Brief for Antigravity: phone layout for Patient details and Charting, chart background by mode

Repo: `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc` (Flutter, package `doctor_management_app`).
Written 13 Nov 2026 by Opus after reading both screens. Do the phases **in order**. After each phase, stop and
write the report (format at the end). Do not start the next phase until Soham says go.

## Ground rules (all phases)

- **PC stays as it is.** Soham is happy with the PC layout. Change only what each phase names. "Phone" means
  width under 600. Phase 1 is the only change visible on PC.
- Follow `CruDoc/.claude/rules/crudoc-ui.md`: design tokens only (no hard-coded colours, radii, sizes, spacing);
  one filled button per region; red only for allergies; violet only for AI; amber = waiting; green = done;
  motion 200-250 ms easeOutCubic.
- Do not delete features. Everything removed from one place must still be reachable from exactly one other
  place listed in this brief.
- Do not touch `CruDoc/dental3d/` or `CruDoc/assets/dental3d/` (Opus already fixed the 3D tap there).
- No commits, no new tests or goldens. Do not run `flutter test` on the whole project (dental tests hang on this
  PC). Run only the commands named in each phase.
- Do not say "checked in the app" or "looks right" unless you produced the PNG pictures asked for in Phase 4.

## The rule behind every change

Each thing on screen must answer: what is it for, why here, why now. On a phone that means:
1. **Safety first, always visible**: name and allergy pill.
2. **The main job gets the thumb**: the one main action sits at the bottom, where the thumb is.
3. **Show it where it is used**: Recall lives with visits, Scan lives with files, records live in Records.
4. **One way to reach each action on a view.** No second button for the same thing.
5. **Hide what does not apply**: Milk teeth only for children, legend only lists marks this patient has.

---

## Phase 1: chart background follows the active mode (PC and phone)

Today the odontogram is always white paper, so Dental, Plan and All look the same at a glance.

Where:
- Active mode: `ChartLayer` (`lib/features/dental/presentation/desktop/chart/tooth_chart_data.dart` l.14-57),
  held in `_ToothChartCardState._layer` (`lib/features/dental/presentation/desktop/tooth_chart_card.dart` l.190).
- White paper: `static const _paper = Color(0xFFFFFFFF)` and the panel paint in
  `lib/features/dental/presentation/desktop/chart/odontogram_picture_chart.dart` l.331 and l.339-343.
- Row chart (`chart/tooth_chart_2d.dart`) has no fill; the card surface shows through. Perio and Endo use the row
  chart (`odontogram_picture_chart.dart` l.108).
- Legend colours per layer: `chart/chart_legend.dart` (`ChartMark.of`, from l.40).

Do:
1. Add one function, e.g. `Color chartPaper(ChartLayer layer, CruColors c)`, in `tooth_chart_data.dart`:
   - `dental`: today's paper (white in day theme; keep what evening uses now).
   - `plan`: paper mixed 6% with the colour the legend uses for the "planned" mark.
   - `perio`: paper mixed 6% with the legend's gum/pocket colour.
   - `endo`: paper mixed 6% with the pulp colour (`CruColors` pulp getter, `crudoc_shared/lib/theme/cru_colors.dart` ~l.470).
   - `all`: paper mixed 4% with `c.textSecondary` (neutral grey paper).
   - Evening theme: same idea, 10% mix against the evening paper.
   - If a legend colour is the allergy red or the AI violet, use `c.textSecondary` instead.
   Use `Color.lerp(paper, tint, amount)`.
2. Odontogram painter: replace the constant `_paper` with a `paper` field passed in from the widget
   (`OdontogramPictureChart` already receives `layer`).
3. Row chart: wrap the chart canvas area in `tooth_chart_card.dart` (canvas built around l.359-411) in an
   `AnimatedContainer` with that colour and the panel radius token, so Perio and Endo get the tint too.
   Animate the change: 220 ms, `Curves.easeOutCubic`.
4. The 3D compact view is not changed.

Check: `flutter analyze lib/features/dental` shows no new issues.

---

## Phase 2: Patient details on phone (width under 600)

Files: `lib/features/patients/presentation/patient_details_view.dart`,
`lib/features/patients/presentation/widgets/details/identity_header.dart`,
`lib/features/patients/presentation/widgets/details/details_top_bar.dart`, the cards in
`lib/features/patients/presentation/widgets/details/` (visits_card.dart, payments_block.dart,
patient_files_card.dart). Phone flag already exists: `phoneBelow = 600` (identity_header.dart l.58),
`_phoneWidth` (patient_details_view.dart l.60).

Target (phone):
```
 ‹ Patients                                   •••
 (AB)  Asha Bhosale                     [call] [wa]
       34 · F · 98200 00000
 [ Allergic to penicillin ]        (or outlined "No known allergies")
 [   Overview   |   Clinical   ]   (only when Clinical exists, as today)

 ┌ Medical history ─────────────── Edit ┐   first 3 lines, then "Show all"
 ┌ Visits ──────────────────────────────┐
 │ Recall · 12 Jan                    › │   dentists only, moved here
 │ 3 Nov  Scaling            Dr. Rao    │
 │ See all 8 visits                     │
 ┌ Payments ───── ₹1,200 due  [Record] ┐   if nothing due: one row "Payments · No dues ›"
 ┌ Files ─────────────────────── [+] ──┐   only Add in the header
 ┌ Assigned doctors ───────────────────┐   as today, only when scope is 'assigned'

 ════════════════════════════════════════  sticky bar, safe area
 [  New visit  ]   [■ Open chart ]          dentist: inset + filled
 [■        New visit             ]          everyone else: one filled
```

Do:
1. **Top bar (phone):** keep back link and ••• only. Remove the Charting, Recall and "+" (New visit) icon buttons
   from the phone top bar (`patient_details_view.dart` l.575-577, identity_header.dart l.110-118). PC keeps them.
2. **Call and WhatsApp (phone):** move them to the right end of the name row (they are about this person, not the
   page). Keep them hidden when there is no phone number.
3. **Sticky bottom bar (phone only):** new widget at the bottom of `PatientDetailsScreen` / phone body, inside
   `SafeArea`, surface colour with a hairline top border.
   - Dentist: `New visit` (inset secondary button, if `canBook`) + `Open chart` (filled, tooth icon, same action as
     `_ChartingButton` l.702-738).
   - Others: `New visit` filled, full width (if `canBook`). No bar when nothing to show.
   - Add bottom padding to the scroll content equal to the bar height so nothing hides under it.
   - Hide the bar while a sub-screen (Visits, Files, Payments) is open.
4. **Recall (phone, dentists):** first row inside the Visits card: "Recall · <date>", or "Recall overdue · <date>"
   in the amber tone, or "Set recall" when none. Tap does exactly what `_RecallButton` (l.742-789) does. Reuse its
   logic; do not copy-paste the date logic twice (extract a small helper if needed).
5. **Files card (phone):** header shows only the Add icon. Move `Scan` and `Dose log` into the Files
   sub-screen header (they stay as they are on PC).
6. **Payments card (phone):** when nothing is due, show a single row "Payments · No dues" with a chevron that
   opens the Payments sub-screen. When something is due, keep today's card with `Record payment`.
7. **Medical history card (phone):** show at most 3 lines, then "Show all" expands in place. "Edit" stays.
8. Order on phone: Medical history, Visits, Payments, Files, Assigned doctors.

Not changed: ••• menu contents, sub-screens and their morph, Overview | Clinical switch, PC layout.

Check: `flutter analyze lib/features/patients` shows no new issues.

---

## Phase 3: Charting on phone (width under 600), and 600-999 without the shelf

Files: `lib/features/dental/presentation/desktop/charting_screen.dart` (ChartingScreen l.78, top row l.387-409,
tabs l.497-523, shelf l.718-721, workspaces l.578-681), `charting_page.dart` (patient search l.53-58),
`charting_records.dart` (ChartingTab l.25-37, records l.84-358, RecordShelf l.378, RecordGrid l.673),
`tooth_chart_card.dart` (controls l.272-331, canvas l.359-411, 3D peek row l.422-430 and l.485-530).
Phone flag: width < 600 (charting_screen.dart l.223). Studio with inspector: width >= 1000 (`_studio`, l.70).

Target (phone):
```
 ‹ Back   Asha Bhosale                         •••
          34 · F
 [ Allergic to penicillin ]

 [ Dental ▾ ]                          [2D|3D]   one tool row
 ┌──────────────────────────────────────────┐
 │        odontogram (tinted by mode)       │   chart gets the width
 └──────────────────────────────────────────┘
 ● Decay  ● Filling  ● Crown                     only marks this patient has
 ┌ 16 Upper right first molar · Decay  [Open] ┐  appears when a tooth is selected

 Needs care · DMFT 7
 16  Decay MO                                  ›
 ...

 ════════════════════════════════════════════
   Chart      Plan      Records     Wrap-up       bottom tab bar
```

Do:
1. **Header (phone):** one block: back link, patient name (callout w600) with age · sex under it, ••• on the
   right. Remove the "Charting" title on phone (the chart itself says where you are; the name matters more).
   ••• menu items: `Medical history` (opens the same OM history dialog the history chip opens today),
   `Switch patient` (sidebar Charting page only; opens the existing patient search as a sheet instead of the
   always-visible search field).
2. **Safety row (phone):** only the allergy pill (red if allergic, outlined "No known allergies" otherwise).
   The history chip moves into ••• (step 1). The DMFT chip moves to the "Needs care" header (step 6).
3. **Recall:** remove the header Recall chip on phone, and the Recall tile from the record shelf/panel clusters.
   Recall stays in exactly one place: the Wrap-up tab tile (it is an end-of-visit job). PC keeps its header chip.
4. **Tabs (phone):** replace the top segmented control with a bottom tab bar of 4: `Chart`, `Plan`, `Records`,
   `Wrap-up`. Use the app's existing bottom-bar style if one exists in `lib/features/mobile/`; otherwise a
   simple bar with icon + label, accent for the active tab.
   - `Surgery` and `Kids & ortho` stop being tabs on phone and 600-999: their tiles become sections inside Records.
   - 600-999: keep a top segmented control, but with the same 4 tabs.
   - Swipe between tabs stays.
5. **Records tab (phone and 600-999)**, top to bottom, using `RecordGrid` sections with the existing status badges:
   Exam (Perio, Endo, Pain & TMD, Photos, Eruption if child) · Treat (Root planing, Checklist, Sedation, LA dose,
   Consents, Behaviour if child) · After (Lab cases, Referrals) · Paper (Forms, Scan) · then `PatientFilesCard`.
   Then **remove the always-visible `RecordShelf`** on phone and 600-999 (l.718-721): its contents now live here.
6. **Chart tab (phone):**
   - One tool row above the chart: left a chip `Dental ▾` that opens a small menu (Dental, Plan, Perio, Endo,
     All; only Dental and Plan while 3D is on). Right: the `2D | 3D` toggle. On phone, 3D opens the full-screen
     page as today, so **remove the separate "Show patient" button on phone** (same page, two buttons).
   - `Adult | Milk teeth`: show only when the patient is under 16 or has milk-tooth records (the same test
     `defaultMilkTeeth` and the Kids tab use). Otherwise hide it.
   - Legend: list only the marks that appear on this patient's chart in the current mode. Small, one wrapped line,
     under the chart. Keep the "Perio dd MMM" text when perio is shown.
   - Selected tooth: show the peek row (tooth name, findings, `Open`) for 2D too, not only 3D. Reuse the 3D peek
     row widget. Tap outside clears it.
   - Session bar (when an older visit is loaded): a thin banner above the chart, "Viewing <date> visit · Latest",
     same actions as `_SessionBar` (l.1295).
   - Under the chart: "Needs care" list as today, header now "Needs care · DMFT n" (or "dmft n · DMFT n" under 16).
7. **Plan tab (phone):** remove the Medical history card from this tab (it is in ••• and on Patient details; the
   allergy pill stays visible). Keep plan card / "Create plan", then Procedures.
8. **Wrap-up tab:** unchanged (Visits card + tiles incl. Recall and Book next visit).

Not changed: PC at width >= 1000 (header, inspector, record panel, all tabs as today), Perio full screen,
Endo dialog, the tooth form.

Check: `flutter analyze lib/features/dental` shows no new issues.

---

## Phase 4: pictures for review

Use the render-harness way already used in this repo (a throwaway test with provider overrides that paints the
screen to PNG; see `test/tool/tooth_chart_sheet_test.dart` for the pattern). Run that one test file alone.
Save to `CruDoc/handoff/out/phone_layout/`:
- `details_phone_dentist.png`, `details_phone_other.png` (390 x 844)
- `charting_phone_chart_dental.png`, `charting_phone_chart_plan.png`, `charting_phone_records.png` (390 x 844)
- `charting_tablet_chart.png` (800 x 1100), `charting_pc_plan.png` (1440 x 900, to show PC unchanged except tint)
Delete the throwaway test after the pictures are saved, unless it was already in the repo.

---

## Report format (after each phase, short)

- Files changed (paths).
- What moved where (one line each), and anything you could not do as written, with the reason.
- Analyze result (paste the summary line).
- Any place where the brief did not match the code (line numbers moved, widget missing).
