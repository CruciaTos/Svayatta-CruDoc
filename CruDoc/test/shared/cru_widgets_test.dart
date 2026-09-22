import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

Widget _host(Widget child, {CruAppearance appearance = CruAppearance.day}) {
  return MaterialApp(
    theme: CruTheme.of(appearance),
    home: Scaffold(body: Center(child: child)),
  );
}

const _allIcons = [
  CruIcons.plus, CruIcons.chevronsUpDown, CruIcons.chevronDown,
  CruIcons.chevronLeft, CruIcons.chevronRight, CruIcons.dashboard,
  CruIcons.queue, CruIcons.calendar, CruIcons.patients, CruIcons.mic,
  CruIcons.box, CruIcons.rupee, CruIcons.megaphone, CruIcons.search,
  CruIcons.userPlus, CruIcons.clock, CruIcons.warning, CruIcons.check,
  CruIcons.more, CruIcons.flask, CruIcons.phone, CruIcons.sparkle,
  CruIcons.moon, CruIcons.sun, CruIcons.pen, CruIcons.wallet,
  CruIcons.arrowUp, CruIcons.arrowDown, CruIcons.settings, CruIcons.help,
  CruIcons.logout, CruIcons.sidebar, CruIcons.autoMode,
];

void main() {
  group('parseSvgPath', () {
    test('parses every icon in the set', () {
      for (final icon in _allIcons) {
        if (icon.path.isEmpty) continue;
        // Sample the drawn outline (getBounds includes curve control
        // points, which overshoot on large arcs).
        for (final metric in parseSvgPath(icon.path).computeMetrics()) {
          for (var d = 0.0; d <= metric.length; d += 0.25) {
            final p = metric.getTangentForOffset(d)!.position;
            expect(p.dx, inInclusiveRange(-0.01, 24.01), reason: icon.path);
            expect(p.dy, inInclusiveRange(-0.01, 24.01), reason: icon.path);
          }
        }
      }
    });

    test('handles relative commands, implicit line-tos and arcs', () {
      final p = parseSvgPath('m8 9 4-4 4 4');
      expect(p.getBounds(), const Rect.fromLTRB(8, 5, 16, 9));
      final arc = parseSvgPath('M16 4.6a3.5 3.5 0 0 1 0 6.8');
      expect(arc.getBounds().right, greaterThan(16));
    });
  });

  group('shared widgets', () {
    for (final appearance in CruAppearance.values) {
      testWidgets('render in ${appearance.name}', (tester) async {
        await tester.pumpWidget(_host(
          appearance: appearance,
          SingleChildScrollView(
            child: Column(
              children: [
                CruCard(child: Wrap(children: [
                  for (final i in _allIcons) CruIcon(i),
                ])),
                CruInkCard(
                  child: Row(children: [
                    const CruMonogram(name: 'Kavya Iyer', size: 56),
                    CruButton(label: 'Start', onPressed: () {}, large: true),
                    const CruChip(label: 'BP', value: '118/76'),
                  ]),
                ),
                const CruProgressRing(value: 5 / 13),
                const Row(children: [
                  CruStatusDot(CruDotKind.now),
                  CruStatusDot(CruDotKind.waiting),
                  CruStatusDot(CruDotKind.booked),
                  CruStatusDot(CruDotKind.done),
                ]),
                const CruIconTile(icon: CruIcons.flask, tone: CruTileTone.teal),
                const CruDoneBadge(),
                const CruKeycap('Ctrl K'),
                CruCapsuleButton(label: 'Review', onPressed: () {}),
                CruButton(
                  label: 'Close the day',
                  kind: CruButtonKind.tinted,
                  expand: true,
                  large: true,
                  onPressed: () {},
                ),
                const CruSeparator(indent: 60),
              ],
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('ink card scopes the on-ink colours', (tester) async {
      late CruColors inside;
      await tester.pumpWidget(_host(CruInkCard(
        child: Builder(builder: (context) {
          inside = context.cru;
          return const SizedBox();
        }),
      )));
      expect(inside.label, const Color(0xFFFFFFFF));
      expect(inside.primaryButtonFill, const Color(0xFFFFFFFF));
      expect(inside.primaryButtonText, CruColors.day.ink);
    });

    testWidgets('buttons respond to tap and keyboard', (tester) async {
      var taps = 0;
      final focus = FocusNode();
      await tester.pumpWidget(_host(CruPressable(
        onTap: () => taps++,
        focusNode: focus,
        builder: (_, _) => const SizedBox(width: 80, height: 40),
      )));
      await tester.tap(find.byType(CruPressable));
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(taps, 2);
      focus.dispose();
    });

    testWidgets('segmented control reports the tapped segment',
        (tester) async {
      String? picked;
      await tester.pumpWidget(_host(CruSegmentedControl<String>(
        segments: const [
          CruSegment('all', 'All'),
          CruSegment('waiting', 'Waiting 2'),
          CruSegment('done', 'Done 5'),
        ],
        selected: 'all',
        onChanged: (v) => picked = v,
      )));
      await tester.tap(find.text('Done 5'));
      expect(picked, 'done');
      expect(tester.getSize(find.byType(CruSegmentedControl<String>)).height,
          CruSize.segmentHeight);
    });

    test('monogram initials', () {
      expect(CruMonogram.initialsOf('Kavya Iyer'), 'KI');
      expect(CruMonogram.initialsOf('  mohammed  bin ansari '), 'MA');
      expect(CruMonogram.initialsOf('Priya'), 'P');
      expect(CruMonogram.initialsOf('Dr. Ananya Deshpande'), 'AD');
      expect(CruMonogram.initialsOf('dr Kavya Iyer'), 'KI');
      expect(CruMonogram.initialsOf(''), '?');
    });
  });
}
