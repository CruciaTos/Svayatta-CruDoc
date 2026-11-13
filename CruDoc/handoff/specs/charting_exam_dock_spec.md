Read-only: I edited no files. Web search was thin, so findings 1, 2 and 4 are fetched and the rest are recalled from general knowledge (marked).

## (a) Reference findings

1. **Open Dental ODTouch** (fetched) -> its mobile Chart home is a read-only glance, and all editing sits behind one edit icon. Perio is not available on phones. -> Fit: Chart should be glance-first with one-tap entry. We beat it by keeping perio and endo on the phone.
2. **Archy charting** (fetched) -> a colour-coded odontogram, dentition picked by age (primary for children), and multi-procedure bundles in one click. -> Fit: our age-based Adult/Milk default and the single-tap tooth select already match. Exams still need a permanent entry point.
3. **Medicasimple** (search snippet) -> "Click a tooth, build a plan, done." -> Fit: supports the owner's single-tap select and double-tap open.
4. **Laws of UX, Hick's law** (fetched) -> limit choices when speed matters, chunk, highlight the recommended option, and do not oversimplify. -> Fit: group exams as one icon chunk and keep fixed positions. Do not hide the exams behind a menu.
5. **Apple Phone/Contacts card** (recalled) -> a row of round icon quick actions (message, call, video, mail) with tiny labels. This is the owner's "phone app profile" inspiration. -> Fit: this is the exam dock (Concept 1).
6. **Google Maps layers button** (recalled) -> one icon opens the layer choices and the rest of the UI stays quiet. -> Fit: the phone layer chip stays as the single entry to layers, and the 2D|3D switch becomes one icon.
7. **Lightroom mobile / Procreate** (recalled) -> an icon-only tool strip, with options shown only for the selected tool, and a very quiet canvas. -> Fit: the dock is icon-led, and the tooth peek row is the only contextual UI.
8. **iOS context menus (HIG)** (recalled; the fetch returned only the title) -> keep them short, show only what is relevant to the selection, and never make them the only path. -> Fit: double-tap is a shortcut, so the peek row keeps a visible chevron as the discoverable path.
9. **Apple Health / Fitness summary tiles** (recalled) -> glanceable status tiles ordered by attention. -> Fit: Concept 3, and a possible later upgrade to the dock's status line.
10. **Notion slash menu / iOS Recents** (recalled) -> recent-first short lists with "more" behind a link. -> Fit: the Wrap-up "Follow-ups" glance for referrals and lab cases (latest item plus "+N").

## Current phone choice count (adult, one allergy, 4 teeth needing care, 3 visits)

I count tappable controls: header, tools, rows and the 4 nav tabs. The 32 teeth are excluded.
- **Chart: 13.** Back, ⋯, layer chip, 2D, 3D, 4 Needs-care rows, 4 nav. It grows with the number of needs-care rows, and a child adds Adult/Milk (+2). There are also 5 hidden layer options.
- **Records: 19** (21 for a child). Back, ⋯, 13 rows (Exam 4, Treat 5, After 2, Paper 2), the Files card, 4 nav. Reaching Endo takes the Records tab, a scroll, then a row.
- **Wrap-up: 18.** Back, ⋯, Visits (3 rows plus New), 8 tiles, 4 nav.
- **Total 50.**

## (b) Three concepts

### Concept 1: "Exam dock" (icon strip on Chart)

**Chart tab**
```
┌────────────────────────────────────────┐ 390
│ <  Priya Sharma                     ...│ header unchanged
│    34 · F                              │
│ (! Penicillin allergy)                 │
│ ┌────────────────────────────────────┐ │
│ │ Dental v                      [3D] │ │ layer chip + one cube icon
│ │       upper arch                   │ │
│ │       lower arch                   │ │
│ │ legend (unchanged)                 │ │
│ └────────────────────────────────────┘ │
│  46  Deep caries · MO              >   │ peek (only if tooth selected)
│ ┌────────────────────────────────────┐ │
│ │ (perio)  (endo)  (pain)  (ortho)   │ │ EXAM DOCK: 44px circles
│ │ Perio    Endo   Pain/TMD  Ortho    │ │ child adds 5th: Eruption
│ │ 12 Nov   2 open  VAS 4    New      │ │ status: amber open, green done
│ └────────────────────────────────────┘ │
│  [tooth 3 need care >]                 │ quiet pill, hidden at 0
│  ====== Chart Plan Records Wrap-up === │ blue pill nav
└────────────────────────────────────────┘
```

