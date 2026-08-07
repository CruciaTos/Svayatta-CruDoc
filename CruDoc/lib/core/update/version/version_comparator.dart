/// Pure semver-style comparison, used to decide whether a GitHub release
/// is newer than the installed app. No I/O, no Flutter/platform
/// dependency — architecture doc §4: "unit-testable."
///
/// Supports the shapes this project actually produces/consumes:
/// git tags (`v1.4.2`), `pubspec.yaml`'s `version:` (`1.4.2` or
/// `1.4.2+7`), and basic pre-release suffixes (`1.5.0-beta.1`) per
/// semver precedence rules, in case a beta channel is added later
/// (architecture doc §8).
abstract final class VersionComparator {
  /// Strips a leading `v`/`V` from a git tag (`v1.4.2` → `1.4.2`).
  /// Leaves an already-bare version string untouched.
  static String normalize(String rawVersion) {
    final trimmed = rawVersion.trim();
    if (trimmed.isEmpty) return trimmed;
    final first = trimmed[0];
    if (first == 'v' || first == 'V') return trimmed.substring(1);
    return trimmed;
  }

  /// Compares two version strings. Returns a negative number if [a] is
  /// older than [b], zero if equal precedence, positive if [a] is newer.
  /// Accepts either bare (`1.4.2`) or tagged (`v1.4.2`) input — both
  /// sides are normalized before comparing.
  static int compare(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);

    for (var i = 0; i < 3; i++) {
      final diff = pa.core[i] - pb.core[i];
      if (diff != 0) return diff.sign;
    }

    // Equal major.minor.patch — a pre-release has *lower* precedence
    // than the normal release it precedes (semver 11.3): 1.5.0-beta < 1.5.0.
    if (pa.preRelease == null && pb.preRelease == null) return 0;
    if (pa.preRelease == null) return 1;
    if (pb.preRelease == null) return -1;
    return _comparePreRelease(pa.preRelease!, pb.preRelease!);
  }

  /// Convenience wrapper for the common call site: "does [candidate]
  /// represent a newer release than [current]?"
  static bool isNewer(String candidate, String current) => compare(candidate, current) > 0;

  static _ParsedVersion _parse(String raw) {
    final normalized = normalize(raw);
    // Build metadata (`+7`) never affects precedence — drop it first.
    final withoutBuild = normalized.split('+').first;
    final dashIndex = withoutBuild.indexOf('-');
    final corePart = dashIndex == -1 ? withoutBuild : withoutBuild.substring(0, dashIndex);
    final preRelease = dashIndex == -1 ? null : withoutBuild.substring(dashIndex + 1);

    final segments = corePart.split('.');
    final core = List<int>.generate(3, (i) {
      if (i >= segments.length) return 0;
      return int.tryParse(segments[i]) ?? 0;
    });

    return _ParsedVersion(core, preRelease);
  }

  /// Dotted pre-release identifiers compared per semver precedence
  /// rules: numeric identifiers compare numerically and always sort
  /// before alphanumeric ones; a shorter identifier list has lower
  /// precedence when it's a prefix of the longer one.
  static int _comparePreRelease(String a, String b) {
    final aIds = a.split('.');
    final bIds = b.split('.');
    final len = aIds.length > bIds.length ? aIds.length : bIds.length;

    for (var i = 0; i < len; i++) {
      if (i >= aIds.length) return -1;
      if (i >= bIds.length) return 1;

      final aId = aIds[i];
      final bId = bIds[i];
      final aNum = int.tryParse(aId);
      final bNum = int.tryParse(bId);

      if (aNum != null && bNum != null) {
        final diff = aNum - bNum;
        if (diff != 0) return diff.sign;
      } else if (aNum != null) {
        return -1;
      } else if (bNum != null) {
        return 1;
      } else {
        final cmp = aId.compareTo(bId);
        if (cmp != 0) return cmp.sign;
      }
    }
    return 0;
  }
}

class _ParsedVersion {
  final List<int> core;
  final String? preRelease;
  const _ParsedVersion(this.core, this.preRelease);
}
