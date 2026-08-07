/// One file attached to a GitHub Release — either a platform installer
/// (`CruDoc-windows-1.4.2.exe`, `CruDoc-android-1.4.2.apk`) or the
/// structured `update.json` manifest asset.
///
/// Deliberately just a dumb data holder: [GithubReleaseSource] is the
/// only place that knows how to turn a raw GitHub API asset object into
/// one of these.
class ReleaseAsset {
  /// Exact file name as uploaded to the release (e.g.
  /// `CruDoc-windows-1.4.2.exe`). This is what [AppRelease.assetNamed]
  /// and [UpdateManifestPlatform.asset] match against.
  final String name;

  /// Direct, public download URL (GitHub's `browser_download_url`) —
  /// no auth header needed since the repo is public.
  final String downloadUrl;

  /// Size in bytes as reported by GitHub. Used as a fallback total for
  /// progress reporting when `update.json` doesn't also carry a size.
  final int size;

  /// MIME type as reported by GitHub (e.g. `application/vnd.microsoft.portable-executable`).
  final String contentType;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.contentType,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: json['name'] as String? ?? '',
      downloadUrl: json['browser_download_url'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      contentType: json['content_type'] as String? ?? 'application/octet-stream',
    );
  }

  @override
  String toString() => 'ReleaseAsset($name, $size bytes)';
}
