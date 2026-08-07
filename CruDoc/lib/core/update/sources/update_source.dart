import 'package:doctor_management_app/core/update/models/app_release.dart';

/// Contract for "where does release metadata come from." The only
/// reason this exists as an interface rather than [UpdateService]
/// calling [GithubReleaseSource] directly: [UpdateService] never
/// imports `http` itself, and a test can supply a fake implementation
/// without hitting the network.
abstract interface class UpdateSource {
  /// Fetches the latest published release, or null if none exists yet
  /// (e.g. a brand-new repo with no releases). Implementations should
  /// throw an [UpdateException] subtype on failure rather than a raw
  /// exception, so [UpdateService.checkForUpdate] can surface a clean
  /// [CheckFailed] reason.
  Future<AppRelease?> fetchLatestRelease();
}
