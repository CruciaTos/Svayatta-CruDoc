import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What the row saw.
class _Log {
  final events = <String>[];
}

MobileSwipeAction _swipe(_Log log, String name) => MobileSwipeAction(
  label: name,
  icon: CruIcons.phone,
  tone: MobileTone.green,
  onCommit: () async => log.events.add(name),
);

/// A patient row on the middle of three tab pages, like the phone shell.
Future<PageController> _pump(
  WidgetTester tester,
  _Log log, {
  bool right = true,
  bool left = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  // Android's own touch slop (8 dp), which the tab pager picks up. Lower
  // than Flutter's default, so a row that ignores it loses every swipe.
  tester.view.gestureSettings = const ui.GestureSettings(
    physicalTouchSlop: 8 * 2.625,
  );
  addTearDown(tester.view.reset);
  final pages = PageController(initialPage: 1);
  addTearDown(pages.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: CruTheme.day(),
      home: Scaffold(
        body: PageView(
          controller: pages,
          children: [
            const SizedBox.expand(),
            Center(
              child: MobileSwipeRow(
                action: right ? _swipe(log, 'call') : null,
                leftAction: left ? _swipe(log, 'book') : null,
                child: MobileRow(
                  title: 'Asha Patil',
                  onTap: () => log.events.add('open'),
                  onLongPress: () => log.events.add('actions'),
                ),
              ),
            ),
            const SizedBox.expand(),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  return pages;
}

Finder get _row => find.text('Asha Patil');

/// Drags like a finger: small steps, so whichever recognizer's slop is
/// smallest gets the first claim (a single big jump would hide that).
Future<void> _fingerDrag(WidgetTester tester, double dx) async {
  final g = await tester.startGesture(tester.getCenter(_row));
  final step = dx.sign * 3;
  for (var moved = 0.0; moved.abs() < dx.abs(); moved += step) {
    await g.moveBy(Offset(step, 0));
    await tester.pump(const Duration(milliseconds: 8));
  }
  await g.up();
}

void main() {
  testWidgets('a single tap opens the patient', (tester) async {
    final log = _Log();
    await _pump(tester, log);
    await tester.tap(_row);
    // Opens straight away: no waiting for a second tap.
    await tester.pump();
    expect(log.events, ['open']);
  });

  testWidgets('a long press opens the actions', (tester) async {
    final log = _Log();
    await _pump(tester, log);
    await tester.longPress(_row);
    await tester.pumpAndSettle();
    expect(log.events, ['actions']);
  });

  testWidgets('swipe right runs the right action and keeps the tab', (
    tester,
  ) async {
    final log = _Log();
    final pages = await _pump(tester, log);
    await _fingerDrag(tester, 160);
    await tester.pumpAndSettle();
    expect(log.events, ['call']);
    expect(pages.page, 1);
  });

  testWidgets('swipe left runs the left action and keeps the tab', (
    tester,
  ) async {
    final log = _Log();
    final pages = await _pump(tester, log);
    await _fingerDrag(tester, -160);
    await tester.pumpAndSettle();
    expect(log.events, ['book']);
    expect(pages.page, 1);
  });

  testWidgets('a short swipe springs back and does nothing', (tester) async {
    final log = _Log();
    await _pump(tester, log);
    await _fingerDrag(tester, 60);
    await tester.pumpAndSettle();
    expect(log.events, isEmpty);
    // Back in place: the row's left edge is the page's.
    expect(tester.getTopLeft(find.byType(MobileRow)).dx, 0);
  });

  testWidgets('a direction with no action still changes the tab', (
    tester,
  ) async {
    final log = _Log();
    final pages = await _pump(tester, log, left: false);
    await tester.fling(_row, const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(log.events, isEmpty);
    expect(pages.page, 2);
  });
}
