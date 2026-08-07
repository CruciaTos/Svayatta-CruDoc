import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:doctor_management_app/core/update/models/app_release.dart';
import 'package:doctor_management_app/core/update/models/release_asset.dart';
import 'package:doctor_management_app/core/update/models/update_manifest.dart';
import 'package:doctor_management_app/core/update/sources/update_source.dart';
import 'package:doctor_management_app/core/update/update_exceptions.dart';
import 'package:doctor_management_app/core/update/version/version_comparator.dart';

/// The only concrete [UpdateSource]. Talks exclusively to GitHub's
/// public REST API for `CruciaTos/Svayatta-CruDoc` — no Firestore, no
/// Remote Config, no third-party update service (architecture doc's
/// scope statement). All GitHub-API-response-shape knowledge lives
/// here and nowhere else in the update framework.
class GithubReleaseSource implements UpdateSource {
  GithubReleaseSource({http.Client? client, String? repoSlug})
      : _client = client ?? http.Client(),
        _repoSlug = repoSlug ?? _defaultRepoSlug;

  static const String _defaultRepoSlug = 'CruciaTos/Svayatta-CruDoc';
  static const String _updateManifestAssetName = 'update.json';
  static const Duration _requestTimeout = Duration(seconds: 15);

  final http.Client _client;
  final String _repoSlug;

  Uri get _latestReleaseUri => Uri.parse('https://api.github.com/repos/$_repoSlug/releases/latest');

  /// GitHub requires a `User-Agent` on REST API requests (a missing one
  /// gets a 403); `Accept`/`X-GitHub-Api-Version` pin the response shape
  /// this parsing code was written against. No auth token — the repo is
  /// public, so none is needed to read release metadata.
  Map<String, String> get _apiHeaders => const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'CruDoc-UpdateChecker',
      };

  @override
  Future<AppRelease?> fetchLatestRelease() async {
    final http.Response response;
    try {
      response = await _client.get(_latestReleaseUri, headers: _apiHeaders).timeout(_requestTimeout);
    } catch (e) {
      throw UpdateCheckException('Could not reach GitHub to check for updates: $e');
    }

    // No releases published yet — a valid, non-error state, not a failure.
    if (response.statusCode == 404) return null;

    if (response.statusCode != 200) {
      throw UpdateCheckException('GitHub returned HTTP ${response.statusCode} while checking for updates.');
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const UpdateCheckException('Received an unreadable response while checking for updates.');
    }

    final assets = _parseAssets(json['assets']);
    final tag = json['tag_name'] as String? ?? '';
    final version = VersionComparator.normalize(tag);
    final notes = (json['body'] as String? ?? '').trim();
    final publishedAt = DateTime.tryParse(json['published_at'] as String? ?? '') ?? DateTime.now();

    final manifest = await _fetchManifest(assets);

    return AppRelease(
      version: version,
      tag: tag,
      notes: notes,
      publishedAt: publishedAt,
      assets: assets,
      manifest: manifest,
    );
  }

  List<ReleaseAsset> _parseAssets(dynamic rawAssets) {
    final list = rawAssets is List ? rawAssets : const [];
    return list
        .whereType<Map>()
        .map((a) => ReleaseAsset.fromJson(a.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Resolves and parses the `update.json` asset if the release carries
  /// one. A missing or unparsable manifest is treated as "no manifest"
  /// rather than a failed check — design principle #2 treats it as a
  /// convenience layer on top of the tag/notes/assets that are always
  /// present, not a hard requirement.
  Future<UpdateManifest?> _fetchManifest(List<ReleaseAsset> assets) async {
    ReleaseAsset? manifestAsset;
    for (final asset in assets) {
      if (asset.name == _updateManifestAssetName) {
        manifestAsset = asset;
        break;
      }
    }
    if (manifestAsset == null || manifestAsset.downloadUrl.isEmpty) return null;

    try {
      final response = await _client
          .get(Uri.parse(manifestAsset.downloadUrl), headers: _apiHeaders)
          .timeout(_requestTimeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return UpdateManifest.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
