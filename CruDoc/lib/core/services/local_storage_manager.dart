import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'medical_storage_service.dart';
import 'storage_sync_queue.dart';

/// One file this device holds that may be removed to save space: a copy of
/// something already in the cloud (an original), or a cache the app can
/// rebuild by itself.
class LocalAsset {
  LocalAsset({
    required this.file,
    required this.bytes,
    required this.lastUsed,
    required this.isStillSafe,
    this.storagePath = '',
    this.isCache = false,
    this.onRemoved,
  });

  final File file;
  final int bytes;

  /// When it was last opened or changed; the oldest go first.
  final DateTime lastUsed;

  /// Where the cloud keeps it. Empty for a cache.
  final String storagePath;

  /// A derived file (preview, viewing file) the app fetches again on its
  /// own. Needs no cloud check and goes before any original.
  final bool isCache;

  /// Re-checked right before removal: the record has reached the cloud,
  /// still points at [storagePath], and nothing for it is waiting to upload.
  final Future<bool> Function() isStillSafe;

  /// Tells the owning feature the local copy is gone.
  final Future<void> Function()? onRemoved;
}

/// Lists the files one feature keeps on this device. Registered at startup,
/// the way upload link handlers are, so core code never imports features.
abstract class LocalAssetSource {
  String get name;
  Future<List<LocalAsset>> assets();
}

/// What a clean-up did.
class LocalCleanupResult {
  const LocalCleanupResult({
    this.freedBytes = 0,
    this.removedFiles = 0,
    this.skippedUnsafe = 0,
    this.totalBytesAfter = 0,
    this.limitBytes = 0,
  });

  final int freedBytes;
  final int removedFiles;

  /// Candidates left alone because their cloud copy couldn't be confirmed
  /// (not uploaded, still syncing, a different size, or offline).
  final int skippedUnsafe;

  final int totalBytesAfter;
  final int limitBytes;

  bool get withinLimit => limitBytes <= 0 || totalBytesAfter <= limitBytes;
}

/// What Settings shows: how much this device holds and how much of it the
/// app could free.
class LocalStorageReport {
  const LocalStorageReport({
    required this.totalBytes,
    required this.cloudCopyBytes,
    required this.cacheBytes,
    required this.limitBytes,
  });

  final int totalBytes;

  /// Copies of files the cloud also has (freeable once confirmed).
  final int cloudCopyBytes;
  final int cacheBytes;

  /// Everything else: the patient database, uploads still waiting, and
  /// files that are never uploaded. Never removed.
  int get keptBytes => totalBytes - cloudCopyBytes - cacheBytes;

  /// 0 = no limit.
  final int limitBytes;
}

/// The order to try removing [assets] in, to bring [totalBytes] within
/// [limitBytes]: caches first, then the least recently used; nothing used
/// within [grace] of [now]. Stops planning once the projected total fits.
/// Pure, for tests.
List<LocalAsset> planCleanup(
  List<LocalAsset> assets, {
  required int totalBytes,
  required int limitBytes,
  required DateTime now,
  Duration grace = LocalStorageManager.recentUseGrace,
}) {
  if (limitBytes <= 0 || totalBytes <= limitBytes) return const [];
  final eligible = [
    for (final a in assets)
      if (now.difference(a.lastUsed) >= grace &&
          (a.isCache || a.storagePath.isNotEmpty))
        a,
  ]..sort((a, b) {
      if (a.isCache != b.isCache) return a.isCache ? -1 : 1;
      return a.lastUsed.compareTo(b.lastUsed);
    });
  final plan = <LocalAsset>[];
  var projected = totalBytes;
  for (final a in eligible) {
    if (projected <= limitBytes) break;
    plan.add(a);
    projected -= a.bytes;
  }
  return plan;
}

