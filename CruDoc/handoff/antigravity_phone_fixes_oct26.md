# Antigravity brief: phone fixes from the 26 Oct notes

Paste this whole file into Antigravity. It is a standalone brief.

## ▶ DO NOW

Do Tasks 1 to 9 in order, then run the Checks once at the end. Stop after the Checks and report.

## Rules (how to work)

- Work without pausing. Write every task first, then run all Checks once at the end.
- Change only the files named in each task. Do not rename, move or reformat anything else.
- Do not delete any file. Do not run `flutter run` or a release build. Do not commit.
- If a step doesn't match the code you see (a name or line is different), skip that step, write down what you saw, and carry on. A task-level "STOP" means: skip that part, note it, carry on.
- All paths are relative to the `CruDoc/` folder (the Flutter app).
- **Do not touch these files.** They hold unfinished work for a later job: `lib/features/appointments/presentation/appointments_screen.dart`, `lib/features/appointments/data/providers/appointments_providers.dart`, `test/appointments/appointments_swipe_shift_test.dart`, `handoff/antigravity_connect_restored_features.md`.
- UI rules: colours, text styles, radii and spacing come from the design tokens (`context.cru`, `MobileType`, `CruType`, `CruRadius`, `CruSpace`). No new `Color(0x…)`, no `Colors.red/green/orange`, no `fontSize:`. Motion: use `CruMotion.of(context, CruMotion.standard)` and `CruMotion.curve`.

---

## Task 1: Patient name first in appointment activity

File: `lib/features/mobile/activity/activity_feed.dart`

Change these title strings exactly. Use double quotes where the text has an apostrophe.

| Find | Replace with |
|---|---|
| `'Home visit booked for $who'` | `"$who's home visit booked"` |
| `'Appointment booked for $who'` | `"$who's appointment booked"` |
| `_ => 'Home visit with $who finished',` | `_ => "$who's home visit finished",` |
| `title: 'Consultation finished with $who',` | `title: "$who's consultation finished",` |

Leave `"$who's appointment was cancelled"` and `'$who missed their appointment'` as they are. They already start with the name.

## Task 2: No Google Maps link for clinic visits

File: `lib/features/appointments/presentation/schedule_visit_sheet.dart`

1. Find the block that starts `if (_selectedType == VisitType.home) ...[` (around line 375). It ends with a `],` line just before `const SizedBox(height: CruSpace.s16),`.
2. Right after that `],` are these lines:

```dart
            const SizedBox(height: CruSpace.s16),
            CruTextField(
              label: 'Google Maps link',
              optional: true,
              controller: _mapsLinkController,
              enabled: !_isSaving,
              keyboardType: TextInputType.url,
              hint: 'https://maps.google.com/...',
            ),
```

Cut them and paste them just before that `],`, so they sit inside the home-visit block. The field then shows only for home visits.

3. In the save code (around line 142), replace:

```dart
      mapsLink: _mapsLinkController.text.trim().isEmpty
          ? null
          : _mapsLinkController.text.trim(),
```

with:

```dart
      mapsLink:
          _selectedType != VisitType.home ||
              _mapsLinkController.text.trim().isEmpty
          ? null
          : _mapsLinkController.text.trim(),
```

Do not change `desktop_schedule_visit_dialog.dart`. It already shows the field only for home visits.

## Task 3: Schedule heading — month below "Schedule", and it follows week swipes

File: `lib/features/mobile/mobile_schedule.dart`

Two fixes in one edit:
- The month line moves under the "Schedule" title.
- Swiping the week strip to another week updates the month. Today it only follows the selected day.

Find (around line 246):

```dart
            overline: DateFormat(
              'MMMM y',
            ).format(_isMonthExpanded ? _monthDate : day),
```

Replace with:

```dart
            // The month of the week on screen: the selected day when it's
            // in view, else that week's Thursday (where most of it falls).
            subtitle: DateFormat('MMMM y').format(
              _isMonthExpanded
                  ? _monthDate
                  : _pageOf(day) == _page
                  ? day
                  : _weekStart(_page).add(const Duration(days: 3)),
            ),
```

Keep `title: 'Schedule'` and everything else in that `MobileHeader(...)` as is.

