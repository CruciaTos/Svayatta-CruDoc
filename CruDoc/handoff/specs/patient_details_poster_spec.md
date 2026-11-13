PHONE PATIENT DETAILS: DESIGN REPORT (read-only; no files edited)

Method note. WebSearch returned thin detail for most apps (no Mobbin, little on Truecaller or Spotify internals). Findings marked [search] were confirmed by a search result. Findings marked [knowledge] come from my knowledge of the product. The code facts in (d) were read directly from the repo.

(a) REFERENCE FINDINGS

1. iOS Contacts / Contact Poster -> big name typography on a full-bleed "poster", with the poster as the card background [search] -> FITS the large centred name hero. Search also notes Liquid Glass obscures the image and users find the faint type hard to read, so keep high-contrast ink and drop the image. Sources: [TidBITS](https://tidbits.com/2025/11/17/how-to-set-contact-avatars-and-posters-on-the-iphone/), [MacRumors thread](https://forums.macrumors.com/threads/ios-26-change-contacts-background-color.2466250).
2. Google Contacts (Material 3 Expressive) -> Call/Message/Video/Email as a pill row under the name, and details split into separate cards ("Contact info", "About", "Labels") [search] -> the grouping fits. The action pill row does NOT fit: the owner removed Call and WhatsApp, and he wants icons rather than labelled buttons. Source: [9to5Google](https://9to5google.com/2025/08/14/google-contacts-material-3-expressive/).
3. Apple Health Medical ID -> one dedicated safety block (allergies, conditions, meds, notes) that is read-only until Edit [search] -> FITS the "is it safe" question. Becomes a full-width allergy band plus a red bezel on the monogram. Source: [Apple Support](https://support.apple.com/105072).
4. Truecaller -> identity-first screen; tapping the photo shows details, tapping the name opens chat; the home tab merges call/SMS/chat into one stream [search] -> the "who is this" first idea fits. The merged stream does not fit, since there is no calling here. Source: [Beebom](https://beebom.com/truecaller-redesign-adds-fullscreen-caller-id-important-sms-tab-in-india).
5. Telegram / WhatsApp profile -> large avatar and name that collapse into a pinned compact bar on scroll [search, via a design-contest critique and an open-source clone]. The critique flagged buttons staying tappable under a collapsed header -> copy the collapse. Keep the pinned bar to back, mini identity and menu only.
6. Apple Music / Spotify artist page -> hero scrolls away while a compact title bar pins and fades in [search: generic pattern, Spotify specifics unconfirmed] -> FITS. The hero lives inside the scroll and only a small bar is pinned, so the scroll extent never jitters.
7. EHR patient banner, Epic-style (a persistent strip of demographics, allergies and status) [search: general EHR description] -> the safety strip is always one glance away. The same sources found clinicians preferred a plain listed summary over a novel timeline redesign, so stay scannable and don't be too clever.
8. Linear mobile -> properties as an icon-led metadata pill row [search: unofficial teardown, low confidence] -> informs the "Glance" row and icon-led record tiles with the value beside or under the icon.
9. Apple Wallet -> overlapping card stack with only title strips peeking; tap to bring one forward [knowledge] -> distinctive. It hides information, which is bad for allergy and dues (Concept 3).
10. Apple Health summary "Highlights" -> a few big-number tiles on one card, tap for detail [knowledge] -> the model for the three-cell glance row.

(b) THREE CONCEPTS (390 px wide, 16 px gutters, content width 358, on the soft-dot backdrop)

Shared rules for all three:
- No Call or WhatsApp anywhere. The phone number stays as plain text in the meta line.
- CruMonogram stays grey. Name text uses MobileType.largeTitle.
- The floating bottom bar is restyled as the main nav's blue pill (see (d)).
- PC (width 600 or more) is unchanged.

CONCEPT 1: "POSTER + CHART DOORWAY"

```
|  <  Patients                  [...]  |  pinned bar 48px (back, mini identity fades in, menu)
|                                       |
|              ( RM )                  |  monogram 72, red 2px bezel if allergic
|          Rohit Mehta                  |  largeTitle, centred, max 2 lines
|         34 M · 98200 12345            |  subhead, label2, tabular
|    [!] Allergic to Penicillin         |  allergy pill (CruInfoPill allergy), centred
|                                       |
| +-----------------------------------+ |  ONE glance card, 3 cells, hairline dividers
| | LAST       | NEXT       | DUE     | |
| | 12 Mar     | Tomorrow   | Rs4,200 | |   Due amber, or green check "Paid up"
| | RCT 36     | 4:30 pm    | 2 bills | |
| +-----------------------------------+ |
|                                       |
| Chart                                 |  group title (dentists only)
| +----+ +----+ +----+ +----+ +----+    |  icon tiles, fixed order
| |perio| |endo| |pain| |ortho| | +  |  |  icon + 1-line status under
| |12Apr| |2 open| |6/10| |2 sets|     |
| +----+ +----+ +----+ +----+ +----+    |
|                                       |
| +-----------------------------------+ |  Medical history card (existing)
| | Medical history          Edit      | |
| | Diabetes      Type 2 ...           | |
| | Show all                           | |
| +-----------------------------------+ |
| +-----------------------------------+ |  three one-line link cards (sub-screen sources)
| | Visits . 14                     >  | |
| | Payments . Rs4,200 due          >  | |
| | Files . 23                      >  | |
| +-----------------------------------+ |
|  Assigned doctors (only if clinic scopes)
|  .............bottom pill (blue).....  |
|   ( + )  [ tooth  Open chart ]         |
```

Scroll: the hero and glance card scroll away inside the Overview scroll view. The pinned bar's mini identity (28 px monogram, name 17 px, red dot if allergic) fades in once the name row passes under the bar, over about 40 px of scroll. Nothing else is pinned except the bottom pill.

Elements:
- Pinned bar: back (existing DetailsBackLink), the ••• menu (existing DetailsMoreMenu) and the mini identity. Purpose: orientation and the safe exit.
- Monogram with bezel: identity, and a safety signal visible even when scrolled.
- Name and meta line: who this is.
- Allergy pill: safety. Reuses `CruInfoPill` and `KnownAllergies` exactly as the current header does. Hidden when nothing is recorded.
- "Details pending" amber pill under the meta line: existing logic, same widget.
- Glance card, Last cell: lastVisit date plus `visitTitle`. Tap opens the visit via `openVisit`.
- Glance card, Next cell:
  - Shows the next visit (day and time, "Today" when today).
  - If there is no next visit, a dentist with a recall sees "Recall 12 Apr" (amber if overdue). Tap opens `showSetRecallDialog`.
  - Otherwise it shows "Book" with a plus. Tap calls `newVisit`.
  - It replaces the Visits card's recall row.
- Glance card, Due cell: the total from the same lines PaymentsSummaryCard sums. Amber when owed (tap `recordPayment`); green check "Paid up" when not (not tappable). Hidden if `!canBill`, and the card becomes 2 cells.
- Chart dock: one tile per chart record that has data for this patient, in fixed order (see (d)). Tile = icon tile, status text under it, tap opens that record. The trailing "+" opens a sheet of record types not yet started. This is where Perio, Endo, Pain/TMD and Ortho get their importance on the patient screen. Referral and lab-case tiles appear last as quick recent glances, matching the owner's "dedicated screen exists, so just a glance" note.
- Medical history card: reused, unchanged.
- Link cards: Visits, Payments, Files collapse to single rows. Detail lives in the existing sub-screens.
- Bottom pill: icon-only circle for New visit plus one wide "Open chart" (the single filled action).

Reuses: `CruMonogram`, `CruInfoPill`, `DetailsBackLink`, `DetailsMoreMenu`, `MedicalHistoryCard`, `AssignedDoctorsCard`, `chartRecords()` (charting_records.dart), `patientRecallInfo`, `patientBillingProvider`, the existing sub-screen morph.

Unique: a calm "poster" with a safety bezel and a patient-specific doorway into the charting screens. The number of choices scales with that patient's records, not with the app's feature count (Hick's law).

CONCEPT 2: "MOUTH MAP" (dentists only; others get Concept 1)

```
|  <  Patients                  [...]  |
|  ( RM )  Rohit Mehta                  |  left-aligned compact identity
|          34 M . 98200 12345   [!]     |
|  +-----------------------------------+ |
|  |  . . o . x . . . | . . # . . o . . | |  upper arch, 16 pips: finding colours
|  |  . . . o . . . . | . . . . . . . . | |  lower arch
|  +-----------------------------------+ |  tap a pip -> chart at that tooth
|  | LAST 12 Mar | NEXT Tomorrow | DUE  | |
|  Medical history ... link cards ...    |
```

- The mouth is the profile picture. Sixteen small pips per arch, coloured by finding (decay, filling, RCT, missing, planned). Tap a pip to open Charting on that tooth (`tooth_detail_screen`).
- It reuses `ChartLayer` and the tooth state in `tooth_chart_data.dart`, and the vector teeth now in `vector_teeth/` (untracked).
- Pros: the most unique idea, and the most useful one for a dentist.
- Cons: the 3D and 2D chart feature is still in flux. Per-patient tooth state needs a new lightweight provider and a pip painter. There is no equivalent for physio or homeopathy. Colours on the hero risk breaking the rule that red is only for allergies (needs a neutral palette).
- Not recommended as the first build, but it could later replace the Chart dock's hero.

CONCEPT 3: "DECK" (Wallet stack)

```
|  <  Patients                  [...]  |
|  ( RM ) Rohit Mehta  34 M   [!]      |  compact identity + allergy pill
|  +-----------------------------------+ |
|  | Visits . 14                        | |  front card, expanded (last 3 visits + next)
|  | Next: Tomorrow 4:30 pm             | |
|  | Last: 12 Mar . RCT 36              | |
|  +-----------------------------------+ |
|   Payments . Rs4,200 due            ^  |  peeking 44px strips, overlapped
|    Files . 23                       ^  |
|     Medical history . 3 flags       ^  |
|      Chart . perio, endo            ^  |
```

- Tapping a strip raises it to the front.
- Pros: distinctive, and only one card is open at a time (Hick's law).
- Cons: it hides allergies, dues and history behind a tap, which is wrong for a safety-critical screen. It fights the existing MorphBox sub-screens. A big rebuild for little gain.

(c) RECOMMENDATION: CONCEPT 1

- It is the only one that is both distinctive and safe. Allergy and dues are visible with zero taps.
- It answers every question the owner listed in one scroll position: who, safe, last, next, money, quick actions.
- It solves Hick's law by showing one choice per thing. "Next" is a single cell that means "what happens next". The dock shows only the records this patient actually has, in a fixed order (muscle memory, per the consistent-control-positions rule).
- It copies the phone-contacts idea the owner pointed at, a large centred identity that collapses to a pinned bar, with no new components beyond a hero, a three-cell card and an icon-tile row.
- It removes duplicate elements: the Visits recall row, the Payments summary body and the top-row buttons all go.
- It needs no new data. Everything reads existing providers.
- It keeps the existing sub-screen morph intact.

(d) IMPLEMENTATION SPEC FOR CONCEPT 1 (Sonnet worker; no design decisions left)

D0. Scope. Phone only (width under 600, i.e. `PatientDetailsHeader.phoneBelow`). The desktop branch keeps its current layout. Separately, any `onCall`/`onWhatsApp` removal on desktop is a different task. Do not add either back. The phone branch must never render them.

D1. New files in `lib/features/patients/presentation/widgets/details/`.

(1) `poster_hero.dart` defines `PatientPosterHero`. Inputs: `summary`, `allergies` (`KnownAllergies?`), `onEditPending`.
- Column, centred, no card. It sits directly on `MobileBackdrop`.
- `CruMonogram(name, size: 72)`, wrapped in a ring when `allergies != null && !allergies.none`.
  - Ring: a Container, circle border 2 px `c.redText`, with 3 px padding gap.
  - The ring is allowed because red means patient safety. The monogram itself stays grey.
- `SizedBox(CruSpace.s12)`.
- Name: `MobileType.largeTitle` tinted `c.label`, centred, maxLines 2, ellipsis, wrapped in `Semantics(header: true)`.
- `SizedBox(CruSpace.s4)`.
- Meta: `PatientFormat.ageSex(p)` plus `PatientFormat.phone(p.phone)` if the phone is not empty, joined by ' · '. `MobileType.subhead.tabular` tinted `c.label2`, centred.
- If `patientDetailsPending(p)`: `SizedBox(s8)` and the existing amber "Details pending" capsule. Move that capsule widget out of `identity_header.dart` into a shared private-to-library widget. Tap calls `showEditPatientSheet`.
- If allergies are not null: `SizedBox(s12)` and the same `CruInfoPill` (allergy tone, or the "No known allergies" outlined variant), centred.
- Outer padding: top `CruSpace.s8`, bottom `CruSpace.s16`.

(2) `patient_pinned_bar.dart` defines `PatientPinnedBar`. Inputs: `summary`, `allergic` (bool), `onBack`, `backLabel`, `menu`, `identity` (a `ValueListenable<double>` from 0 to 1).
- Height 48 (`CruSize.control` plus s8). Row with 16 side padding.
- Left: `DetailsBackLink`, wrapped in `FittedBox(scaleDown)`.
- Centre: `Opacity(identity.value)` containing a row of `CruMonogram(size: 28)` (with the red ring if allergic), `SizedBox(s8)`, and the name in `MobileType.title2` (Flexible, ellipsis). When opacity is 0 wrap in `IgnorePointer`.
- Right: `menu`.
- No call buttons, nothing else.

(3) `glance_row.dart` defines `PatientGlanceCard`.
- Inputs: `summary`, `now`, `due` (double), `isDentist`, `onOpenVisit(Visit)`, `onNewVisit` (nullable when `!canBook`), `onRecall` (nullable), `onRecordPayment` (nullable), `showDue` (bool, `canBill`), `showClinical` (bool).
- `MobileCard`, padding `EdgeInsets.symmetric(vertical: CruSpace.s12)`, wrapping `IntrinsicHeight(Row)`.
- Cells are `Expanded`, separated by a 1 px vertical `c.separator` line. Each cell is a `CruPressable` (`scaleOnPress: false`) with `semanticLabel`.
- Cell padding: 12 horizontal, 4 vertical. Layout inside a cell:
  - Label: `MobileType.micro` in `c.label3`, upper case, using the `groupLabel` style.
  - Value: `MobileType.callout.w600.tabular` in `c.label`.
  - Caption: `MobileType.caption` in `c.label2`, one line, ellipsis.
- LAST cell:
  - Value `PatientFormat.shortDate(lastVisit.scheduledStart)`; caption `visitTitle(lastVisit)` when `showClinical`.
  - No visit: value "—", caption "No visits yet"; not tappable.
  - Tap calls `onOpenVisit(lastVisit)`.
- NEXT cell:
  - If `summary.upcoming(now).firstOrNull != null`: value is `PatientFormat.dayTimeInline` (it already renders "Today"/day plus time), coloured `c.accentText` (a "now" state). Caption is `visitTitle`. Tap calls `onOpenVisit(next)`.
  - Else, if `isDentist` and `patientRecallInfo(...).due != null`: value is `recall.label` (amber `c.amberText` when `recall.overdue`). Tap calls `onRecall`.
  - Else, if `onNewVisit != null`: value "Book" with a `CruIcons.plus` glyph 14 px in `c.accentText`, caption "No visit booked". Tap calls `onNewVisit`.
  - Else: value "—", not tappable.
- DUE cell (only when `showDue`):
  - `due > 0`: value `PatientFormat.rupees(due)` in `c.amberText`; caption is the count of open items, e.g. "2 bills". Tap calls `onRecordPayment`.
  - `due == 0`: value "Paid up" in `c.label`, preceded by a `CruIcons.check` 14 px in `c.greenText`. Not tappable.
- If `!showDue`, render only the first two cells.

(4) `chart_dock.dart` defines `PatientChartDock`. Dentists only (`isDentist`).
- Input: `patient`, `clusters` (the `chartRecords(...)` result).
- Flatten all `clusters[*].records`. Keep records with `status != null && !action`.
- Fixed priority order (do not sort by recency):
  1. perio
  2. endo
  3. pain
  4. ortho
  5. eruption
  6. srp
  7. checklist
  8. sedation
  9. consent
  10. labcase
  11. referral
  12. forms, then the rest
- Show the first 4 as tiles, plus one trailing "+" tile. The "+" opens `showMobileActionSheet` listing every record whose `status == null && !action`, plus any records beyond the first 4. Each item shows the icon and label, and a tap calls `onOpen`. If that list is empty, omit the "+" tile.
- If no record has a status, return `SizedBox.shrink()`. Hide the whole section; never show placeholder data.
- Section title: `MobileGroupTitle('Chart', onBackground: true)`.
- Tile layout: 5 `Expanded` columns with 8 px gaps. Each is a `MobileCard` (`onTap: record.onOpen`).
  - Inside: padding 12 vertical and 4 horizontal; `MobileIconTile(size: 36, iconSize: 18, tone)`.
  - Tone: `RecordTone.plain` → `MobileTone.slate`; `warn` → `MobileTone.amber`; `done` → `MobileTone.green`.
  - Under it, the status text in `MobileType.micro.tabular`, `c.label2`, maxLines 1, ellipsis, centred.
  - The record label is not shown on the tile. It goes into `Semantics(label: '${record.label}, ${record.status}')` and a `Tooltip(message: record.label)` for long-press.
- The "+" tile uses `CruIcons.plus` in `MobileTone.blue`, with no status text.

D2. Edit `patient_details_view.dart` (phone branch only; every `phone ?` check stays driven by `constraints.maxWidth < _phoneWidth`).

(1) Add a `ScrollController _overviewScroll` and `ValueNotifier<double> _identity` to `_DetailsBodyState`. Dispose both.
- Listener: `_identity.value = ((_overviewScroll.offset - 80) / 40).clamp(0.0, 1.0)`.
- Attach `_overviewScroll` ONLY to the Overview page's `SingleChildScrollView`. Keep its `PageStorageKey`.
- Effective identity opacity passed to the bar: `1.0` when `_tab == _Tab.clinical` or `open != null`. Otherwise the notifier value. Wrap in `ValueListenableBuilder`.

(2) Phone body layout, replacing `PatientDetailsHeader` for phone:
- `Column[ PatientPinnedBar, if (tabs.length > 1) the existing CruSegmentedControl in a left-aligned padded row (pinned, 12 px bottom), Expanded(area Stack as today) ]`.
- Only the first child of the Overview column changes (below).
- The sub-screen Stack, `MorphBox`, `SwipePages` and `_page` logic stay untouched.
- Desktop and tablet keep `PatientDetailsHeader` exactly as now (minus call/WhatsApp).

(3) Overview content on phone: `Column(crossAxisAlignment: stretch)` with, in order, 16 px gaps (use `CruSpace.cardGap` between cards):
1. `PatientPosterHero`
2. `PatientGlanceCard`
3. `PatientChartDock` (dentist only)
4. `history` (`MedicalHistoryCard`, unchanged; null when `!clinical`)
5. `card(_Sub.visits)`, `card(_Sub.payments)`, `card(_Sub.files)` rendered consecutively with 8 px gaps (tighter than the 16 between cards)
6. `assignedDoctors`
- Clinical page for physio and homeopathy: unchanged.

(4) Pass `due` to the glance card using a new top-level helper `double patientDueTotal(PatientSummary s, PatientBilling b, bool showBills)` in `payments_block.dart`. It sums exactly the same three `lines` that `PaymentsSummaryCard` builds: package balance, unpaid fees, open bills. Refactor `PaymentsSummaryCard` to call it, so the numbers can never disagree.

(5) Dock data: in `_DetailsBodyState.build`, if `isDentist` and phone, call:

```
chartRecords(context, ref, p,
  go: (tab) => openCharting(context, p, initialTab: tab),
  onPerio: () => openCharting(context, p, initialTab: ChartingTab.perio))
```

Before wiring, grep `openCharting` and the `ChartingScreen` constructor. The screen already supports opening on Perio or Endo from outside. Add an optional `ChartingTab? initialTab` to `openCharting` only if it is missing.

(6) Remove `onCall` and `onWhatsApp` from the `PatientDetailsHeader(...)` call and from the widget, if the call-removal task has not already done so.

(7) Skeleton (`_DetailsSkeleton`, phone only): replace the left-aligned monogram row with a centred 72 px circle, a 180 px by 28 px line and a 120 px by 14 px line, followed by one `SkeletonCard(rows: 1)` shaped like the glance card, then the existing cards.

D3. Compact phone variants of the three source cards. Use the existing precedent: `PaymentsSummaryCard` already renders a one-line `CruCard` on phone when there are no dues (`CruCard` padding `fromLTRB(16,14,16,14)`, `MorphTag.text(id:'title')` for the title, trailing chevron).

- `VisitsCard` (visits_card.dart): when phone, render the same single-row card: "Visits" plus " · N" (N = `upcoming.length + past.length`), chevron, tap calls `onSeeAll`.
  - Drop the next and last rows, because the glance card now carries them.
  - Drop the recall row, which moved to the glance Next cell. Remove the `isDentist` and recall plumbing on phone only.
  - Keep the `MorphTag` ids ('title', and 'visit:<id>' only if still rendered; if no rows render on phone, nothing flies except the title).
- `PaymentsSummaryCard`: when phone, always render the single row.
  - "Payments · No dues" when there are no dues.
  - Otherwise "Payments · ₹X due" (value coloured `c.amberText`).
  - Tap calls `onSeeAll`. Remove the "Record" button on phone, since the glance Due cell is the quick action.
- `PatientFilesCard` (patient_files_card.dart): when phone and `!full`, render the single row "Files · N" with chevron. Drop the "+ add" on the Overview card; adding is inside the Files sub-screen. N is the existing count.
- All three keep `semanticLabel` and the keyed wrapper in `patient_details_view.dart`, so the MorphBox still grows from the row into the sub-screen.

D4. Bottom bar: restyle `_PatientDetailsBottomBar` to the main nav's blue pill.
- Read `lib/features/mobile/mobile_nav_bar.dart` for the pill decoration (blue gradient, radius, shadow, height `MobileMetrics.navHeight` 56).
  - If the decoration is private, extract it into a small shared `MobileNavPill` decoration builder in that file and use it both there and here. No new colours.
- Content:
  - Dentist and `canBook`: `Row[ icon-only circle (CruIcons.plus, size 40, semanticLabel 'New visit', tooltip 'New visit'), SizedBox(s8), Expanded( one filled capsule: DentalIcons.tooth + 'Open chart', semanticLabel 'Open chart' ) ]`.
    - The circle is a translucent white fill on the blue (inset-style secondary).
    - The capsule is white fill with `MobileBlue.neon` ink (the single primary action).
  - Dentist without `canBook`: only the Open chart capsule, full width.
  - Non-dentist with `canBook`: one full-width "New visit" capsule, same style.
  - `!canBook` and not a dentist: no bar (as today).
- Position and bottom scroll padding stay: `MobileMetrics.navBottom(context)` and `MobileMetrics.bottom(context)`.
- Hide while a sub-screen is open (as now).

D5. Tokens and rules checklist for the worker.
- Colours only via `context.cru` (`c.*`) and `mobileTone`. No hex literals.
- Spacing only 4-pt values (`CruSpace.s*`).
- Phone cards use `MobileCard` (radius 20, the phone language), the rest `CruCard` (24), matching neighbouring phone screens.
- Numbers use `.tabular`.
- Motion: only the identity fade, 200 ms, via `CruMotion`.
- Red is used only for the bezel, the dot and the allergy pill. Amber is for owed money and overdue recall. Green is for "Paid up" and done records. Ink Blue is only for the Next cell value, the Book plus and the primary capsule.

D6. Behaviour matrix.
- Dentist (clinical view): all of hero, glance card, Chart dock, history, 3 link rows, assigned doctors (if shown), and the pill with New visit and Open chart. No Clinical tab, as today.
- Physio or homeopath: hero, glance card, history, link rows. The Overview|Clinical switch is a pinned row under the bar. On the Clinical page the mini identity is always visible. The pill shows New visit only.
- Role without clinical view (reception): hero (no allergy or history), glance card (Last without the title caption), no Chart dock, no history, link rows Visits and Payments if billing (Files hidden if `!hasFiles`).
- `!canBill`: Due cell and the Payments row are hidden.
- `!canBook`: the Next cell loses its Book state and is plain text, and the pill hides New visit.

D7. Empty and edge states.
- New patient (no visits, no dues, no records): the glance card reads "— / Book / Paid up"; the Chart dock is hidden; the history card shows its own "Nothing recorded yet".
- No allergy info: no pill and no ring. Allergies recorded as none: the green outlined "No known allergies" pill and no ring.
- Very long name: two lines in the hero, ellipsis in the bar.
- No phone: the meta line is age and sex only.
- Evening mode: all tokens already switch, and the backdrop is shared.

D8. Verification (the owner is token-sensitive, so keep it light). Use the Flutter render harness (throwaway test with provider overrides, no login) to render three states at 390x844 in Day and Evening: allergic dentist with dock, new patient, and physio with the Clinical tab. Run `flutter analyze` on the touched files. Skip goldens.