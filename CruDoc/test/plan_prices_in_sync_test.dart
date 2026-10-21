import 'dart:io';

import 'package:crudoc_shared/subscription/feature_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// The upgrade screen shows featureCatalog's prices; a UPI checkout charges
/// MODULE_PRICES_INR in functions/src/plan-payments.ts. If they drift, a
/// doctor is charged something other than what they were shown.
void main() {
  test('every paid module costs the same in the app and on the server', () {
    final source = File('functions/src/plan-payments.ts').readAsStringSync();
    final table = RegExp(
      r'MODULE_PRICES_INR[^{]*\{([^}]*)\}',
    ).firstMatch(source)!.group(1)!;
    final server = {
      for (final m in RegExp(r'(\w+):\s*(\d+)').allMatches(table))
        m.group(1)!: double.parse(m.group(2)!),
    };

    final app = {
      for (final item in featureCatalog)
        if (!item.isBaseModule && item.monthlyPriceInr > 0)
          item.moduleKey: item.monthlyPriceInr,
    };

    expect(server, isNotEmpty);
    expect(server, app);
  });
}