/// Keeps what CruDoc stores on this device within the limit set in
/// Settings → Storage.
///
/// The limit belongs to the device, not the account: it lives in this
/// install's preferences and is never synced, so a phone can keep 500 MB
/// while a desktop keeps 3 GB.
///
/// Only heavy files are ever removed, and only when the cloud is known to
/// have them. Patient records (the local database) are never touched,
/// nor is anything waiting to upload or anything that is never uploaded
/// (scribe audio, some photos). Before each removal the feature re-checks
/// that the record reached the cloud and nothing is queued for it, and the
/// cloud copy is looked up and must match in size. Offline, or any doubt:
/// the file stays. A removed file downloads again when it is next opened.
class LocalStorageManager {
  LocalStorageManager._({
    Future<SharedPreferences> Function()? prefs,
    Future<Directory> Function()? appDir,
    Future<int?> Function(String storagePath)? cloudSize,
    DateTime Function()? now,
  }) : _prefs = prefs ?? SharedPreferences.getInstance,
       _appDir = appDir ?? getApplicationSupportDirectory,
       _cloudSize =
           cloudSize ?? ((path) => MedicalStorageService.instance.cloudSize(path)),
       _now = now ?? DateTime.now;

  static final LocalStorageManager instance = LocalStorageManager._();

  @visibleForTesting
  factory LocalStorageManager.forTesting({
    required Future<SharedPreferences> Function() prefs,
    required Future<Directory> Function() appDir,
    required Future<int?> Function(String storagePath) cloudSize,
    DateTime Function()? now,
  }) => LocalStorageManager._(
    prefs: prefs,
    appDir: appDir,
    cloudSize: cloudSize,
    now: now,
  );

  static const _limitKey = 'crudoc.localStorageLimitBytes';

  /// Files used this recently are never removed, so nothing disappears
  /// from under someone looking at it.
  static const recentUseGrace = Duration(minutes: 10);

  static const _mb = 1024 * 1024;
  static const _gb = 1024 * _mb;

  /// The slider's stops. 0 = no limit (the default).
  static const List<int> limitChoices = [
    500 * _mb,
    1 * _gb,
    2 * _gb,
    3 * _gb,
    5 * _gb,
    10 * _gb,
    20 * _gb,
    0,
  ];

  final Future<SharedPreferences> Function() _prefs;
  final Future<Directory> Function() _appDir;
  final Future<int?> Function(String storagePath) _cloudSize;
  final DateTime Function() _now;

  final List<LocalAssetSource> _sources = [];
  Future<LocalCleanupResult>? _running;
  Timer? _soon;
  Timer? _periodic;
  StreamSubscription<int>? _queueSub;

  void registerSource(LocalAssetSource source) {
    _sources.removeWhere((s) => s.name == source.name);
    _sources.add(source);
  }

  /// Marks [file] as just used, so it is among the last to be removed.
  static Future<void> touch(File file) async {
    try {
      await file.setLastAccessed(DateTime.now());
    } catch (_) {
      // Read-only or gone: ordering falls back to the modified time.
    }
  }

  Future<int> limitBytes() async => (await _prefs()).getInt(_limitKey) ?? 0;

  Future<void> setLimitBytes(int bytes) async {
    await (await _prefs()).setInt(_limitKey, bytes < 0 ? 0 : bytes);
    schedule(delay: Duration.zero);
  }

  /// Starts watching for a reason to clean up: at sign-in, when the upload
  /// queue empties (new cloud copies), and hourly.
  void start() {
    if (kIsWeb) return;
    stop();
    _queueSub = StorageSyncQueue.instance.watchPendingCount().listen((n) {
      if (n == 0) schedule();
    });
    _periodic = Timer.periodic(const Duration(hours: 1), (_) => schedule());
    schedule(delay: const Duration(minutes: 2));
  }

  void stop() {
    _soon?.cancel();
    _periodic?.cancel();
    unawaited(_queueSub?.cancel());
    _soon = null;
    _periodic = null;
    _queueSub = null;
  }

