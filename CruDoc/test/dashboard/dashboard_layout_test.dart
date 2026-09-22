import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dashboard/presentation/widgets/side_cards.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/up_next_card.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'dashboard_fixtures.dart';
import 'dashboard_harness.dart';

Future<void> _pumpAt(
  WidgetTester tester,
  Size size, {
  bool evening = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(dashboardApp(evening: evening));
  await tester.pump(); // stream providers deliver
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(loadGeist);

  const sizes = {
    1440: Size(1440, 1148),
    1280: Size(1280, 900),
    1024: Size(1024, 900),
    800: Size(800, 900),
  };

  for (final evening in [false, true]) {
    for (final entry in sizes.entries) {
      testWidgets(
          '${evening ? 'evening' : 'day'} at ${entry.key} px has no overflow',
          (tester) async {
        await _pumpAt(tester, entry.value, evening: evening);
        expect(tester.takeException(), isNull);
        expect(find.byType(UpNextCard), findsOneWidget);
        expect(find.text('Kavya Iyer').evaluate().isNotEmpty || evening, isTrue);
      });
    }
  }

  testWidgets('two columns at 1440 with a 384 px right column', (tester) async {
    await _pumpAt(tester, sizes[1440]!);
    final collections = tester.getRect(find.byType(CollectionsCard));
    final upNext = tester.getRect(find.byType(UpNextCard));
    expect(collections.width, CruSize.rightColumn);
    expect(collections.left, greaterThan(upNext.right));
    // Sidebar 248 + main left padding 12.
    expect(upNext.left, CruSize.sidebar + 12);
    expect(tester.getSize(find.byType(CruSidebar)).width, CruSize.sidebar);
  });

  testWidgets('right column drops below the main column under 1280',
      (tester) async {
    await _pumpAt(tester, sizes[1024]!);
    final collections = tester.getRect(find.byType(CollectionsCard));
    final upNext = tester.getRect(find.byType(UpNextCard));
    expect(collections.top, greaterThan(upNext.bottom));
  });

  testWidgets('sidebar collapses to icons under 960', (tester) async {
    await _pumpAt(tester, sizes[800]!);
    expect(tester.getSize(find.byType(CruSidebar)).width,
        CruSize.sidebarCollapsed);
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('no fabricated elements are rendered', (tester) async {
    await _pumpAt(tester, sizes[1440]!);
    for (final gap in [
      'Follow-ups due',
      'Alerts and vitals',
      'Insights',
      'CruDoc AI',
      'Allergic',
      'No known allergies',
      'UPI',
      'AI Smart Insights',
    ]) {
      expect(find.textContaining(gap), findsNothing, reason: gap);
    }
  });

  testWidgets('Day shows real values from the fixtures', (tester) async {
    await _pumpAt(tester, sizes[1440]!);
    expect(find.text('Good morning, Dr. Deshpande'), findsOneWidget);
    expect(find.text('Wednesday, 23 September'), findsOneWidget);
    expect(find.text('Token 7'), findsOneWidget);
    expect(find.text('Waiting 8 min'), findsOneWidget);
    expect(find.text('₹3,400'), findsOneWidget);
    expect(find.text('₹21,300'), findsOneWidget);
    expect(find.text('5 seen this morning'), findsOneWidget);
    expect(find.text('Evening session · 3 booked'), findsOneWidget);
    expect(find.text('Paracetamol 650 is low'), findsOneWidget);
    expect(find.text('Sanjeevani Clinic'), findsOneWidget);
    expect(find.text('Free trial · 12 days left'), findsOneWidget);
  });

  testWidgets('nobody waiting shows the neutral card, not an empty ink card',
      (tester) async {
    tester.view.physicalSize = sizes[1440]!;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(dashboardApp(evening: false, emptyQueue: true));
    await tester.pump(); // stream providers deliver
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(UpNextCard), findsNothing);
    expect(find.byType(NoOneWaitingCard), findsOneWidget);
    expect(find.text('No one waiting'), findsOneWidget);
    // Nobody checked in: the next future booking is Lakshmi at 12:30.
    expect(find.text('Next booking at 12:30 PM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
