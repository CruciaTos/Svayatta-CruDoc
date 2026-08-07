// lib/features/update/controllers/update_controller.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/update/models/app_release.dart';
import 'package:doctor_management_app/core/update/models/update_check_result.dart';
import 'package:doctor_management_app/core/update/models/update_progress.dart';
import 'package:doctor_management_app/core/update/update_preferences.dart';
import 'package:doctor_management_app/features/update/providers/update_providers.dart';


// ---------------------------------------------------------------------
// Expected core/update/* contract (not built yet — see "CruDoc Update
// Framework — Architecture Plan", §3/§4/§6). This file is written
// against the shapes below; nothing here should need to change once
// core/update matches them.
//
// UpdateService (core/update/update_service.dart)
//   No-arg constructor `UpdateService()`.
//   Future<UpdateCheckResult> checkForUpdate()
//   Stream<UpdateProgress> startDownloadAndInstall(AppRelease release)
//   Failures resolve into CheckFailed / a `failed` UpdateProgress
//   rather than throwing — see UpdateCheckResult/UpdateProgressState
//   below (design principle #4: explicit typed states, not exceptions,
//   at this boundary).
//
// UpdatePreferences (core/update/update_preferences.dart)
//   No-arg constructor `UpdatePreferences()`.
//   Future<DateTime?> getLastCheckedAt()
//   Future<void> setLastCheckedAt(DateTime time)
//   Future<String?> getSkippedVersion()
//   Future<void> setSkippedVersion(String version)
//   Future<void> setLastNotifiedVersion(String version)
//
// UpdateCheckResult (core/update/models/update_check_result.dart)
//   sealed class UpdateCheckResult {}
//   class UpToDate extends UpdateCheckResult { const UpToDate(); }
//   class UpdateAvailable extends UpdateCheckResult {
//     final AppRelease release; UpdateAvailable(this.release);
//   }
//   class CheckFailed extends UpdateCheckResult {
//     final String reason; const CheckFailed(this.reason);
//   }
//
// AppRelease (core/update/models/app_release.dart)
//   String version; String tag; String notes; DateTime publishedAt;
//   List<ReleaseAsset> assets; UpdateManifest? manifest;
//
// UpdateManifest (core/update/models/update_manifest.dart)
//   bool forceUpdate; String minSupportedVersion; String changelog;
//
// UpdateProgress (core/update/models/update_progress.dart)
//   UpdateProgressState state; int bytesDownloaded; int totalBytes;
//   double percent;
//   enum UpdateProgressState {
//     idle, downloading, verifying, readyToInstall, installing, failed
//   }
// ---------------------------------------------------------------------

/// How often an unattended startup check is allowed to hit the GitHub
/// API — design principle #6 ("no nagging"). A manual "Check for
/// updates" tap always bypasses this via [UpdateController.checkForUpdate]'s
/// `force` flag.
const Duration _kUpdateCheckThrottle = Duration(hours: 6);

/// UI-facing state for the update feature. `UpdateAvailableDialog` /
/// `UpdateBanner` watch [checkResult]; `UpdateProgressSheet` watches
/// [progress]. Neither presentation widget needs to know about
/// [UpdateService] or [UpdatePreferences] directly.
class UpdateControllerState {
  /// True while a [UpdateController.checkForUpdate] call is in flight.
  final bool isChecking;

  /// Result of the most recent completed check, or null before the
  /// first check has ever run.
  final UpdateCheckResult? checkResult;

  /// Snapshot of an in-flight download/install, or null when nothing is
  /// downloading.
  final UpdateProgress? progress;

  /// True once the user has tapped "Later" on the current [checkResult].
  /// Presentation widgets should stop showing the dialog/banner while
  /// this is true — it resets on the next [UpdateController.checkForUpdate] call.
  final bool dismissedForSession;

  const UpdateControllerState({
    this.isChecking = false,
    this.checkResult,
    this.progress,
    this.dismissedForSession = false,
  });

  UpdateControllerState copyWith({
    bool? isChecking,
    UpdateCheckResult? checkResult,
    UpdateProgress? progress,
    bool? dismissedForSession,
    bool clearProgress = false,
  }) {
    return UpdateControllerState(
      isChecking: isChecking ?? this.isChecking,
      checkResult: checkResult ?? this.checkResult,
      progress: clearProgress ? null : (progress ?? this.progress),
      dismissedForSession: dismissedForSession ?? this.dismissedForSession,
    );
  }
}

