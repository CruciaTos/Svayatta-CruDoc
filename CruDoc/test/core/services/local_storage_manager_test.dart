import 'dart:io';

import 'package:doctor_management_app/core/services/local_storage_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A feature's files, as LocalStorageManager sees them.
class _Source implements LocalAssetSource {
  _Source(this.list);
  final List<LocalAsset> list;
  @override
  String get name => 'test';
  @override
  Future<List<LocalAsset>> assets() async => list;
}

void main() {
  late Directory root;
  final now = DateTime(2026, 10, 21, 12);
  final removed = <String>[];

  /// Cloud sizes by storage path; a missing key means "no such object",
  /// and [offline] makes every lookup fail.
  late Map<String, int> cloud;
  var offline = false;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('crudoc_storage_test');
    removed.clear();
    cloud = {};
    offline = false;
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  LocalStorageManager manager({int limit = 0}) {
    SharedPreferences.setMockInitialValues({
      'crudoc.localStorageLimitBytes': limit,
    });
    return LocalStorageManager.forTesting(
      prefs: SharedPreferences.getInstance,
      appDir: () async => root,
      cloudSize: (path) async {
        if (offline) throw const SocketException('offline');
        return cloud[path];
      },
      now: () => now,
    );
  }

  /// A file of [bytes] last used [age] ago. With [storagePath] it is a
  /// cloud copy (and the cloud has it at the same size unless [cloudBytes]
  /// says otherwise); with [cache] it is a cache; otherwise it is a file
  /// that only exists here.
  Future<LocalAsset> file(
    String name,
    int bytes, {
    Duration age = const Duration(days: 2),
    String storagePath = '',
    int? cloudBytes,
    bool cache = false,
    bool safe = true,
  }) async {
    final f = File('${root.path}/$name');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(List.filled(bytes, 1));
    final when = now.subtract(age);
    await f.setLastModified(when);
    await f.setLastAccessed(when);
    if (storagePath.isNotEmpty) cloud[storagePath] = cloudBytes ?? bytes;
    return LocalAsset(
      file: f,
      bytes: bytes,
      lastUsed: when,
      storagePath: storagePath,
      isCache: cache,
      isStillSafe: () async => safe,
      onRemoved: () async => removed.add(name),
    );
  }

  group('planCleanup', () {
    test('caches first, then the least recently used originals', () async {
      final old = await file('old', 10, storagePath: 'a', age: const Duration(days: 9));
      final newer = await file('newer', 10, storagePath: 'b', age: const Duration(days: 1));
      final cache = await file('cache', 10, cache: true, age: const Duration(hours: 1));
      final plan = planCleanup(
        [newer, old, cache],
        totalBytes: 100,
        limitBytes: 75,
        now: now,
      );
      expect([for (final a in plan) a.file.path.split(RegExp(r'[/\\]')).last],
          ['cache', 'old', 'newer']);
    });

    test('stops planning once the projected total fits', () async {
      final a = await file('a', 30, storagePath: 'a', age: const Duration(days: 3));
      final b = await file('b', 30, storagePath: 'b', age: const Duration(days: 2));
      final plan = planCleanup([a, b], totalBytes: 100, limitBytes: 80, now: now);
      expect(plan, [a]);
    });

    test('never plans files used just now, or with no cloud copy', () async {
      final recent = await file('recent', 50, storagePath: 'r', age: const Duration(minutes: 1));
      final localOnly = await file('local', 50);
      final plan = planCleanup(
        [recent, localOnly],
        totalBytes: 100,
        limitBytes: 10,
        now: now,
      );
      expect(plan, isEmpty);
    });

    test('no limit, or within it: nothing', () async {
      final a = await file('a', 50, storagePath: 'a');
      expect(planCleanup([a], totalBytes: 100, limitBytes: 0, now: now), isEmpty);
      expect(planCleanup([a], totalBytes: 100, limitBytes: 200, now: now), isEmpty);
    });
  });

  group('enforce', () {
    test('removes the oldest confirmed copies until within the limit', () async {
      final m = manager(limit: 250);
      m.registerSource(_Source([
        await file('newest', 100, storagePath: 'p/1', age: const Duration(days: 1)),
        await file('oldest', 100, storagePath: 'p/2', age: const Duration(days: 5)),
        await file('middle', 100, storagePath: 'p/3', age: const Duration(days: 3)),
      ]));
      final r = await m.enforce();
      expect(removed, ['oldest']);
      expect(r.freedBytes, 100);
      expect(r.withinLimit, isTrue);
      expect(await File('${root.path}/oldest').exists(), isFalse);
      expect(await File('${root.path}/newest').exists(), isTrue);
    });

    test('keeps a file whose cloud copy is missing or a different size', () async {
      final m = manager(limit: 10);
      final missing = await file('missing', 100, storagePath: 'p/missing');
      cloud.remove('p/missing');
      m.registerSource(_Source([
        missing,
        await file('short', 100, storagePath: 'p/short', cloudBytes: 99),
      ]));
      final r = await m.enforce();
      expect(removed, isEmpty);
      expect(r.skippedUnsafe, 2);
      expect(r.withinLimit, isFalse);
    });

    test('keeps everything while offline', () async {
      final m = manager(limit: 10);
      m.registerSource(_Source([await file('a', 100, storagePath: 'p/a')]));
      offline = true;
      final r = await m.enforce();
      expect(removed, isEmpty);
      expect(r.skippedUnsafe, 1);
    });

    test('keeps a file the feature no longer vouches for', () async {
      // Still uploading, or the record hasn't reached the cloud.
      final m = manager(limit: 10);
      m.registerSource(_Source([
        await file('a', 100, storagePath: 'p/a', safe: false),
      ]));
      await m.enforce();
      expect(removed, isEmpty);
    });

    test('never touches files that only exist here', () async {
      final m = manager(limit: 10);
      m.registerSource(_Source([await file('only-here', 100)]));
      await m.enforce();
      expect(await File('${root.path}/only-here').exists(), isTrue);
    });

    test('keeps a file opened after the plan was made', () async {
      final m = manager(limit: 10);
      final a = await file('a', 100, storagePath: 'p/a');
      await a.file.setLastAccessed(now.subtract(const Duration(minutes: 2)));
      m.registerSource(_Source([a]));
      await m.enforce();
      expect(removed, isEmpty);
    });

    test('caches go without a cloud check', () async {
      final m = manager(limit: 10);
      m.registerSource(_Source([await file('preview', 100, cache: true)]));
      offline = true;
      await m.enforce();
      expect(removed, ['preview']);
    });

    test('no limit: nothing is removed', () async {
      final m = manager();
      m.registerSource(_Source([await file('a', 100, storagePath: 'p/a')]));
      await m.enforce();
      expect(removed, isEmpty);
    });
  });

  test('the limit is kept in this device\'s preferences', () async {
    final m = manager();
    expect(await m.limitBytes(), 0);
    await m.setLimitBytes(3 * 1024 * 1024 * 1024);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('crudoc.localStorageLimitBytes'), 3 * 1024 * 1024 * 1024);
    m.stop();
  });

  test('report splits cloud copies, caches and what is always kept', () async {
    final m = manager(limit: 1000);
    final cloudCopy = await file('c', 300, storagePath: 'p/c');
    final cache = await file('v', 100, cache: true);
    await file('db', 600); // The database and other kept files.
    m.registerSource(_Source([cloudCopy, cache]));
    final r = await m.report();
    expect(r.totalBytes, 1000);
    expect(r.cloudCopyBytes, 300);
    expect(r.cacheBytes, 100);
    expect(r.keptBytes, 600);
    expect(r.limitBytes, 1000);
  });
}
