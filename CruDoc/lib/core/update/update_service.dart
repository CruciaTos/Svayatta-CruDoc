import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';

import 'package:doctor_management_app/core/update/models/app_release.dart';
import 'package:doctor_management_app/core/update/models/update_check_result.dart';
import 'package:doctor_management_app/core/update/models/update_progress.dart';
import 'package:doctor_management_app/core/update/platform/android_update_installer.dart';
import 'package:doctor_management_app/core/update/platform/update_installer.dart';
import 'package:doctor_management_app/core/update/platform/update_installer_factory.dart';
import 'package:doctor_management_app/core/update/sources/github_release_source.dart';
import 'package:doctor_management_app/core/update/sources/update_source.dart';
import 'package:doctor_management_app/core/update/update_exceptions.dart';
import 'package:doctor_management_app/core/update/version/version_comparator.dart';

/// Facade the rest of the app talks to — the only class `UpdateController`
/// depends on (architecture doc §4). Builds its own [GithubReleaseSource]
/// and [UpdateInstallerFactory] internally, the same way `VisitRepository()`
/// / `RevenueRepository()` build their own Firestore access rather than
/// taking it as a constructor argument — see `update_providers.dart`'s
/// `updateServiceProvider`, which already relies on this no-arg shape.
///
/// Depends only on [UpdateSource], [VersionComparator], and
/// [UpdateInstallerFactory] — zero platform-specific code, per design
/// principle #3.
class UpdateService {
  UpdateService({
    UpdateSource? source,
    UpdateInstallerFactory? installerFactory,
  }) : _source = source ?? GithubReleaseSource(),
       _installerFactory = installerFactory ?? const UpdateInstallerFactory();

  final UpdateSource _source;
  final UpdateInstallerFactory _installerFactory;

  /// Fetches the latest GitHub release and compares it against the
  /// installed app's version via [PackageInfo] — reading local package
  /// info, never a store API. Every failure path resolves into
  /// [CheckFailed] rather than throwing (design principle #4), so
  /// callers never need a top-level try/catch around this.
  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final release = await _source.fetchLatestRelease();
      if (release == null || release.version.isEmpty) {
        return const CheckFailed(
          'No published release could be found on GitHub.',
        );
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (!VersionComparator.isNewer(release.version, currentVersion)) {
        return const UpToDate();
      }

      return UpdateAvailable(release);
    } on UpdateException catch (e) {
      return CheckFailed(e.message);
    } catch (e) {
      return CheckFailed(e.toString());
    }
  }

  /// Downloads, verifies, and installs [release] via whichever
  /// [UpdateInstaller] [UpdateInstallerFactory] resolves for the
  /// current platform, streaming [UpdateProgress] snapshots as it goes.
  ///
  /// The returned stream always terminates: either the platform
  /// installer takes over (Windows exits the app; Android hands off to
  /// the system installer and returns), or a final
  /// [UpdateProgressState.failed] snapshot is emitted before the stream
  /// closes. Callers ([UpdateController.startUpdate]) don't need to
  /// handle stream errors — failures arrive as data, not as a thrown
  /// stream error.
  Stream<UpdateProgress> startDownloadAndInstall(AppRelease release) {
    final controller = StreamController<UpdateProgress>();
    unawaited(_run(release, controller));
    return controller.stream;
  }

  Future<void> _run(
    AppRelease release,
    StreamController<UpdateProgress> controller,
  ) async {
    void emit(UpdateProgress progress) {
      if (!controller.isClosed) controller.add(progress);
    }

    try {
      final installer = _installerFactory.create();

      emit(const UpdateProgress(state: UpdateProgressState.downloading));
      await installer.download(release, emit);

      emit(const UpdateProgress(state: UpdateProgressState.verifying));
      final verified = await installer.verifyChecksum();
      if (!verified) {
        throw const UpdateVerificationException(
          'The downloaded file does not match the published checksum. Please try again.',
        );
      }

      emit(const UpdateProgress(state: UpdateProgressState.readyToInstall));
      emit(const UpdateProgress(state: UpdateProgressState.installing));
      await installer.install();
      // Windows exits the app from inside install(); Android hands off
      // to the system installer and returns here. Either way, there's
      // nothing further for this stream to report — fall through to close.
    } on UpdateInstallPermissionException catch (e) {
      // Not a failure: Android's "install unknown apps" page is open and
      // the controller carries on when the person comes back.
      emit(
        UpdateProgress(
          state: UpdateProgressState.readyToInstall,
          needsInstallPermission: true,
          errorMessage: e.message,
        ),
      );
    } on UpdateException catch (e) {
      emit(
        UpdateProgress(
          state: UpdateProgressState.failed,
          errorMessage: e.message,
        ),
      );
    } catch (e) {
      emit(
        UpdateProgress(
          state: UpdateProgressState.failed,
          errorMessage: e.toString(),
        ),
      );
    } finally {
      await controller.close();
    }
  }

  /// The Android installer, or null on any other platform.
  AndroidUpdateInstaller? _androidInstaller() {
    try {
      final UpdateInstaller installer = _installerFactory.create();
      return installer is AndroidUpdateInstaller ? installer : null;
    } on UpdateException {
      return null;
    }
  }

  /// Android only: stops the background download and forgets it, so a
  /// retry starts fresh. No-op elsewhere.
  Future<void> cancelAndroidDownload() async {
    await _androidInstaller()?.cancelDownload();
  }

  /// Android only: whether the phone currently lets CruDoc open the
  /// installer ("install unknown apps"). `true` elsewhere.
  Future<bool> androidCanInstall() async {
    return await _androidInstaller()?.canInstall() ?? true;
  }

  /// Android only: status of the stored background download if it is the
  /// package for [release] (`pending`, `running`, `paused`, `successful`,
  /// `failed`), else `none`. Always `none` elsewhere.
  Future<String> androidDownloadStatus(AppRelease release) async {
    return await _androidInstaller()?.downloadStatusFor(release) ?? 'none';
  }
}