## Task 4: Show the duration on every Schedule row

File: `lib/features/mobile/mobile_schedule.dart`

Find (around line 1016):

```dart
        subtitle: [
          if (item.tokenNumber != null) 'Token ${item.tokenNumber}',
          if (item.isHomeVisit) 'Home visit',
          ?item.detailLine,
        ].join(' · ').ifEmpty(DashFormat.minutes(item.durationMinutes)),
```

Replace with:

```dart
        subtitle: [
          if (item.tokenNumber != null) 'Token ${item.tokenNumber}',
          if (item.durationMinutes > 0)
            DashFormat.minutes(item.durationMinutes),
          if (item.isHomeVisit) 'Home visit',
          ?item.detailLine,
        ].join(' · '),
```

If `flutter analyze` then says an import is unused in this file, remove only that import.

## Task 5: Notifications — no "You", time on the far right, same width on every row

**5a.** File: `lib/features/mobile/activity/activity_feed.dart`. In `actorName`, replace:

```dart
    if (i.actorUid == me) return 'You';
```

with:

```dart
    if (i.actorUid == me) return null;
```

Other team members' names still show.

**5b.** File: `lib/features/mobile/mobile_notifications.dart`, method `_row` (around line 178). Replace:

```dart
      subtitle: [?i.detail, ?actor, activityAgo(i.at, now)].join(' · '),
      trailing: unread ? const MobileUnreadDot() : null,
```

with:

```dart
      subtitle: [?i.detail, ?actor].isEmpty
          ? null
          : [?i.detail, ?actor].join(' · '),
      // Fixed-width dot and time columns so every row lines up.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            child: unread ? const Center(child: MobileUnreadDot()) : null,
          ),
          const SizedBox(width: CruSpace.s8),
          SizedBox(
            width: 64,
            child: Text(
              activityAgo(i.at, now),
              textAlign: TextAlign.right,
              maxLines: 1,
              style: MobileType.caption.tabular.tint(context.cru.label3),
            ),
          ),
        ],
      ),
```

## Task 6: Notifications — tap the picture for the patient, tap the row for the appointment

**6a.** File: `lib/features/mobile/activity/activity_feed.dart`, class `ActivityItem`.

1. Add `this.visit,` to the constructor, after `this.homeVisit = false,`.
2. Add this field after `final bool homeVisit;`:

```dart
  /// The appointment or home visit it's about; tapping the row opens it.
  final Visit? visit;
```

3. In the "Appointments and home visits" loop (around line 248), there are two `ActivityItem(` calls: one with `id: 'vb_${v.id}'` and one with `id: 'vs_${v.id}'`. Add `visit: v,` to both, after `homeVisit: home,`.

**6b.** File: `lib/features/mobile/mobile_notifications.dart`

1. Add these imports with the other `package:doctor_management_app/...` imports:

```dart
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/session_details_sheet.dart';
```

2. In `_row`, replace the `leading:` value:

```dart
      leading: i.showsPatient
          ? VisitBadged(
              avatar: MobileAvatar(name: p!.fullName, size: 38),
              avatarSize: 38,
              homeVisit: i.homeVisit,
            )
          : MobileIconTile(icon: icon, tone: tone),
```

with:

```dart
      leading: i.showsPatient
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openMobilePatient(context, p!),
              child: VisitBadged(
                avatar: MobileAvatar(name: p!.fullName, size: 38),
                avatarSize: 38,
                homeVisit: i.homeVisit,
              ),
            )
          : MobileIconTile(icon: icon, tone: tone),
```

3. In `_row`, replace the `onTap:` value:

```dart
      onTap: p != null
          ? () => openMobilePatient(context, p)
          : tab != null
```

with:

```dart
      onTap: i.visit != null && p != null
          ? () => showSessionDetailsSheet(
              context,
              VisitWithPatient(visit: i.visit!, patient: p),
            )
          : p != null
          ? () => openMobilePatient(context, p)
          : tab != null
```

Keep the rest of that `onTap` (the `openMobileDestination` part) as it is.

## Task 7: Recent activity cards change look as the work moves on

File: `lib/features/mobile/mobile_tasks.dart`, class `_RecentActivityCard`, method `build` (around line 1267).