**Records tab** (Treat and Paper tools only; Exam, After and Files are gone)
```
│ <  Priya Sharma                     ...│
│ ┌────────────────────────────────────┐ │
│ │ (LA)   (SRP)  (Consent)(Checklist) │ │ one card, 4 columns, fixed order
│ │ LA dose Root   Consents Checklist  │ │
│ │         planing 2 signed 1 open    │ │
│ │ (Sed)  (Forms)(Scan)   (Behaviour) │ │ Behaviour only for a child
│ │ Sedation Forms  Scan    Behaviour  │ │
│ └────────────────────────────────────┘ │
```

**Wrap-up tab**
```
│ Visits card (unchanged)                │
│ ┌────────────────────────────────────┐ │
│ │ (Rx)    (Rs)   (Cert)  (Report)    │ │ 4 action icons, no description text
│ │ Prescr. Bill   Certif. Report      │ │
│ └────────────────────────────────────┘ │
│ Follow-ups                             │ hidden if both are empty
│ ┌────────────────────────────────────┐ │
│ │ [^] Referrals  Dr Mehta · Endo  2 open >│ -> referrals screen
│ │ [#] Lab cases  Crown 46 · At lab +1  1 active >│ -> lab cases screen
│ └────────────────────────────────────┘ │
```

**Counts**
- **Chart: 13.** Back, ⋯, layer, 3D, dock 4, pill 1, nav 4. It is flat against 13 because the dock moves 4 exams onto Chart. It no longer grows with the number of needs-care rows. A child gets 14.
- **Records: 13** (from 19). Back, ⋯, 7 tools, 4 nav. A child gets 14.
- **Wrap-up: 16** (from 18). Back, ⋯, Visits 4, icons 4, glance 2, 4 nav.
- **Total 42 vs 50.**
- **Taps to an exam: 1** (from 2 plus a scroll).

### Concept 2: "Tooth-first with a lens button" (radical, 3 tabs)

**Chart tab**
```
│ <  Priya Sharma                     ...│
│ (! Penicillin)                         │
│ ┌────────────────────────────────────┐ │
│ │   odontogram, taller               │ │
│ └────────────────────────────────────┘ │
│                                  (lens)│ floating exam button, bottom right
│ ( 46   form   endo   perio   +plan )   │ contextual pill, only with a tooth selected
│  ====== Chart  Plan  Wrap-up =======   │
```
Opening the lens fans out Perio, Endo, Pain/TMD, Ortho (and Eruption) as labelled status chips above the button. Records is dropped as a tab. Its tools go in a sheet from ⋯ (a 4x2 icon grid).

**Counts**
- **Chart at rest: 7.** Back, ⋯, lens, 3D, 3 nav. When the lens is open it is 11.
- **Wrap-up: 15.**
- Exams take 2 taps.
- **Risk:** exams are hidden at rest, which cuts against the owner's "they should have importance". It also needs a new contextual pill and a speed-dial.

### Concept 3: "Exams hub tab" (status tiles)

**Exams tab** (replaces Records)
```
│ <  Priya Sharma                     ...│
│ ┌──────────────────┐┌─────────────────┐│
│ │ (perio)       !  ││ (endo)          ││
│ │ Perio            ││ Endo            ││
│ │ BOP 18% · 4 >=5mm││ 46 · canals 2/3 ││
│ └──────────────────┘└─────────────────┘│
│ ┌──────────────────┐┌─────────────────┐│
│ │ Pain/TMD         ││ Ortho           ││
│ │ trend  VAS 4     ││ [photo] 2 sets  ││
│ └──────────────────┘└─────────────────┘│
│ ┌──────────────────┐┌─────────────────┐│
│ │ Eruption (child) ││ ... More tools  ││ -> sheet of 7 icons
│ └──────────────────┘└─────────────────┘│
│  ====== Chart  Plan  Exams  Wrap-up ==  │
```
Chart tab is the odontogram only: layer, 3D and the needs-care pill. Wrap-up is the same as Concept 1.

**Counts**
- **Chart: 9.**
- **Exams: 11.** Back, ⋯, 4 tiles, 1 tools tile, 4 nav.
- **Wrap-up: 16.**
- **Total 36.**
- Exams take 2 taps and no scroll.
- The tiles carry richer glance data (BOP %, canals, pain trend, photo thumbnail). Those values are not in `chartRecords` today, so new derivations are needed.

## (c) Recommendation: Concept 1

