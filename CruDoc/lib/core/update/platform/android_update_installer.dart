import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/core/update/models/app_release.dart';
import 'package:doctor_management_app/core/update/models/update_progress.dart';
import 'package:doctor_management_app/core/update/platform/update_installer.dart';
import 'package:doctor_management_app/core/update/update_exceptions.dart';

/// Android's [UpdateInstaller]. Downloads the `.apk` asset to app-scoped
/// storage, verifies it, and hands it to the system's own
/// signature-verified install flow.
///
/// Requires `android.permission.REQUEST_INSTALL_PACKAGES` and a
/// `FileProvider <provider>` entry in `AndroidManifest.xml` — the one
/// platform needing a manifest change (architecture doc §5/§7), but
/// that change is isolated to `android/`, not to any Dart logic outside
/// this class.
///
/// The actual "hand the APK to the system installer" step needs a small
/// native intent (`FileProvider` content URI + `ACTION_VIEW` with
/// `FLAG_GRANT_READ_URI_PERMISSION`) that no plugin already in
/// `pubspec.yaml` covers — flagged as an open decision in architecture
/// doc §7/§8. Rather than guess at a new plugin dependency, [install]
/// calls a `crudoc/update_installer` platform channel; see the
/// `MissingPluginException` branch below for exactly what to add on the
/// Kotlin side.
class AndroidUpdateInstaller implements UpdateInstaller {
  AndroidUpdateInstaller({http.Client? client}) : _client = client ?? http.Client();

  static const String _platformKey = 'android';
  static const MethodChannel _installChannel = MethodChannel('crudoc/update_installer');

  final http.Client _client;

  File? _downloadedFile;
  String? _expectedSha256;

  @override
  bool get supportsInAppInstall => true;

  @override
  Future<void> download(AppRelease release, void Function(UpdateProgress progress) onProgress) async {
    final platformInfo = release.manifest?.platformFor(_platformKey);
    final assetName = platformInfo?.asset;
    if (assetName == null || assetName.isEmpty) {
      throw const UpdateDownloadException(
        'This release has no Android package asset listed in update.json.',
      );
    }

    final asset = release.assetNamed(assetName);
    if (asset == null || asset.downloadUrl.isEmpty) {
      throw UpdateDownloadException('Could not find the "$assetName" asset on the GitHub release.');
    }

    _expectedSha256 = platformInfo?.sha256;

    // App-scoped storage that a FileProvider can expose via a content://
    // URI — never the public Downloads folder, which REQUEST_INSTALL_PACKAGES
    // sideloading doesn't need and which complicates cleanup.
    final dir = await getExternalStorageDirectory() ?? await getApplicationSupportDirectory();
    final destination = File(p.join(dir.path, asset.name));

    await downloadFileWithProgress(
      client: _client,
      uri: Uri.parse(asset.downloadUrl),
      destination: destination,
      totalHint: platformInfo?.size ?? asset.size,
      onProgress: onProgress,
    );

    _downloadedFile = destination;
  }

  @override
  Future<bool> verifyChecksum() async {
    final file = _downloadedFile;
    if (file == null) return false;

    final expected = _expectedSha256;
    if (expected == null || expected.isEmpty) return true;
    return verifyFileSha256(file, expected);
  }

  @override
  Future<void> install() async {
    final file = _downloadedFile;
    if (file == null) {
      throw const UpdateInstallException('No downloaded package to install.');
    }

    try {
      await _installChannel.invokeMethod<void>('installApk', {'path': file.path});
    } on MissingPluginException {
      throw const UpdateInstallException(
        'The native Android install bridge is not implemented yet. Add a '
        '`crudoc/update_installer` MethodChannel handler in '
        'MainActivity.kt that: builds a content:// URI for the APK via '
        'FileProvider.getUriForFile(), then fires an Intent(ACTION_VIEW) '
        'with setDataAndType(uri, "application/vnd.android.package-archive") '
        'and FLAG_GRANT_READ_URI_PERMISSION. Requires the '
        'REQUEST_INSTALL_PACKAGES permission and a FileProvider <provider> '
        'entry in AndroidManifest.xml (architecture doc §7).',
      );
    } on PlatformException catch (e) {
      throw UpdateInstallException('The system installer could not be launched: ${e.message}');
    }
  }
}
