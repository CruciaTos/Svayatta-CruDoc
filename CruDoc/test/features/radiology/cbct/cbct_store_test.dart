import 'dart:async';
import 'dart:io';

import 'package:doctor_management_app/features/radiology/cbct/cbct_pack.dart';
import 'package:doctor_management_app/features/radiology/cbct/cbct_store.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:flutter_test/flutter_test.dart';

RadStudy study(String id, {RadModality modality = RadModality.cbct}) {
  final now = DateTime(2026, 11, 9);
  return RadStudy(
    id: id,
    patientId: 'p',
    patientName: 'N',
    modality: modality,
    studyDate: now,
    receivedAt: now,
    images: const [],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Directory tmp;
  late List<String> packed;
  late Map<String, String> fingerprints;
  late Map<String, String> builtWith;
  late Completer<void> gate;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cbct_store_test');
    packed = [];
    fingerprints = {};
    builtWith = {};
    gate = Completer<void>();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  CbctStore make({bool supported = true, bool gated = false}) => CbctStore(
    platformSupported: () => supported,
    appVersion: () async => '1.0',
    studyDirOf: (s) async => Directory('${tmp.path}/${s.id}'),
    plan: (s, d) => CbctPlan(dir: d.path, fingerprint: fingerprints[s.id] ?? 'a'),
    readReady: (dir, fp) async {
      final id = dir.split(RegExp(r'[\\/]')).last;
      return builtWith[id] == fp ? {'ok': true} : null;
    },
    pack: (s, d, onProgress) async {
      packed.add(s.id);
      onProgress('Reading slices', 0.5);
      if (gated && s.id == 'a') await gate.future;
      builtWith[s.id] = fingerprints[s.id] ?? 'a';
      return CbctPack(dir: Directory(d.path), meta: {'ok': true});
    },
  );

  test('packs one at a time and priority jumps the queue', () async {
    final store = make(gated: true);
    store.enqueue(study('a'));
    store.enqueue(study('b'));
    store.enqueue(study('c'));
    store.enqueue(study('c'), priority: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(packed, ['a']); // a is running; the rest wait
    gate.complete();
    await store.idle;
    expect(packed, ['a', 'c', 'b']);
    expect(store.statusOf(study('c')).state, CbctPackState.ready);
  });

  test('does nothing on an unsupported platform or a non-volume study', () async {
    final store = make(supported: false);
    store.enqueue(study('a'));
    await store.idle;
    expect(packed, isEmpty);
    final other = make();
    other.enqueue(study('x', modality: RadModality.opg));
    await other.idle;
    expect(packed, isEmpty);
  });

  test('packs again when the fingerprint changes, not otherwise', () async {
    final store = make();
    store.enqueue(study('a'));
    await store.idle;
    store.enqueue(study('a'));
    await store.idle;
    expect(packed, ['a']);
    expect((await store.refresh(study('a'))).state, CbctPackState.ready);

    fingerprints['a'] = 'b';
    expect((await store.refresh(study('a'))).state, CbctPackState.missing);
    store.enqueue(study('a'));
    await store.idle;
    expect(packed, ['a', 'a']);
  });
}
