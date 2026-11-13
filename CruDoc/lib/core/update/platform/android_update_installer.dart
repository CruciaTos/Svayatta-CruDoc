import 'dart:io';

import 'package:flutter/services.dart';

import 'package:doctor_management_app/core/update/models/app_release.dart';
import 'package:doctor_management_app/core/update/models/update_manifest.dart';
import 'package:doctor_management_app/core/update/models/update_progress.dart';
import 'package:doctor_management_app/core/update/platform/update_installer.dart';
import 'package:doctor_management_app/core/update/update_exceptions.dart';

/// Android's [UpdateInstaller]. Downloads the `.apk` asset through the
/// system DownloadManager (so it continues in the background, even after
/// the app is closed), verifies it, and hands it to the system's own
/// signature-verified install flow.
///
/// Requires `android.permission.REQUEST_INSTALL_PACKAGES` and a
/// `FileProvider <provider>` entry in `AndroidManifest.xml`. The native side
/// lives in `MainActivity.kt` (channel `crudoc/update_installer`),
/// `UpdateDownloads.kt` and `UpdateDownloadReceiver.kt`.
class AndroidUpdateInstaller implements UpdateInstaller {
  AndroidUpdateInstaller();

  /// Fallback `update.json` key, and the only one releases before 1.0.8
  /// read. It points at the 64-bit APK.
  static const String _platformKey = 'android';

  /// Releases ship one APK per processor type. Android ABI name →
  /// `update.json` key.
  static const Map<String, String> _abiKeys = {
    'arm64-v8a': 'android-arm64',
    'armeabi-v7a': 'android-arm',
    'x86_64': 'android-x86_64',
  };

  static const MethodChannel _installChannel = MethodChannel(
    'crudoc/update_installer',
  );

  static const Duration _pollEvery = Duration(milliseconds: 700);

  static const String _downloadFailedMessage =
      'The download failed. Check the internet connection and tap Retry.';

  File? _downloadedFile;
  String? _expectedSha256;

  @override
  bool get supportsInAppInstall => true;

  /// Starts (or re-attaches to) the background download, then follows it
  /// until it finishes. The native side never starts a second download for
  /// the same file, so calling this again while one runs just re-attaches.
  @override
  Future<void> download(
    AppRelease release,
    void Function(UpdateProgress progress) onProgress,
  ) async {
    final platformInfo = await _platformInfoFor(release);
    final assetName = platformInfo?.asset;
    if (assetName == null || assetName.isEmpty) {
      throw const UpdateDownloadException(
        'This release has no Android package asset listed in update.json.',
      );
    }

    final asset = release.assetNamed(assetName);
    if (asset == null || asset.downloadUrl.isEmpty) {
      throw UpdateDownloadException(
        'Could not find the "$assetName" asset on the GitHub release.',
      );
    }

    _expectedSha256 = platformInfo?.sha256;
    final totalHint = platformInfo?.size ?? asset.size;

    try {
      await _installChannel.invokeMethod<int>('startApkDownload', {
        'url': asset.downloadUrl,
        'fileName': asset.name,
        'title': 'CruDoc update ${release.version}',
      });

      while (true) {
        final info = await _query();
        final status = info['status'] as String? ?? 'none';
        final bytes = (info['bytes'] as num?)?.toInt() ?? 0;
        final reported = (info['total'] as num?)?.toInt() ?? 0;
        final total = reported > 0 ? reported : totalHint;

        if (status == 'successful') {
          final path = info['path'] as String?;
          if (path == null || path.isEmpty || !File(path).existsSync()) {
            throw const UpdateDownloadException(_downloadFailedMessage);
          }
          _downloadedFile = File(path);
          return;
        }
        if (status == 'failed' || status == 'none') {
          throw const UpdateDownloadException(_downloadFailedMessage);
        }

        onProgress(
          UpdateProgress(
            state: UpdateProgressState.downloading,
            bytesDownloaded: bytes,
            totalBytes: total,
            percent: total > 0 ? (bytes / total).clamp(0.0, 1.0) : 0.0,
            waitingForNetwork: info['waitingForNetwork'] == true,
          ),
        );
        await Future<void>.delayed(_pollEvery);
      }
    } on MissingPluginException {
      throw const UpdateDownloadException(
        'The Android download bridge is missing. Reinstall CruDoc from the '
        'latest build.',
      );
    } on PlatformException catch (e) {
      throw UpdateDownloadException(
        e.message ?? 'The download could not start.',
      );
    }
  }

  Future<Map<String, Object?>> _query() async {
    final raw = await _installChannel.invokeMapMethod<String, Object?>(
      'queryApkDownload',
    );
    return raw ?? const {};
  }

  /// Stops the background download and forgets it, so the next
  /// [download] starts fresh.
  Future<void> cancelDownload() async {
    try {
      await _installChannel.invokeMethod<void>('cancelApkDownload');
    } on PlatformException {
      // Nothing to cancel.
    } on MissingPluginException {
      // Same.
    }
  }

  /// Whether Android currently lets CruDoc open the installer.
  Future<bool> canInstall() async {
    try {
      return await _installChannel.invokeMethod<bool>('canInstallPackages') ??
          true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// Status of the stored background download (`none`, `pending`,
  /// `running`, `paused`, `successful`, `failed`), but only when it is the
  /// package for [release]; `none` for anything else.
  Future<String> downloadStatusFor(AppRelease release) async {
    try {
      final assetName = (await _platformInfoFor(release))?.asset;
      if (assetName == null || assetName.isEmpty) return 'none';
      final info = await _query();
      if (info['fileName'] != assetName) return 'none';
      return info['status'] as String? ?? 'none';
    } on PlatformException {
      return 'none';
    } on MissingPluginException {
      return 'none';
    }
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
      await _installChannel.invokeMethod<void>('installApk', {
        'path': file.path,
      });
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
      if (e.code == 'NEEDS_PERMISSION') {
        throw UpdateInstallPermissionException(
          e.message ??
              'Allow CruDoc to install updates, then come back — the update '
                  'continues by itself.',
        );
      }
      throw UpdateInstallException(
        'The system installer could not be launched: ${e.message}',
      );
    }
  }

  /// The `update.json` entry for this phone's processor: the first of its
  /// ABIs (best first) that the release has an APK for, else `android`.
  Future<UpdateManifestPlatform?> _platformInfoFor(AppRelease release) async {
    final manifest = release.manifest;
    if (manifest == null) return null;
    List<String> abis = const [];
    try {
      abis =
          await _installChannel.invokeListMethod<String>('supportedAbis') ??
          const [];
    } on PlatformException {
      // Fall back to the default entry below.
    } on MissingPluginException {
      // Same.
    }
    for (final abi in abis) {
      final key = _abiKeys[abi];
      final info = key == null ? null : manifest.platformFor(key);
      if (info?.asset?.isNotEmpty ?? false) return info;
    }
    return manifest.platformFor(_platformKey);
  }
}
