import 'package:doctor_management_app/core/update/models/release_asset.dart';
import 'package:doctor_management_app/core/update/models/update_manifest.dart';

/// Normalized view of one GitHub Release — what [GithubReleaseSource]
/// maps the raw API response into, and the only release shape the rest
/// of the update framework (and `features/update/*`) ever sees.
class AppRelease {
  /// Normalized semver, e.g. `1.4.2` — the git tag with a leading `v`
  /// stripped via [VersionComparator.normalize]. This is what
  /// [VersionComparator] compares against the installed app's version.
  final String version;

  /// Raw git tag as published, e.g. `v1.4.2`. Kept alongside [version]
  /// since the tag is "the primary version signal" (architecture doc
  /// §6) even though comparisons run against the normalized form.
  final String tag;

  /// The release's free-text body from GitHub — shown as "What's new"
  /// in [UpdateAvailableDialog]. Independent of [UpdateManifest.changelog].
  final String notes;

  /// When this release was published, per GitHub's `published_at`.
  final DateTime publishedAt;

  /// Every file attached to the release, including `update.json` itself.
  /// Platform installers resolve their target file from here by name,
  /// via [assetNamed], using the file name recorded in [manifest].
  final List<ReleaseAsset> assets;

  /// Parsed `update.json`, if the release carries one. Null means the
  /// release is still usable (version/notes/assets all work), just
  /// without checksum verification, `forceUpdate`, or `minSupportedVersion`.
  final UpdateManifest? manifest;

  const AppRelease({
    required this.version,
    required this.tag,
    required this.notes,
    required this.publishedAt,
    required this.assets,
    this.manifest,
  });

  /// Finds the asset with exactly this file name, or null if the
  /// release doesn't carry one — e.g. when [manifest] names an asset
  /// (`update.json`'s `platforms.windows.asset`) that wasn't actually
  /// uploaded to the release.
  ReleaseAsset? assetNamed(String name) {
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }

  @override
  String toString() => 'AppRelease($tag, ${assets.length} asset(s))';
}