The card's icon and colours come from where the task started (`t.source`). They should follow the step it's at now (`t.stage.source`). For example, a scan whose report is being written should show the report card, not the scan card.

Replace:

```dart
    final (icon, top, bottom) = switch (t.source) {
```

with:

```dart
    // The card looks like the work it's at now (a scan becomes a report
    // card once reading is done), not where the task started.
    final (icon, top, bottom) = switch (t.stage.source) {
```

Change nothing else in the card.

## Task 8: A shared swipe widget for screens with a switcher

File: `lib/features/mobile/mobile_kit.dart`

Add this widget directly after the whole `MobileSegmented` class (its closing `}`). `CruMotion` and `MobileHaptics` are already available in this file. If the analyzer can't find `CruMotion`, check that `package:doctor_management_app/shared/widgets/cru/cru.dart` is imported. If it can't find `TickerCanceled`, add `import 'package:flutter/scheduler.dart';` next to the other `package:flutter/` imports.

```dart
/// Swipe left or right over a screen's content to move to the next or
/// previous option of the switcher above it. The content follows the
/// finger; let go past a third of the width, or flick, and it slides off
/// while the next option's content slides in. At the first and last
/// option it drags with resistance and springs back.
class MobileSwipeSwitch<T> extends StatefulWidget {
  const MobileSwipeSwitch({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.child,
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final Widget child;

  @override
  State<MobileSwipeSwitch<T>> createState() => _MobileSwipeSwitchState<T>();
}

class _MobileSwipeSwitchState<T> extends State<MobileSwipeSwitch<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this);
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _motion,
    curve: CruMotion.curve,
  );
  double _dx = 0;
  double _width = 1;
  bool _busy = false;

  int get _index => widget.values.indexOf(widget.selected);
  bool get _enabled => widget.values.length > 1 && _index != -1;

  @override
  void dispose() {
    _curve.dispose();
    _motion.dispose();
    super.dispose();
  }

  Future<void> _slideTo(double target) async {
    final from = _dx;
    final d = CruMotion.of(context, CruMotion.standard);
    if (d == Duration.zero || from == target) {
      setState(() => _dx = target);
      return;
    }
    void tick() => setState(() => _dx = from + (target - from) * _curve.value);
    _motion
      ..duration = d
      ..addListener(tick);
    try {
      await _motion.forward(from: 0).orCancel;
    } on TickerCanceled {
      // A new drag took over.
    } finally {
      _motion.removeListener(tick);
    }
  }

  void _onDrag(DragUpdateDetails d) {
    if (_busy) return;
    _motion.stop();
    final i = _index;
    final pastEnd =
        (d.delta.dx > 0 && i == 0 && _dx >= 0) ||
        (d.delta.dx < 0 && i == widget.values.length - 1 && _dx <= 0);
    setState(() => _dx += pastEnd ? d.delta.dx * 0.25 : d.delta.dx);
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    if (_busy) return;
    final i = _index;
    final v = d.primaryVelocity ?? 0;
    final next =
        (_dx < -_width / 3 || v < -400) && i < widget.values.length - 1;
    final prev = !next && (_dx > _width / 3 || v > 400) && i > 0;
    if (!next && !prev) {
      await _slideTo(0);
      return;
    }
    _busy = true;
    final dir = next ? -1.0 : 1.0;
    MobileHaptics.tap();
    await _slideTo(dir * _width);
    if (!mounted) return;
    widget.onChanged(widget.values[i + (next ? 1 : -1)]);
    setState(() => _dx = -dir * _width);
    await _slideTo(0);
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth.isFinite
            ? box.maxWidth
            : MediaQuery.sizeOf(context).width;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: _enabled ? _onDrag : null,
          onHorizontalDragEnd: _enabled ? _onDragEnd : null,
          onHorizontalDragCancel: _enabled
              ? () {
                  if (!_busy) _slideTo(0);
                }
              : null,
          child: ClipRect(
            child: Transform.translate(
              offset: Offset(_dx, 0),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}
```

## Task 9: Make every phone screen with a switcher swipeable

