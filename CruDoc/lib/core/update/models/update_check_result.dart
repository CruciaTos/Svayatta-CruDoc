import 'package:doctor_management_app/core/update/models/app_release.dart';

/// Sealed result of [UpdateService.checkForUpdate] — design principle
/// #4: "explicit typed states, not booleans." `features/update`'s
/// `UpdateController` and presentation widgets switch on this rather
/// than inspecting a raw exception or a nullable release.
///
/// Matches the contract already relied on by `update_controller.dart`,
/// `update_banner.dart`, and `update_available_dialog.dart` — nothing
/// in `features/update/` needs to change to consume this.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// The installed app is already on the latest published version (or
/// newer — e.g. a local dev build). Nothing to show.
class UpToDate extends UpdateCheckResult {
  const UpToDate();
}

/// A newer release than the installed version was found. Carries the
/// full [AppRelease] so the UI can show its notes/version and, if the
/// user proceeds, hand it straight to [UpdateService.startDownloadAndInstall].
class UpdateAvailable extends UpdateCheckResult {
  final AppRelease release;
  const UpdateAvailable(this.release);
}

/// The check itself failed — network error, unreadable GitHub response,
/// no releases published yet, etc. [reason] is a short, user-presentable
/// string; [UpdateService] never lets a raw exception escape to this
/// boundary (design principle #4).
class CheckFailed extends UpdateCheckResult {
  final String reason;
  const CheckFailed(this.reason);
}
