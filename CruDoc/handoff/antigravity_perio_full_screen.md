# Antigravity brief: Perio button opens the perio chart full screen

Paste this whole file into Antigravity. It is a standalone brief.

## ▶ DO NOW

Do Task 1 to Task 4 in order, then run the Check once at the end. Stop after the Check and report.

## Rules (how to work)

- Work without pausing. Write every task first, then run the Check once at the end.
- Change only the files named below. Do not rename, move or reformat anything else.
- Do not run `flutter run`, tests or a release build. Do not commit.
- If a step doesn't match the code you see (a name or line is different), skip that step, write down what you saw, and carry on.
- All paths are relative to the `CruDoc/` folder (the Flutter app).

## Background

Desktop **Charting** screen (`lib/features/dental/presentation/desktop/charting_screen.dart`). On the right, the **Clinical records** card has a **Perio** button.

**Already done (by Claude, don't redo):** Perio is no longer a tab in the top switch (`tabs` skips `ChartingTab.perio`, its `workspace` case is `SizedBox.shrink()`). Root planing opens its own dialog. The tooth chart's "Start perio exam" button is gone. Right now the Perio button does nothing; that's what you fix. The `perio_chart_screen.dart` import in `charting_screen.dart` is unused until your Task 4 uses it again; leave it.

The **only** way to open perio is the Perio button. It opens the perio chart **full screen**:

- The app's left sidebar goes to its **collapsed** (icon-only) mode while perio is open, and comes back as it was after.
- The **"Charting" title** and the **patient line under it** stay exactly where they are. They must not move.
- **Everything else goes**: the DMFT/allergy pills, the "Switch patient" search, the Recall chip, the workspace tabs (Chart, Plan, Perio…), the left cards, the tooth chart, the right cards. The perio chart fills all the space under the title.
- A close button (X) appears at the right end of the title row, where Recall was. It folds perio back.

**Animation (our guideline, `design/motion-transitions.md`, "Opening from a button"):** the Perio button's own box grows on all four sides into the full perio area while the button's icon fades out; the perio chart fades in once the box is mostly open. Closing is the same motion backwards: it shrinks back into the Perio button. 250 ms, `CruMotion.curve` (easeOutCubic), no bounce. We already have the helper for this: `MorphBox` in `lib/shared/widgets/morph_tag.dart`. Patient details uses it the same way (`lib/features/patients/presentation/patient_details_view.dart`, `_openSub` / `_close` / `MorphBox(`); look there if you need an example.

Other screens can still open Charting "on Perio" (`openCharting(..., tab: ChartingTab.perio)` from tooth details and the perio patients list). Then Charting starts on the chart and opens perio full screen straight away (Task 3). The phone layout (width < 600) is not touched.

---

## Task 1: a "focus" flag that collapses the sidebar

File: `lib/features/dashboard/presentation/dashboard_actions.dart`

Find:

```dart
/// The tab the desktop shell is showing.
final shellCurrentTabProvider = StateProvider<int>(
  (ref) => DesktopTab.dashboard,
);
```

Add right after it:

```dart

/// A screen has opened something full screen (Charting's perio chart):
/// the sidebar shows collapsed until it closes. Never saved.
final shellFocusProvider = StateProvider<bool>((ref) => false);
```

File: `lib/features/shell/presentation/desktop_shell.dart` (around line 554)

Find:

```dart
        final collapsed = forcedCompact || !_isSidebarExpanded;
```

Replace with:

```dart
        final collapsed =
            forcedCompact ||
            !_isSidebarExpanded ||
            ref.watch(shellFocusProvider);
```

(`dashboard_actions.dart` is already imported there because the file uses `shellCurrentTabProvider`.) The sidebar already animates its width when `collapsed` changes, so nothing else is needed. Do not touch `_isSidebarExpanded` or the saved preference.

---

## Task 2: a key on the Perio button, and make the tile public

File: `lib/features/dental/presentation/desktop/charting_records.dart`

(The Perio record there still calls `go(ChartingTab.perio)`. Leave it; Task 3 makes `_go` open perio full screen.)

**2a.** Rename the private class `_PanelTile` to `RecordPanelTile` (3 places: the class name, its constructor, and the one use inside `RecordPanel`). Add this doc line above the class if it has none: `/// One button in the Clinical records card (also drawn inside Perio's growing box).`

**2b.** Give `RecordPanel` an optional key for the Perio button. Find:

```dart
class RecordPanel extends StatelessWidget {
  const RecordPanel({super.key, required this.clusters});

  final List<RecordCluster> clusters;
```

Replace with:

```dart
class RecordPanel extends StatelessWidget {
  const RecordPanel({super.key, required this.clusters, this.perioKey});

  final List<RecordCluster> clusters;

  /// On the Perio button, so Charting can grow the perio chart from it.
  final GlobalKey? perioKey;
```

**2c.** In `RecordPanel.build`, find:

```dart
                    for (final r in clusters[i].records)
                      SizedBox(
                        width: each,
                        child: _PanelTile(record: r),
                      ),
```

Replace with:

```dart
                    for (final r in clusters[i].records)
                      SizedBox(
                        key: r.id == 'perio' ? perioKey : null,
                        width: each,
                        child: RecordPanelTile(record: r),
                      ),
```

---

## Task 3: open/close state in Charting

File: `lib/features/dental/presentation/desktop/charting_screen.dart`

**3a. Imports.** Add these four imports at the top of the file, next to the matching existing ones (skip any that is already there):

```dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/shared/widgets/morph_tag.dart';
```

(`legacy.dart` is where Riverpod 3 keeps `StateController`; `services.dart` gives `LogicalKeyboardKey` for Esc.)

**3b.** Find this line:

```dart
class _ChartingScreenState extends ConsumerState<ChartingScreen> {
```

Replace it with the code below (the fields that follow it in the file, `_tab`, `_built` and `_go`, stay; 3c changes `_go`):

```dart
class _ChartingScreenState extends ConsumerState<ChartingScreen>
    with SingleTickerProviderStateMixin {
  /// Perio full screen, opened from the Clinical records Perio button:
  /// the button's box grows over everything under the title
  /// (design/motion-transitions.md, "Opening from a button").
  late final AnimationController _morph = AnimationController(vsync: this);
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _morph,
    curve: CruMotion.curve,
    reverseCurve: CruMotion.curve.flipped,
  );
  late final StateController<bool> _shellFocus;

  /// Everything under the title row; perio fills it.
  final GlobalKey _area = GlobalKey(debugLabel: 'charting area');
  final GlobalKey _perioTile = GlobalKey(debugLabel: 'perio button');
  bool _perio = false;

  /// The Perio button's rectangle in [_area] when perio opened.
  Rect? _from;

  @override
  void initState() {
    super.initState();
    _shellFocus = ref.read(shellFocusProvider.notifier);
    _morph.addStatusListener((_) {
      if (mounted) setState(() {});
    });
    // Opened "on Perio" from another screen: open it full screen once
    // the Perio button is laid out, so it grows from there.
    if (widget.initialTab == ChartingTab.perio) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPerio();
      });
    }
  }

  @override
  void dispose() {
    // Left Charting with perio open: give the sidebar back.
    if (_perio) {
      final focus = _shellFocus;
      Future.microtask(() => focus.state = false);
    }
    _t.dispose();
    _morph.dispose();
    super.dispose();
  }

  Rect? _tileRect() {
    final tile = _perioTile.currentContext?.findRenderObject();
    final area = _area.currentContext?.findRenderObject();
    if (tile is! RenderBox || area is! RenderBox || !tile.hasSize) return null;
    return tile.localToGlobal(Offset.zero, ancestor: area) & tile.size;
  }

  void _openPerio() {
    if (_perio) return;
    setState(() {
      _perio = true;
      _from = _tileRect();
    });
    _shellFocus.state = true;
    _morph.duration = CruMotion.of(context);
    _morph.forward(from: 0);
  }

  Future<void> _closePerio() async {
    if (!_perio || _morph.status == AnimationStatus.reverse) return;
    // Fold back while the sidebar is still collapsed, so the button is
    // where it was measured; then give the sidebar back.
    _from = _tileRect() ?? _from;
    _morph.duration = CruMotion.of(context);
    await _morph.reverse();
    if (!mounted) return;
    setState(() => _perio = false);
    _shellFocus.state = false;
  }
```

**3c.** A little further down, find:

```dart
  void _go(ChartingTab tab) => setState(() {
    _tab = tab;
    _built.add(tab);
  });
```

Replace with:

```dart
  void _go(ChartingTab tab) {
    // Perio isn't a tab: its button opens it full screen.
    if (tab == ChartingTab.perio) return _openPerio();
    setState(() {
      _tab = tab;
      _built.add(tab);
    });
  }
```

**3d.** In `build`, find:

```dart
    final records = chartRecords(context, ref, p, go: _go);
```

Add this line right after it:

```dart
    final perioRecord = findRecord(records, 'perio');
```

**3e.** Find:

```dart
      RecordPanel(clusters: records),
```

Replace with:

```dart
      RecordPanel(clusters: records, perioKey: _perioTile),
```

---

## Task 4: the layout (header fades, perio grows)

Same file, `charting_screen.dart`, inside `build`.

**4a. Title row (desktop only).** In the `else` branch that builds `topRow = Row(...)` (the comment above it starts with `// Like every page header`), everything after the title column must fade out, and the X fades in at the right end. The title column (`ConstrainedBox(maxWidth: 420, ...)`) stays exactly as it is.

Find this part of that `Row`'s children (it comes right after the `ConstrainedBox(...)` title column):

```dart
          const SizedBox(width: CruSpace.s20),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final w in pills) ...[
                    w,
                    const SizedBox(width: CruSpace.s6),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          if (widget.picker != null) ...[
            SizedBox(width: 300, child: widget.picker),
            const SizedBox(width: CruSpace.s10),
          ],
          _RecallChip(patient: p),
        ],
      );
```

Replace with:

```dart
          Expanded(
            child: Stack(
              alignment: Alignment.centerRight,
              children: [
                // Pills, search and recall fade while perio is open.
                AnimatedBuilder(
                  animation: _t,
                  builder: (context, child) => Opacity(
                    opacity:
                        1 - const Interval(0, 0.5).transform(_t.value),
                    child: child,
                  ),
                  child: IgnorePointer(
                    ignoring: _perio,
                    child: ExcludeFocus(
                      excluding: _perio,
                      child: Row(
                        children: [
                          const SizedBox(width: CruSpace.s20),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final w in pills) ...[
                                    w,
                                    const SizedBox(width: CruSpace.s6),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: CruSpace.s12),
                          if (widget.picker != null) ...[
                            SizedBox(width: 300, child: widget.picker),
                            const SizedBox(width: CruSpace.s10),
                          ],
                          _RecallChip(patient: p),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_perio)
                  AnimatedBuilder(
                    animation: _t,
                    builder: (context, child) => Opacity(
                      opacity: const Interval(0.5, 1).transform(_t.value),
                      child: child,
                    ),
                    child: CruIconButton(
                      icon: CruIcons.close,
                      semanticLabel: 'Close perio chart',
                      tooltip: 'Close',
                      onPressed: _closePerio,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
```

**4b. The area under the title.** Find the whole `final body = Column(...)` block:

```dart
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            topRow,
            const SizedBox(height: CruSpace.s12),
            switcher,
```

…down to its end:

```dart
          ],
        );
        return body;
```

Replace that whole block with the code below. The middle part (`Expanded(child: Row(...))` with `pool`, `centre`, `inspector`) is copied unchanged from the old block; it just moves inside `below`.

```dart
        // Everything under the title row: tabs, shelf, the three columns.
        final below = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            switcher,
            // Below the inspector's width the buttons stay on top.
            if (!studio) ...[
              const SizedBox(height: CruSpace.s10),
              RecordShelf(clusters: records),
            ],
            const SizedBox(height: CruSpace.s16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide) ...[
                    SizedBox(width: 280, child: scroll(pool)),
                    const SizedBox(width: CruSpace.cardGap),
                  ],
                  Expanded(child: centre),
                  if (studio) ...[
                    const SizedBox(width: CruSpace.cardGap),
                    SizedBox(width: 300, child: scroll(inspector)),
                  ],
                ],
              ),
            ),
          ],
        );

        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            topRow,
            const SizedBox(height: CruSpace.s12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, areaBox) {
                  final area = Offset.zero & areaBox.biggest;
                  return Stack(
                    key: _area,
                    children: [
                      // The studio fades out as perio grows over it. It
                      // stays built, so scroll and workspaces survive.
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _t,
                          builder: (context, child) => Opacity(
                            opacity:
                                1 - const Interval(0, 0.5).transform(_t.value),
                            child: child,
                          ),
                          child: IgnorePointer(
                            ignoring: _perio,
                            child: ExcludeFocus(
                              excluding: _perio,
                              child: below,
                            ),
                          ),
                        ),
                      ),
                      // Perio, growing out of the Perio button.
                      if (_perio)
                        AnimatedBuilder(
                          animation: _t,
                          builder: (context, child) => MorphBox(
                            t: _t.value,
                            from: _from,
                            fromRadius: CruRadius.control,
                            area: area,
                            settled: _morph.isCompleted,
                            source: perioRecord == null
                                ? const SizedBox.shrink()
                                : RecordPanelTile(record: perioRecord),
                            child: child!,
                          ),
                          child: CallbackShortcuts(
                            bindings: {
                              const SingleActivator(LogicalKeyboardKey.escape):
                                  _closePerio,
                            },
                            child: PerioChartScreen(
                              patient: p,
                              embedded: true,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
        return body;
```

Note: on narrow windows (< 1000 px wide) the Clinical records card isn't on screen, so `_from` is null and `MorphBox` opens from the middle. That is expected.

---

## Check (once, at the end)

Run from `CruDoc/`:

```
flutter analyze lib/features/dental/presentation/desktop/charting_screen.dart lib/features/dental/presentation/desktop/charting_records.dart lib/features/shell/presentation/desktop_shell.dart lib/features/dashboard/presentation/dashboard_actions.dart
```

Fix any errors and warnings it shows in these files. Then stop and report:

1. Which tasks you did, and any step you skipped (with what you saw instead).
2. The final `flutter analyze` output.

Do not run the app. The user will check it on the PC: open Charting on a patient, click **Perio** in Clinical records. Expected: the sidebar collapses, the Perio button's box grows to fill everything under "Charting" + the patient line (those two never move), pills/search/Recall/tabs/cards fade away, an X appears at the right of the title row. X or Esc shrinks perio back into the Perio button, then the sidebar returns to how it was.