Use `MobileSwipeSwitch` from Task 8. Do not change the Schedule screen (`mobile_schedule.dart`) in this task. In each screen below, wrap only the content **below** the switcher, never the header or the switcher itself. If the content you need to wrap is slivers (`SliverList`, `SliverToBoxAdapter` inside a `CustomScrollView`) and not plain widgets, STOP for that screen.

**9a. Invoices** — `lib/features/mobile/mobile_invoices.dart`

The `MobileSegmented<String>(...)` is around line 145, followed by `const SizedBox(height: CruSpace.s16),`. Take every widget that comes after that `SizedBox` in the same `children:` list (the empty state or the invoice rows) and put them into one widget:

```dart
              MobileSwipeSwitch<String>(
                values: _filters,
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ← the widgets that were after the SizedBox go here,
                    //   unchanged (keep their `if` / `else` / `for`).
                  ],
                ),
              ),
```

**9b. Revenue** — `lib/features/mobile/mobile_revenue.dart`

The `MobileSegmented<RevenuePeriod>(...)` is around line 153. Wrap the widgets that come after it in the same `children:` list the same way:

```dart
      MobileSwipeSwitch<RevenuePeriod>(
        values: RevenuePeriod.values,
        selected: view.period,
        onChanged: (p) =>
            ref.read(revenueViewControllerProvider.notifier).setPeriod(p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ← the widgets that were after the switcher go here, unchanged.
          ],
        ),
      ),
```

If the switcher is built in a separate method from the content below it, STOP for this screen.

**9c. Tasks** — `lib/features/mobile/mobile_tasks.dart`

The source chips row is around line 947: `if (availableSources.length > 2) ...[ SingleChildScrollView(... MobileChip ...), const SizedBox(height: CruSpace.s12), ],`. Take every widget that comes after that block inside the same `else ...[ ... ]` (the Recent activity strip, search and the task list) and wrap them:

```dart
          MobileSwipeSwitch<TaskSourceFilter>(
            values: availableSources.length > 2
                ? availableSources
                : const <TaskSourceFilter>[],
            selected: effectiveSource,
            onChanged: (s) => setState(() {
              _sourceFilter = s;
              _statusFilter = TaskStatusFilter.any;
            }),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ← the widgets that were after the chips block go here,
                //   unchanged.
              ],
            ),
          ),
```

**9d. Referrals / Referrers** — `lib/features/mobile/mobile_more.dart`, class `_PageHubState` (around line 662)

This one switches whole pages, so use a `PageView` here, not `MobileSwipeSwitch`.

1. Under `int _tab = 0;` add:

```dart
  final _pages = PageController();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }
```

2. In the `MobileSegmented<int>(...)`, replace `onChanged: (i) => setState(() => _tab = i),` with:

```dart
            onChanged: (i) {
              setState(() => _tab = i);
              final d = CruMotion.of(context, CruMotion.standard);
              if (d == Duration.zero) {
                _pages.jumpToPage(i);
              } else {
                _pages.animateToPage(i, duration: d, curve: CruMotion.curve);
              }
            },
```

3. Replace:

```dart
          child: IndexedStack(
            index: _tab,
            children: [for (final p in widget.pages) p.$2],
          ),
```

with:

```dart
          child: PageView(
            controller: _pages,
            onPageChanged: (i) => setState(() => _tab = i),
            children: [
              for (final p in widget.pages) MobileKeepAlive(child: p.$2),
            ],
          ),
```

---

## Checks (run once, after all tasks)

1. Format only the files you changed:

```
dart format lib/features/mobile/activity/activity_feed.dart lib/features/mobile/mobile_notifications.dart lib/features/mobile/mobile_schedule.dart lib/features/mobile/mobile_tasks.dart lib/features/mobile/mobile_kit.dart lib/features/mobile/mobile_invoices.dart lib/features/mobile/mobile_revenue.dart lib/features/mobile/mobile_more.dart lib/features/appointments/presentation/schedule_visit_sheet.dart
```

2. Analyze:

```
flutter analyze lib/features/mobile lib/features/appointments/presentation/schedule_visit_sheet.dart lib/features/dashboard/presentation/widgets/notifications_panel.dart
```

Fix every error and warning in the files you changed. Ignore problems in files you didn't touch.

3. Do not write or run tests for this job.

## Report

For each task 1–9: done, or skipped plus what you saw. List every file you changed.
