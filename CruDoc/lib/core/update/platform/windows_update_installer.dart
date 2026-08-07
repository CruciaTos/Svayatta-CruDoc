import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/core/update/models/app_release.dart';
import 'package:doctor_management_app/core/update/models/update_progress.dart';
import 'package:doctor_management_app/core/update/platform/update_installer.dart';
import 'package:doctor_management_app/core/update/update_exceptions.dart';

/// Windows's [UpdateInstaller]. Downloads the installer asset (`.exe`/
/// `.msix`) to a temp folder, verifies it, launches it as a detached
/// process, then exits this app so the installer can replace the
/// running executable/DLLs cleanly.
///
/// Windows has no OS-level sideload restriction the way Android/iOS do
/// — architecture doc §5 — so this needs zero new native code: `dart:io
/// Process.start` plus the already-present `path_provider`/`crypto`
/// dependencies are enough. It does assume the release's asset is an
/// actual installer (Inno Setup/MSIX) rather than a raw `.exe`+DLL
/// folder — architecture doc §7's packaging gap must be closed
/// separately for this to have something sensible to launch.
class WindowsUpdateInstaller implements UpdateInstaller {
  WindowsUpdateInstaller({http.Client? client}) : _client = client ?? http.Client();

  static const String _platformKey = 'windows';

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
        'This release has no Windows installer asset listed in update.json.',
      );
    }

    final asset = release.assetNamed(assetName);
    if (asset == null || asset.downloadUrl.isEmpty) {
      throw UpdateDownloadException('Could not find the "$assetName" asset on the GitHub release.');
    }

    _expectedSha256 = platformInfo?.sha256;

    final tempDir = await getTemporaryDirectory();
    final destination = File(p.join(tempDir.path, asset.name));

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
    if (expected == null || expected.isEmpty) {
      // No checksum published — nothing to compare against. Design
      // principle #2 treats update.json as optional; don't block the
      // install path over its absence.
      return true;
    }
    return verifyFileSha256(file, expected);
  }

  @override
  Future<void> install() async {
    final file = _downloadedFile;
    if (file == null) {
      throw const UpdateInstallException('No downloaded installer to run.');
    }

    try {
      await Process.start(file.path, const [], mode: ProcessStartMode.detached);
    } catch (e) {
      throw UpdateInstallException('Could not launch the downloaded installer: $e');
    }

    // The installer now owns replacing this app's files — it can't do
    // that cleanly while this process still has them open.
    exit(0);
  }
}
