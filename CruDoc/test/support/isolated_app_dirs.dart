import 'dart:io';

import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Gives this test file its own app folders, so the local database it opens
/// is its own.
///
/// `flutter test` runs test files side by side in separate processes. With
/// no path_provider plugin they all fell back to the same system temp
/// folder, opened the same SQLite files, and failed each other with
/// "database is locked" and rows left over from earlier runs. Call at the
/// top of `main()` in any test that touches [LocalDatabaseService].
void useIsolatedAppDirs() {
  late Directory root;
  late PathProviderPlatform previous;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('crudoc_test_');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TempPathProvider(root.path);
  });

  tearDownAll(() async {
    try {
      await LocalDatabaseService.instance.close();
    } catch (_) {}
    PathProviderPlatform.instance = previous;
    try {
      await root.delete(recursive: true);
    } catch (_) {
      // Windows can hold a file briefly after close; the OS cleans temp.
    }
  });
}

class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.root);

  final String root;

  String _dir(String name) {
    final d = Directory('$root${Platform.pathSeparator}$name')
      ..createSync(recursive: true);
    return d.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async => _dir('support');

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('documents');

  @override
  Future<String?> getApplicationCachePath() async => _dir('cache');

  @override
  Future<String?> getTemporaryPath() async => _dir('tmp');

  @override
  Future<String?> getLibraryPath() async => _dir('library');

  @override
  Future<String?> getDownloadsPath() async => _dir('downloads');
}