/// Orchestrates the update feature's UI-facing state. Talks to
/// [UpdateService] (the actual check/download/install work) and
/// [UpdatePreferences] (throttling + skip/notified bookkeeping) so
/// nothing in `presentation/` ever imports either directly.
///
/// Nothing runs automatically from [build] — per the architecture doc's
/// §7 integration points, `main.dart` is responsible for kicking off the
/// throttled startup check (`checkForUpdate()`, not forced) after
/// `runApp`, and `profile_screen.dart`'s manual "Check for updates"
/// action calls `checkForUpdate(force: true)`.
class UpdateController extends Notifier<UpdateControllerState> {
  @override
  UpdateControllerState build() => const UpdateControllerState();

  /// Asks [UpdateService] whether a newer release exists.
  ///
  /// Respects [_kUpdateCheckThrottle] via [UpdatePreferences] unless
  /// [force] is true. Resets [UpdateControllerState.dismissedForSession]
  /// on every call so a newly-available release is shown again even if
  /// a previous one was dismissed.
  Future<void> checkForUpdate({bool force = false}) async {
    final prefs = ref.read(updatePreferencesProvider);

    if (!force) {
      final lastCheckedAt = await prefs.getLastCheckedAt();
      if (lastCheckedAt != null &&
          DateTime.now().difference(lastCheckedAt) < _kUpdateCheckThrottle) {
        return;
      }
    }

    state = state.copyWith(
      isChecking: true,
      dismissedForSession: false,
      clearProgress: true,
    );

    try {
      final service = ref.read(updateServiceProvider);
      final result = await service.checkForUpdate();
      await prefs.setLastCheckedAt(DateTime.now());

      final resolved = await _applySkipPreference(result, prefs);
      state = state.copyWith(isChecking: false, checkResult: resolved);
    } catch (e) {
      // Defensive backstop — see the contract note above: UpdateService
      // is expected to resolve failures into CheckFailed itself rather
      // than throwing.
      state = state.copyWith(
        isChecking: false,
        checkResult: CheckFailed(e.toString()),
      );
    }
  }

  /// If the found release's version matches what the user previously
  /// chose to skip, downgrade an [UpdateAvailable] result to [UpToDate]
  /// so it doesn't reappear. A force-update release is never skippable.
  Future<UpdateCheckResult> _applySkipPreference(
    UpdateCheckResult result,
    UpdatePreferences prefs,
  ) async {
    if (result is! UpdateAvailable) return result;

    final release = result.release;
    if (release.manifest?.forceUpdate == true) return result;

    final skipped = await prefs.getSkippedVersion();
    if (skipped != null && skipped == release.version) {
      return const UpToDate();
    }
    return result;
  }

  /// Begins downloading + installing [release], streaming progress into
  /// [UpdateControllerState.progress] as it arrives. Called once, from
  /// `UpdateProgressSheet.initState` — see that file's doc comment.
  Future<void> startUpdate(AppRelease release) async {
    final service = ref.read(updateServiceProvider);
    try {
      await for (final progress in service.startDownloadAndInstall(release)) {
        state = state.copyWith(progress: progress);
      }
    } catch (e, st) {
      // Defensive backstop — a broken/unhandled stream error shouldn't
      // crash the controller. UpdateProgressState.failed is the
      // expected path for a normal download/verify/install failure.
      if (kDebugMode) {
        debugPrint('UpdateController.startUpdate failed unexpectedly: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }

  /// User tapped "Later" — hide the dialog/banner for this session
  /// without remembering anything past it, so it resurfaces on the next
  /// throttled or manual check. Also stamps `lastNotifiedVersion` so the
  /// persisted field reflects what was actually shown, ready for a
  /// future cross-restart cooldown refinement.
  Future<void> remindLater() async {
    final result = state.checkResult;
    if (result is UpdateAvailable) {
      await ref
          .read(updatePreferencesProvider)
          .setLastNotifiedVersion(result.release.version);
    }
    state = state.copyWith(dismissedForSession: true);
  }

  /// User tapped "Skip" — persists the current release's version as
  /// [UpdatePreferences.getSkippedVersion] so [checkForUpdate] silently
  /// treats it as up to date until a *newer* version is published.
  Future<void> skipThisVersion() async {
    final result = state.checkResult;
    if (result is! UpdateAvailable) return;

    await ref
        .read(updatePreferencesProvider)
        .setSkippedVersion(result.release.version);

    state = state.copyWith(
      checkResult: const UpToDate(),
      dismissedForSession: false,
    );
  }

  /// Resets progress back to idle, e.g. so a retry starts clean.
  void clearProgress() => state = state.copyWith(clearProgress: true);
}

/// The single [UpdateController] instance the whole update feature
/// reads/watches through.
final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateControllerState>(
  UpdateController.new,
);