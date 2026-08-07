// lib/features/update/providers/update_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/update/models/update_check_result.dart';
import 'package:doctor_management_app/core/update/models/update_progress.dart';
import 'package:doctor_management_app/core/update/update_preferences.dart';
import 'package:doctor_management_app/core/update/update_service.dart';
import 'package:doctor_management_app/features/update/controllers/update_controller.dart';

// Assumes the core/update/* contract documented at the top of
// update_controller.dart (that layer isn't built yet).

/// Singleton [UpdateService] — the only facade [UpdateController] talks
/// to for checking/downloading/installing updates. Builds its own
/// `GithubReleaseSource` / `VersionComparator` / `UpdateInstallerFactory`
/// internally, the same way `VisitRepository()` / `RevenueRepository()`
/// build their own Firestore access rather than taking it as a
/// constructor argument — no manual wiring needed here.
final updateServiceProvider =
    Provider<UpdateService>((ref) => UpdateService());

/// Singleton [UpdatePreferences] — thin `shared_preferences` wrapper for
/// `lastCheckedAt` / `skippedVersion` / `lastNotifiedVersion`, the state
/// that makes throttling and "don't nag" behavior possible without any
/// server-side flag.
final updatePreferencesProvider =
    Provider<UpdatePreferences>((ref) => UpdatePreferences());

/// Read-only view of [UpdateController]'s current [UpdateCheckResult].
/// Lets a widget that only cares "is there an update" — `UpdateBanner` —
/// watch just this instead of the whole controller state shape.
final updateCheckResultProvider = Provider<UpdateCheckResult?>((ref) {
  return ref.watch(updateControllerProvider).checkResult;
});

/// Read-only view of the in-flight [UpdateProgress], watched by
/// `UpdateProgressSheet` while a download/install is running.
final updateProgressProvider = Provider<UpdateProgress?>((ref) {
  return ref.watch(updateControllerProvider).progress;
});