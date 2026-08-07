/// One entry under `update.json`'s `"platforms"` map — architecture doc
/// §6. For a downloadable platform (Windows, Android) this carries
/// [asset] + [sha256] so the matching [ReleaseAsset] can be found and
/// verified. For a store-distributed platform (iOS, later) it instead
/// carries a [url] to the App Store/TestFlight listing — no asset, no
/// checksum, nothing to download.
class UpdateManifestPlatform {
  /// File name of the matching [ReleaseAsset] on the release (e.g.
  /// `CruDoc-windows-1.4.2.exe`). Null for store-distributed platforms.
  final String? asset;

  /// Expected sha256 hex digest of the downloaded asset. Null means
  /// "no checksum published" — verification is skipped rather than
  /// failed, matching design principle #2 (`update.json` is a
  /// convenience layer, not a hard requirement).
  final String? sha256;

  /// Size in bytes, if `update.json` chose to duplicate it here instead
  /// of relying on the GitHub-reported [ReleaseAsset.size].
  final int? size;

  /// Store/TestFlight URL for a platform that isn't distributed via a
  /// downloadable asset (the future iOS case — see [IosUpdateInstaller]).
  final String? url;

  const UpdateManifestPlatform({this.asset, this.sha256, this.size, this.url});

  factory UpdateManifestPlatform.fromJson(Map<String, dynamic> json) {
    return UpdateManifestPlatform(
      asset: json['asset'] as String?,
      sha256: json['sha256'] as String?,
      size: (json['size'] as num?)?.toInt(),
      url: json['url'] as String?,
    );
  }
}

/// Parsed `update.json` — the structured manifest asset attached to
/// every GitHub Release (architecture doc §6), layered on top of the
/// release's own tag/notes to make parsing robust instead of dependent
/// on free-text release notes.
///
/// Optional: [GithubReleaseSource] treats a missing or unparsable
/// `update.json` as "no manifest" rather than a failed check — the
/// release itself (tag, notes, assets) is still usable without it, just
/// without checksum verification or a force-update flag.
class UpdateManifest {
  /// Bumped only on a breaking change to this JSON shape. `platforms`
  /// can gain new keys (like `"ios"`) without a schema break.
  final int schemaVersion;

  /// The version this manifest describes — should match the release
  /// tag, kept separately since the manifest is hand/CI-authored.
  final String version;

  /// Oldest installed version still allowed to run at all. Currently
  /// informational; [UpdateService] doesn't hard-block below this yet
  /// (see architecture doc §8 — channel/force semantics are an open
  /// decision), but it's parsed and available for that later.
  final String minSupportedVersion;

  /// When true, [UpdateAvailableDialog] is shown non-dismissible with
  /// no Later/Skip — design principle #5's "clearly-flagged force path
  /// for critical fixes."
  final bool forceUpdate;

  /// Short, structured changelog summary. Separate from
  /// [AppRelease.notes] (the release's free-text body) — presentation
  /// currently prefers `AppRelease.notes` for "What's new" since it's
  /// always present; this is kept for a future richer changelog UI.
  final String changelog;

  /// Per-platform asset/checksum/store-url info, keyed by `"windows"`,
  /// `"android"`, and later `"ios"`. Look up via [platformFor] rather
  /// than indexing directly.
  final Map<String, UpdateManifestPlatform> platforms;

  const UpdateManifest({
    required this.schemaVersion,
    required this.version,
    required this.minSupportedVersion,
    required this.forceUpdate,
    required this.changelog,
    required this.platforms,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final platformsJson = (json['platforms'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

    return UpdateManifest(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      version: json['version'] as String? ?? '',
      minSupportedVersion: json['minSupportedVersion'] as String? ?? '0.0.0',
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      changelog: json['changelog'] as String? ?? '',
      platforms: platformsJson.map(
        (key, value) => MapEntry(
          key,
          UpdateManifestPlatform.fromJson((value as Map).cast<String, dynamic>()),
        ),
      ),
    );
  }

  /// Looks up this manifest's info for a given platform key (`"windows"`,
  /// `"android"`, `"ios"`). Returns null if the manifest doesn't mention
  /// that platform at all.
  UpdateManifestPlatform? platformFor(String key) => platforms[key];
}
