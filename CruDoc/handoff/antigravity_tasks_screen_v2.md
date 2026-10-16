# Antigravity brief: Tasks screen v2 (PHONE ONLY)

Edit only:
- `CruDoc/lib/features/mobile/mobile_tasks.dart`
- `CruDoc/lib/features/mobile/tasks/tasks_logic.dart`

Do not touch desktop screens, `mobile_shell.dart`, `mobile_more.dart`, or any radiology/dental file. Only call their public functions.

Follow `CruDoc/.claude/rules/crudoc-ui.md`: design tokens only, motion 200–250 ms easeOutCubic, tabular figures, no fabricated data.

---

## Target layout (top to bottom, one ListView)

1. `MobileHeader('Tasks')` with the + button (see §5).
2. **Pill row**: the source filter.
3. **4 glance boxes** for the selected pill.
4. **Search bar with a filter icon** (status/time filters).
5. **One flat list** of every matching item, one below another. No bucket headers.

Remove completely:
- the "Full lists" box at the bottom
- the "Next to read" card
- the Overdue / Due today / Coming up / No deadline section headers, and the stage chip row

Keep the `TaskBucket` logic only if the time filter (§3) uses it. Otherwise delete it.

---

## 1. Pill row: source filter

```dart
enum TaskSourceFilter { all, worklist, reports, plans }
```

Labels: **All · Worklist · Reports · Treatment plans**. Each pill shows its count.
- Worklist = stages `toRead` and `reading`.
- Reports = `drafting`, `toSign`, `toSend`.
- Treatment plans = `awaitingOk` and `toTreat`.

Show a pill only if its source is on for this doctor (the same gating as now: radiology via `DesktopTab.worklist`/`DesktopTab.reports` in `sidebarTabs`, plans via `DesktopTab.treatmentPlans`). If only one source is on, hide the whole pill row and treat that source as selected.

Use `MobileChip(label:, selected:, onTap:, count:)` in a horizontal scroll row, like the Patients tab. Call `MobileHaptics.select()` on change. Changing the pill resets the status filter (§3) to "Any".

---

## 2. Four glance boxes (change with the pill)

A row of 4 small equal boxes. Lay them out like Home's `_Glance` tiles in `mobile_home.dart`: `MobileCard`, a caption label, a big tabular value and a small caption. Use 2×2 if the phone is narrower than 360 dp, otherwise 4 in a row (keep the text from overflowing; scale with `FittedBox`). Tapping a box applies the matching status filter (§3) when one exists.

Copy the exact numbers from the desktop pages:

**Worklist** (from `worklist_screen.dart`, the GlanceStrip around line 210):
1. **To read**: studies with status `newStudy` or `reading`. Caption: 'Oldest <ago>' using `RadFormat.ago(oldest receivedAt, now)`, or 'All caught up'. Tap → status "To read".
2. **Urgent & STAT**: open studies (`status.isOpen`) whose priority is not routine. Caption: 'Waiting for a report' / 'None waiting'. Tap → "Urgent".
3. **Overdue**: open studies where `study.isOverdue(now)`. Caption: 'Past due time' / 'On time'. Tap → "Overdue".
4. **Signed today**: copy the `signedToday` count the worklist computes. Caption: 'Reports signed'. No tap.

**Reports** (from `reports_screen.dart`, around lines 60–80 and 150–175). The data is studies; map them like this:
1. **Drafts**: status `draft`. Tap → "Drafting".
2. **Awaiting signature**: status `preliminary`. Tap → "To sign".
3. **Signed this week**: copy the reports screen's `signedWeek` logic. If you need reports, use `ref.watch(radReportsProvider)` (`RadReport.signedAt`), with `weekStart` computed the same way that screen does.
4. **Sent this week**: the same, with `sharedAt`.

