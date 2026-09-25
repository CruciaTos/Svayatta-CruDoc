import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/theme/cru_theme.dart';

double _contrast(Color fg, Color bg) {
  // Composite translucent foregrounds over the background first.
  final a = fg.a;
  final blended = Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
  final l1 = blended.computeLuminance();
  final l2 = bg.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  group('CruColors', () {
    test('day and evening carry the spec values', () {
      expect(CruColors.day.canvas, const Color(0xFFF1F4F9));
      expect(CruColors.day.ink, const Color(0xFF2542BD));
      expect(CruColors.evening.canvas, const Color(0xFF111214));
      expect(CruColors.evening.ink, const Color(0xFF1D3591));
      expect(CruColors.evening.accentText, const Color(0xFF7399FF));
      expect(CruColors.evening.cardShadow, isEmpty);
    });

    test('onInk overrides only what sits on the Up next card', () {
      final onInk = CruColors.day.onInk();
      expect(onInk.label, const Color(0xFFFFFFFF));
      expect(onInk.label2, const Color(0xFFD3E0FF));
      expect(onInk.inset, const Color(0x1FFFFFFF));
      expect(onInk.primaryButtonFill, const Color(0xFFFFFFFF));
      expect(onInk.primaryButtonText, CruColors.day.ink);
      expect(onInk.surface, CruColors.day.surface);
      expect(CruColors.evening.onInk().inset, const Color(0x1AFFFFFF));
    });

    test('lerp between appearances is well formed', () {
      final mid = CruColors.day.lerp(CruColors.evening, 0.5);
      expect(mid.canvas, isNot(CruColors.day.canvas));
      expect(CruColors.day.lerp(CruColors.evening, 1).canvas,
          CruColors.evening.canvas);
    });

    for (final c in [CruColors.day, CruColors.evening]) {
      test('${c.appearance.name}: text pairs reach 4.5:1 on surface', () {
        final pairs = <String, Color>{
          'label': c.label,
          'label2': c.label2,
          'accentText': c.accentText,
          'amberText': c.amberText,
          if (c.isEvening) 'greenText': c.greenText,
          'redText': c.redText,
          'ai': c.ai,
          'tealText': c.tealText,
        };
        pairs.forEach((name, color) {
          expect(_contrast(color, c.surface), greaterThanOrEqualTo(4.5),
              reason: '$name on surface');
        });
        // Tinted pills keep their text legible too.
        expect(_contrast(c.accentText, Color.alphaBlend(c.accentTint, c.surface)),
            greaterThanOrEqualTo(4.5));
        expect(_contrast(c.ai, Color.alphaBlend(c.aiTint, c.surface)),
            greaterThanOrEqualTo(4.5));
      });
    }

    test('day greenText is the spec value, 4.4:1 on white (known exception)',
        () {
      // DESIGN_SPEC §2.2 gives #248A3D and claims every pair passes 4.5:1;
      // it measures 4.40:1. Kept as specified and reported, not changed.
      final ratio = _contrast(CruColors.day.greenText, CruColors.day.surface);
      expect(ratio, closeTo(4.40, 0.01));
    });

    test('white on the ink surfaces and the accent fill', () {
      const white = Color(0xFFFFFFFF);
      expect(_contrast(white, CruColors.day.ink), greaterThanOrEqualTo(4.5));
      expect(_contrast(white, CruColors.evening.ink), greaterThanOrEqualTo(4.5));
      expect(_contrast(white, CruColors.day.accent), greaterThanOrEqualTo(4.5));
      final onInk = CruColors.day.onInk();
      expect(_contrast(onInk.label2, CruColors.day.ink),
          greaterThanOrEqualTo(4.5));
    });
  });

  group('CruTheme', () {
    test('day and evening expose the extension and Geist', () {
      final day = CruTheme.day();
      final evening = CruTheme.evening();
      expect(day.extension<CruColors>(), same(CruColors.day));
      expect(evening.extension<CruColors>(), same(CruColors.evening));
      expect(day.brightness, Brightness.light);
      expect(evening.brightness, Brightness.dark);
      expect(day.colorScheme.primary, CruBrand.ink600);
      expect(day.textTheme.titleMedium?.fontFamily, CruType.family);
    });
  });
}