  /// Runs [enforce] after [delay], once however often it's asked for.
  void schedule({Duration delay = const Duration(seconds: 30)}) {
    if (kIsWeb) return;
    _soon?.cancel();
    _soon = Timer(delay, () => unawaited(enforce()));
  }

  Future<LocalStorageReport> report() async {
    final total = await _directoryBytes(await _appDir());
    var cloud = 0;
    var cache = 0;
    for (final a in await _allAssets()) {
      if (a.isCache) {
        cache += a.bytes;
      } else if (a.storagePath.isNotEmpty) {
        cloud += a.bytes;
      }
    }
    return LocalStorageReport(
      totalBytes: total,
      cloudCopyBytes: cloud,
      cacheBytes: cache,
      limitBytes: await limitBytes(),
    );
  }

  /// Brings this device within its limit, as far as it safely can. One run
  /// at a time; a second call waits for the first.
  Future<LocalCleanupResult> enforce() {
    if (kIsWeb) return Future.value(const LocalCleanupResult());
    return _running ??= _enforce().whenComplete(() => _running = null);
  }

  Future<LocalCleanupResult> _enforce() async {
    try {
      final limit = await limitBytes();
      var total = await _directoryBytes(await _appDir());
      if (limit <= 0 || total <= limit) {
        return LocalCleanupResult(totalBytesAfter: total, limitBytes: limit);
      }
      final plan = planCleanup(
        await _allAssets(),
        totalBytes: total,
        limitBytes: limit,
        now: _now(),
      );
      var freed = 0;
      var removed = 0;
      var skipped = 0;
      for (final a in plan) {
        if (total <= limit) break;
        if (!await _safeToRemove(a)) {
          skipped++;
          continue;
        }
        try {
          await a.file.delete();
        } catch (e) {
          // Open in another program, or already gone.
          debugPrint('[LocalStorage] could not remove ${a.file.path}: $e');
          continue;
        }
        await a.onRemoved?.call();
        total -= a.bytes;
        freed += a.bytes;
        removed++;
      }
      if (removed > 0 || skipped > 0) {
        debugPrint(
          '[LocalStorage] freed $freed bytes in $removed files; '
          '$skipped not confirmed in the cloud and kept',
        );
      }
      return LocalCleanupResult(
        freedBytes: freed,
        removedFiles: removed,
        skippedUnsafe: skipped,
        totalBytesAfter: total,
        limitBytes: limit,
      );
    } catch (e, st) {
      debugPrint('[LocalStorage] clean-up failed: $e\n$st');
      return const LocalCleanupResult();
    }
  }

  /// The last word before a file goes. Anything uncertain keeps it.
  Future<bool> _safeToRemove(LocalAsset a) async {
    try {
      if (!await a.file.exists()) return false;
      if (_now().difference(await _lastUsed(a.file)) < recentUseGrace) {
        return false; // Opened since the plan was made.
      }
      if (!await a.isStillSafe()) return false;
      if (a.isCache) return true;
      if (a.storagePath.isEmpty) return false;
      final cloud = await _cloudSize(a.storagePath);
      return cloud != null && cloud == await a.file.length();
    } catch (e) {
      // Offline, or the cloud couldn't be asked: not known to be safe.
      return false;
    }
  }

  Future<List<LocalAsset>> _allAssets() async {
    final all = <LocalAsset>[];
    for (final s in _sources) {
      try {
        all.addAll(await s.assets());
      } catch (e) {
        debugPrint('[LocalStorage] ${s.name} could not list files: $e');
      }
    }
    return all;
  }

  /// When [file] was last used: opened (see [touch]) or changed.
  static Future<DateTime> lastUsedOf(File file) => _lastUsed(file);

  static Future<DateTime> _lastUsed(File file) async {
    final s = await file.stat();
    return s.accessed.isAfter(s.modified) ? s.accessed : s.modified;
  }

  static Future<int> _directoryBytes(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }
}
