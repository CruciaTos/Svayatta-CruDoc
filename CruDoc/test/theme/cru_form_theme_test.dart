import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

Widget _host(Widget child, {CruAppearance appearance = CruAppearance.day}) {
  return MaterialApp(
    theme: CruTheme.of(appearance),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  );
}

InputDecorator _decorator(WidgetTester tester, Finder field) => tester
    .widget<InputDecorator>(
      find.descendant(of: field, matching: find.byType(InputDecorator)),
    );

void main() {
  group('input decoration theme', () {
    for (final appearance in CruAppearance.values) {
      test('${appearance.name}: inset fill, accent focus, amber error', () {
        final c = CruColors.of(appearance);
        final theme = CruTheme.of(appearance).inputDecorationTheme;
        expect(theme.filled, isTrue);
        expect(theme.contentPadding, const EdgeInsets.fromLTRB(14, 12, 14, 12));
        expect(theme.errorStyle?.color, c.amberText);

        final fill = theme.fillColor! as WidgetStateColor;
        expect(fill.resolve({}), c.inset);
        expect(fill.resolve({WidgetState.focused}), c.surface);

        // The ring lives in `border` so a field's own border wins.
        expect(theme.enabledBorder, isNull);
        expect(theme.focusedBorder, isNull);
        final ring = theme.border! as CruStateInputBorder;
        expect(ring.isOutline, isFalse);
        expect(ring.radius, CruRadius.control);
        InputBorder at(Set<WidgetState> s) => ring.resolve(s);
        expect(at({}).borderSide.color.a, 0);
        expect(at({WidgetState.focused}).borderSide,
            BorderSide(color: c.accent, width: 1.5));
        expect(at({WidgetState.error}).borderSide,
            BorderSide(color: c.amber, width: 1.5));
        expect(at({WidgetState.focused, WidgetState.error}).borderSide.color,
            c.amber);
      });
    }

    testWidgets('a plain field takes the inset style', (tester) async {
      await tester.pumpWidget(
        _host(const TextField(decoration: InputDecoration(hintText: 'Name'))),
      );
      final decoration = _decorator(tester, find.byType(TextField)).decoration;
      expect(decoration.filled, isTrue);
      expect(decoration.border, isA<CruStateInputBorder>());
    });

    testWidgets('a dense 15 px field and CruTextField are 44 px',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              TextField(
                key: const Key('dense'),
                style: CruType.input,
                decoration: const InputDecoration(isDense: true),
              ),
              CruTextField(label: 'Name', controller: controller),
            ],
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('dense'))).height, 44);
      final frame = find.descendant(
        of: find.byType(CruTextField),
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(frame.first).height, 44);
    });

    testWidgets('InputBorder.none and collapsed fields keep their own look',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              TextField(
                key: Key('none'),
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                ),
              ),
              TextField(
                key: Key('collapsed'),
                decoration: InputDecoration.collapsed(hintText: 'x'),
              ),
            ],
          ),
        ),
      );
      for (final key in ['none', 'collapsed']) {
        final d = _decorator(tester, find.byKey(Key(key))).decoration;
        expect(d.border, InputBorder.none, reason: key);
        expect(d.filled, isFalse, reason: key);
        expect(d.focusedBorder, isNull, reason: key);
      }
    });

    testWidgets('pickers open on the Calm Clinical surface', (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDatePicker(
                context: context,
                initialDate: DateTime(2026, 10, 5),
                firstDate: DateTime(2026),
                lastDate: DateTime(2027),
              ),
              child: const Text('open'),
            ),
          ),
          appearance: CruAppearance.evening,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.backgroundColor ?? CruColors.evening.surface,
          CruColors.evening.surface);
      final theme = DatePickerTheme.of(tester.element(find.byType(Dialog)));
      expect(theme.backgroundColor, CruColors.evening.surface);
      expect(
        theme.dayBackgroundColor?.resolve({WidgetState.selected}),
        CruColors.evening.accent,
      );
    });
  });

  group('CruDropdownField', () {
    testWidgets('shows the value and reports a new choice', (tester) async {
      String? picked;
      await tester.pumpWidget(
        _host(
          CruDropdownField<String>(
            label: 'Duration',
            value: '30 min',
            items: const ['15 min', '30 min', '45 min'],
            itemLabel: (d) => d,
            onChanged: (v) => picked = v,
          ),
        ),
      );
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);

      await tester.tap(find.text('30 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('45 min').last);
      await tester.pumpAndSettle();
      expect(picked, '45 min');
    });

    testWidgets('null onChanged disables it', (tester) async {
      await tester.pumpWidget(
        _host(
          CruDropdownField<String>(
            label: 'Duration',
            value: '30 min',
            items: const ['15 min', '30 min'],
            itemLabel: (d) => d,
            onChanged: null,
          ),
        ),
      );
      final button = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(button.onChanged, isNull);
      expect(find.text('30 min'), findsOneWidget);
    });

    testWidgets('an error draws the amber message', (tester) async {
      await tester.pumpWidget(
        _host(
          CruDropdownField<String>(
            label: 'Duration',
            value: null,
            items: const ['15 min'],
            itemLabel: (d) => d,
            onChanged: (_) {},
            error: 'Pick a duration',
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('Pick a duration'));
      expect(text.style?.color, CruColors.day.amberText);
    });
  });
}
