import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'package:doctor_management_app/core/update/models/app_release.dart';
import 'package:doctor_management_app/core/update/models/update_progress.dart';
import 'package:doctor_management_app/core/update/update_exceptions.dart';

/// Contract every platform's updater satisfies — architecture doc §4/§5:
/// the seam that lets [UpdateService] and everything above it stay
/// completely platform-agnostic, and lets iOS slot in later without
/// touching anything but [UpdateInstallerFactory].
abstract interface class UpdateInstaller {
  /// Whether this platform can complete an update inside the running
  /// app (Windows/Android download + local install) versus only
  /// redirecting elsewhere (iOS → App Store/TestFlight, where
  /// `install()` just opens a URL and there's nothing "in-app" about it).
  bool get supportsInAppInstall;

  /// Downloads the asset matching this platform from [release],
  /// reporting progress via [onProgress] as it arrives. Throws
  /// [UpdateDownloadException] if the release/manifest doesn't carry a
  /// usable asset for this platform.
  Future<void> download(AppRelease release, void Function(UpdateProgress progress) onProgress);

  /// Verifies the just-downloaded file's integrity. Returns `true` when
  /// verification passes *or* when no checksum was published to check
  /// against (design principle #2 — `update.json` is optional).
  Future<bool> verifyChecksum();

  /// Hands the verified file to the platform's own install mechanism.
  /// May never return normally on some platforms (Windows exits the
  /// running app once the installer process is launched).
  Future<void> install();
}

/// Streams [uri] to [destination] in chunks, reporting
/// [UpdateProgressState.downloading] snapshots as bytes arrive. Shared
/// by [WindowsUpdateInstaller] and [AndroidUpdateInstaller] — the only
/// real difference between the two platforms is *where* the file lands
/// and how it's installed afterwards, not how the bytes get to disk.
Future<void> downloadFileWithProgress({
  required http.Client client,
  required Uri uri,
  required File destination,
  required void Function(UpdateProgress progress) onProgress,
  int totalHint = 0,
}) async {
  final http.StreamedResponse response;
  try {
    response = await client.send(http.Request('GET', uri));
  } catch (e) {
    throw UpdateDownloadException('Could not start the download: $e');
  }

  if (response.statusCode != 200) {
    throw UpdateDownloadException('Download failed with HTTP ${response.statusCode}.');
  }

  final total = response.contentLength ?? totalHint;
  var received = 0;

  await destination.parent.create(recursive: true);
  final sink = destination.openWrite();

  try {
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress(UpdateProgress(
        state: UpdateProgressState.downloading,
        bytesDownloaded: received,
        totalBytes: total,
        percent: total > 0 ? _clamp01(received / total) : 0,
      ));
    }
    await sink.flush();
  } catch (e) {
    throw UpdateDownloadException('Download interrupted: $e');
  } finally {
    await sink.close();
  }
}

/// Computes [file]'s sha256 and compares it (case-insensitively, ignoring
/// surrounding whitespace) against [expectedHex] — the value published
/// under `update.json`'s `platforms.<platform>.sha256`.
Future<bool> verifyFileSha256(File file, String expectedHex) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString().toLowerCase() == expectedHex.trim().toLowerCase();
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
