import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_pane.dart';

RadPixels _px(int bytes) => RadPixels(
  width: 1,
  height: 1,
  values: Float32List(bytes ~/ 4),
  minValue: 0,
  maxValue: 1,
  lowPct: 0,
  highPct: 1,
);

void main() {
  test('the image asked for jumps ahead of background loads', () async {
    final started = <String>[];
    final gates = <String, Completer<RadPixels>>{};
    final cache = RadPixelCache((s, id, f) {
      started.add(id);
      return (gates[id] = Completer<RadPixels>()).future;
    }, capacity: 100, maxLoads: 1);

    for (final id in ['a', 'b', 'c']) {
      cache.prefetch('s', id, 0);
    }
    expect(started, ['a']);
    final wanted = cache.get('s', 'z', 0);
    gates['a']!.complete(_px(4));
    await pumpEventQueue();
    expect(started, ['a', 'z']);
    gates['z']!.complete(_px(4));
    expect((await wanted).values.length, 1);

    // A queued background load asked for becomes wanted now and survives
    // a cancel.
    final b = cache.get('s', 'b', 0);
    await pumpEventQueue();
    cache.cancelPrefetch();
    expect(started.last, 'b');
    gates['b']!.complete(_px(4));
    await b;
    await pumpEventQueue();
    expect(started.contains('c'), isFalse);
    expect(cache.has('s', 'c', 0), isFalse);
  });

  test('keeps decoded bytes under the limit, oldest out first', () async {
    final cache = RadPixelCache(
      (s, id, f) async => _px(100),
      capacity: 100,
      maxBytes: 250,
    );
    for (final id in ['a', 'b', 'c']) {
      await cache.get('s', id, 0);
    }
    await pumpEventQueue();
    expect(cache.has('s', 'a', 0), isFalse);
    expect(cache.has('s', 'b', 0), isTrue);
    expect(cache.has('s', 'c', 0), isTrue);
  });

  test('a failed load is not kept', () async {
    var tries = 0;
    final cache = RadPixelCache((s, id, f) async {
      tries++;
      throw StateError('bad');
    });
    await expectLater(cache.get('s', 'x', 0), throwsStateError);
    await pumpEventQueue();
    expect(cache.has('s', 'x', 0), isFalse);
    cache.prefetch('s', 'y', 0); // nobody waits: must not throw uncaught
    await pumpEventQueue();
    expect(tries, 2);
  });
}