1. **One tap.** Exams get the shortest path, from the screen where they are performed.
2. **Same pattern the owner already likes.** It copies the contact-card quick-action icon row and the phone screens' circle icon tiles.
3. **Nothing moves between views.** The dock is fixed in place. Records uses a fixed order with no reordering, which respects the "consistent control positions" rule.
4. **Hick's win where it counts.** Total choices go from 50 to 42. Exam access falls from 2 taps plus a scroll to 1. Records falls from 19 to 13 and no longer scales with the data.
5. **Mostly reuse.** `ChartRecord`, `chartRecords`, the existing dialogs and `MobileMetrics` are reused. No new data derivation and no change to the tab set, nav or header.
6. **Why not the others.** Concept 2 hides the exams and replaces the tab architecture. Concept 3 needs new data fields and still costs 2 taps. Its richer status line can be added to the dock later.

## (d) Implementation spec for Concept 1

All paths are under `C:\Soham\Kamachya_Goshti\Svayatta_CruDoc\CruDoc\lib\features\dental\presentation\desktop\`. Use tokens only (`CruSpace`, `CruType`, `c.*`), Geist, and no hard-coded values. No new tests or goldens.

### Dependency
The single-tap select / double-tap open change is a separate item.
- `ToothChartCard.onToothSelect` becomes select-only on phone.
- A new `onToothOpen` (double tap) must be wired in `ToothChartArches`, `ToothChartArches3d`, `ToothChart2D` and `Dental3dView`.
- This spec only changes `_Peek` (step 5).

### Breakpoints
- **Phone <600:** the full redesign below.
- **Tablet 600–999:** it shares the same workspaces, so these apply:
  - the ExamDock appears on Chart;
  - the Exam section, After section and Files card are removed from Records;
  - the Treat and Paper `_RecordSection`s stay as cards;
  - Wrap-up gets the Follow-ups glance;
  - the layer-chip and 3D-icon change (step 5) is phone-only;
  - the `needsCareCard` stays on the Chart tab as it is today. The new needs-care pill is phone-only.
- **PC ≥1000:** unchanged, with two exceptions:
  - the Wrap-up tile removals apply at every width (the owner's decision);
  - Files and `RecordPanel` are untouched.

### 1. `charting_records.dart`
- `ChartRecord` gets two optional fields:
  - `String? dockLabel`
  - `String? recent`
- Set `dockLabel` in `chartRecords`:

| id | dockLabel |
|---|---|
| perio | `Perio` |
| endo | `Endo` |
| pain | `Pain/TMD` |
| ortho | `Ortho` |
| eruption | `Eruption` |

- `recent` for the follow-up records:
  - `lab`: sort `labCases` by `recordedAt` descending, take the first, and use `'${lc.type} · ${lc.stage.label}'` from `LabCase.fromRecord`. Append `'  +${n-1}'` when n>1.
  - `referral`: use `DentalReferral.fromRecord(...).reason` on the newest record, with the same suffix. Check the field names in `referrals/referral_dialogs.dart` and `specialties/prostho/lab_case_dialog.dart`. If a field is missing, fall back to `DentalFormat.shortDate(recordedAt)`.
- `PatientLabCasesDialog` and `PatientReferralsDialog` are the "dedicated screens" at patient scope. Keep their `onOpen` as is.
- New widget `RecordIconGrid({required List<ChartRecord> records, GlobalKey? perioKey})`:
  - Single `CruCard`, padding 12 all round, radius 24. This is for phone and tablet only.
  - 4 columns on phone. On tablet use `(width/96).floor().clamp(4,6)`.
  - Cell, centred column (min 48 tap height, `CruPressable`, `onTap: r.onOpen`):
    - 44px circle, `c.inset` fill, `BoxShape.circle` (the `MobileIconTile` shape, but neutral).
    - Icon 20px, strokeWidth 1.8. Colour is `c.label` when `status != null` or `r.action`, otherwise `c.label3`.
    - A 4-px gap, then the label in `CruType.caption.w500.tint(c.label)`, maxLines 1.
    - Below that, status in `CruType.micro.tabular`, tone-coloured through the existing `_toneColor` (plain `label2`, warn `amberText`, done `greenText`). The line is blank, keeping its height, when null or for action records.
    - Amber attention dot, 8px, top-right of the circle, when `tone == warn`. Reuse the `MobileChip` attention-dot colour.
  - Wrap each cell in `Tooltip(message: r.detail)`.
  - Semantics: `'${label}. ${status ?? 'Nothing recorded yet'}'`.
- New widget `ExamDock` in a new file `charting_exam_dock.dart`:
  - It is `RecordIconGrid` with `dockLabel ?? label`, with one difference: records with no status show the status text `New` in `c.label3`.
  - `Expanded` cells in one row, so there are 4 cells, or 5 for a child.
  - At 360px, 5 cells give about 62px each. Ellipsis covers a long label. Do not wrap.
  - The `perioKey` goes on the Perio cell so the morph still grows from it.
- Delete `chartRecallRecord` if it has no other users (grep first).

### 2. `charting_screen.dart` — Chart tab
- `width < 1000` (phone and tablet): the workspace is `DetailsStack([PhoneSessionBar?, ToothChartCard(fullScreen: true), ExamDock(records: pick(['perio','endo','pain','ortho','eruption']), perioKey: _perioTile), if (phone && needsCare.isNotEmpty) NeedsCarePill])`.
- Remove `if (!studio) needsCareCard` on phone only.
- Dock order is fixed. Eruption appears only when `findRecord` returns it (a child, or one that already has a status).
- `NeedsCarePill` is a `CruPressable` in `c.inset` with a stadium shape. It uses:
  - `DentalIcons.tooth` at 14px;
  - the text `'N need care'` in `CruType.callout.w600`;
  - `CruIcons.chevronRight`;
  - left alignment.
- Tapping it opens a modal bottom sheet. The `sheet(...)` helper is already in `build`. It holds the existing `_ToothListCard`, with title `'Needs care · $dmftLabel'` and the same `onOpen`. The pill is hidden at 0, and that is the empty state.

### 3. `charting_screen.dart` — Records tab
- **Phone:** replace the sections and Files card with `RecordIconGrid(records: pick(['la','srp','consent','checklist','sedation','forms','scan','behaviour']))`. `pick` already drops missing ids. The order is fixed, with no reordering by status. Remove `PatientFilesCard` here.
- **Tablet (600–999, `!studio`):** keep `_RecordSection` for Treat and Paper only. Drop Exam, After and Files.
- **PC (studio):** unchanged.

### 4. `charting_screen.dart` — Wrap-up tab
- Remove `Book next visit`, `chartRecallRecord`, and `...pick(['referral','lab'])` from the tile list. Keep Prescription, Bill, Certificate and Medical report, each behind its current permission.
- **Phone and tablet:** `RecordIconGrid(records: [...asRecord()])` for those four tiles, with the ActionTile description text dropped.
- **PC (studio):** keep `RecordGrid`.
- `visitsCard` stays first on phone and tablet.
- Under the grid, on width <1000 only, add `_FollowUps(referral: findRecord(records,'referral'), lab: findRecord(records,'lab'))`:
  - Title `Follow-ups` in `CruType.callout.w600.tint(c.label2)`, matching `_RecordSection`.
  - One `CruCard` containing 1–2 rows with `CruSeparator` between.
  - A row is a `CruPressable`. Left: a 38px `c.inset` circle with `CruIcons.arrowUpRight` for referrals or `CruIcons.box` for lab cases. Middle: label in `callout.w600` over `recent` in `subhead.tint(c.label3)`, single line. Right: the status text in its tone, then `chevronRight`. Tap runs `r.onOpen`.
  - A row is hidden when `status == null`, and the section is hidden when both are.
- On PC, referrals and lab cases stay reachable through the inspector's `RecordPanel` "After" cluster.

### 5. `tooth_chart_card.dart` (phone branch only)
- Replace the 2D|3D `CruSegmentedControl` in `controls` with `CruSquareButton(icon: RadIcons.cube, secondary: true, semanticLabel: '3D view', tooltip: '3D', onPressed: () => unawaited(openFullScreen()))`. It is disabled when `child` is true.
- Keep the layer chip and menu as they are. `DentalIcons.chart` is available if a leading glyph is wanted. `CruIcons` has no layers icon.
- `_Peek`: replace the `CruCapsuleButton('Open')` with `CruIcons.chevronRight` (16px, `c.label3`). Make the whole row a `CruPressable` calling `onOpen`.

### Unchanged
Nav bar, header, ⋯, Plan tab, Perio and Endo dialogs and their morph.

### Verify
Render at 390x844, at 360x740 and in dark mode, for an adult and a child (the render-harness approach). Check the dock and chart fit on one screen at 390x844. Scrolling is fine at 360x740.

### Sources
- [Open Dental ODTouch chart](https://opendental.com/manual/odtouchchart.html)
- [Archy dental charting](https://www.archy.com/platform/dental-charting)
- [Medicasimple clinical charting](https://www.medicasimple.com/dental-charting)
- [Laws of UX: Hick's law](https://lawsofux.com/hicks-law/)