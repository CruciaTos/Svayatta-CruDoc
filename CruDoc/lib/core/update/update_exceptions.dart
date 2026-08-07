/// Base type for every update-related domain error, following the same
/// pattern as `core/errors/visit_exceptions.dart`: a sealed base plus
/// typed subtypes, so calling code can `catch (e) { if (e is
/// UpdateException) ... }` generically or match a specific subtype.
///
/// In practice these rarely escape [UpdateService] — design principle
/// #4 has it catch its own internals and resolve them into
/// [CheckFailed] / [UpdateProgressState.failed] instead. They exist so
/// [GithubReleaseSource] and the platform installers have a typed,
/// message-carrying way to signal *why* before that translation happens.
sealed class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);

  @override
  String toString() => message;
}

/// Fetching or parsing release metadata failed — network error,
/// unexpected GitHub API response, unreadable JSON.
class UpdateCheckException extends UpdateException {
  const UpdateCheckException(super.message);
}

/// Downloading a release asset (installer/package) failed — missing
/// asset, HTTP error mid-download, or the manifest not naming an asset
/// for the current platform at all.
class UpdateDownloadException extends UpdateException {
  const UpdateDownloadException(super.message);
}

/// The downloaded file's sha256 didn't match `update.json`'s published
/// checksum. Never bypassed — a failed verification always blocks install.
class UpdateVerificationException extends UpdateException {
  const UpdateVerificationException(super.message);
}

/// Handing the verified file off to the platform's own installer failed
/// — e.g. the Windows process couldn't launch, or the Android
/// install-package intent couldn't be dispatched.
class UpdateInstallException extends UpdateException {
  const UpdateInstallException(super.message);
}