**Treatment plans** (from `treatment_plans_screen.dart`, around lines 200–235; counts are items, values are rupees via `DashFormat.rupees`):
1. **Awaiting a yes**: sum of `estimatedPrice` of proposed items; caption 'N procedures proposed'. Tap → "Awaiting".
2. **Accepted**: sum of accepted items; caption 'N to do'. Tap → "Accepted".
3. **Invoiced**: sum of invoiced items; caption 'N done'. Tap → "Invoiced".
4. **Acceptance**: `(accepted + invoiced) * 100 / (accepted + invoiced + declined)` %, or '—'; caption 'of N decided'.

**All**:
1. **To do**: count of all tasks.
2. **Overdue**: tasks whose `isOverdue(now)`.
3. **Urgent**: critical or STAT/urgent.
4. **Done today**: the board's `doneToday`.

Amber tone for a value > 0 only on 'Overdue' and 'Awaiting a yes'. Everything else uses the normal label colour.

**Important:** "Invoiced" and "Signed"/"Sent" items are **not tasks** today. To make the Invoiced filter work, the board must now also keep **finished items** in a separate list: `TaskBoard.finished`, which holds delivered studies and invoiced/declined plan items grouped per patient. Show finished items only when a status filter explicitly asks for them (§3).

---

## 3. Search bar with a filter icon

Put a filter icon button at the right end of `MobileSearchField`, or immediately right of it in the same row (`CruIcons` has a filter/sliders glyph; More uses `CruIcons.settings`, so look for `filter`/`sliders` in `crudoc_shared/lib/widgets/cru/cru_icons.dart`). When a status filter other than "Any" is active, the icon shows a small dot and the active filter appears as a removable chip under the search bar.

Tapping the icon opens `showMobileActionSheet` (or a small bottom sheet) with two groups. The options depend on the selected pill:

**Time** (every pill): Any time · Overdue · Due today · This week · No deadline.
- Overdue = `isOverdue(now)`.
- Due today = `dueAt` is today.
- This week = `dueAt` within the next 7 days.
- No deadline = `dueAt == null`.

**Status**, by pill:
- **All**: Any · Open · Urgent.
- **Worklist**: Any · To read · Reading · Urgent.
- **Reports**: Any · Drafting · To sign · To send · Sent (finished, `delivered`).
- **Treatment plans**: Any · Open (proposed + accepted) · Awaiting (proposed) · Accepted · Invoiced (finished) · Declined (finished).

State:
```dart
enum TaskTimeFilter { any, overdue, today, week, noDeadline }
enum TaskStatusFilter { any, open, urgent, toRead, reading, drafting, toSign, toSend, sent, awaiting, accepted, invoiced, declined }
```

Put the matching functions in `tasks_logic.dart`.

Search keeps working as now: every query word must appear in `searchText`. Hint: 'Search patient, scan, procedure or referrer'.

---

## 4. The list

One flat `MobileRowGroup` with no title. It holds every item that passes pill + status + time + search, sorted by `compareUrgency`. Finished items, when shown, sort newest first.

Row: keep the current row design (source icon tile, patient name, title · detail · time, stage pill, 'Step x of y', critical pill, tap = next step, long-press = action sheet). Finished rows show a green pill ('Sent' / 'Invoiced'), or a slate one ('Declined'), with no step text. Tap a finished study → `openRadReport`; a finished plan → `showTreatmentPlanDialog`.

Empty states stay as now: nothing on → 'No tasks here yet'; no items → 'All caught up'; filtered out → 'No matches' with a 'Clear filters' link that resets the search, status and time.

---

## 5. The + button sheet

The actions, each shown only when its source is on:
- Import scans: radiology, `runRadImport(context, ref)`.
- Capture RVG: radiology, `showRvgCaptureDialog(mobileRoot(context))`.
- **New template**: radiology, `showRadTemplateManager(mobileRoot(context))` from `lib/features/radiology/presentation/reports/template_manager.dart`.
- **New phrase**: radiology, `showRadPhraseLibrary(mobileRoot(context))` from `lib/features/radiology/presentation/reports/phrase_library.dart`.
- New treatment plan: dental, the patient picker then `showTreatmentPlanDialog` (as now).

---

## 6. Finish

1. Run `flutter analyze lib/features/mobile` and fix every error and warning in your two files.
2. Report any function or provider name in this brief that turned out different, and what you used instead.
