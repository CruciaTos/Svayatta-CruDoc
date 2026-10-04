import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class RadViewFrame {
  const RadViewFrame({
    required this.url,
    required this.total,
    required this.previewEnd,
    required this.sha256,
  });

  final String url;
  final int total;
  final int previewEnd;
  final String sha256;

  factory RadViewFrame.fromMap(Map<String, dynamic> m) {
    return RadViewFrame(
      url: m['url'] as String? ?? '',
      total: (m['total'] as num?)?.toInt() ?? 0,
      previewEnd: (m['previewEnd'] as num?)?.toInt() ?? 0,
      sha256: m['sha256'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'url': url,
    'total': total,
    'previewEnd': previewEnd,
    'sha256': sha256,
  };
}

/// Metadata returned by the `getImagingView` callable.
class RadViewInfo {
  const RadViewInfo({
    required this.status,
    this.reason,
    this.codec,
    this.width,
    this.height,
    this.frames = 1,
    this.bitsStored,
    this.signed,
    this.slope = 1.0,
    this.intercept = 0.0,
    this.windowCenter,
    this.windowWidth,
    this.photometric,
    this.frameFiles = const [],
  });

  final String status;
  final String? reason;
  final String? codec;
  final int? width;
  final int? height;
  final int frames;
  final int? bitsStored;
  final bool? signed;
  final double slope;
  final double intercept;
  final double? windowCenter;
  final double? windowWidth;
  final String? photometric;
  final List<RadViewFrame> frameFiles;

  bool get ready => status == 'ready';

  factory RadViewInfo.fromMap(Map<String, dynamic> m) {
    final rawFrames = m['frameFiles'];
    final List<RadViewFrame> framesList = [];
    if (rawFrames is List) {
      for (final item in rawFrames) {
        if (item is Map) {
          framesList.add(RadViewFrame.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }

    return RadViewInfo(
      status: m['status'] as String? ?? '',
      reason: m['reason'] as String?,
      codec: m['codec'] as String?,
      width: (m['width'] as num?)?.toInt(),
      height: (m['height'] as num?)?.toInt(),
      frames: (m['frames'] as num?)?.toInt() ?? 1,
      bitsStored: (m['bitsStored'] as num?)?.toInt(),
      signed: m['signed'] as bool?,
      slope: (m['slope'] as num?)?.toDouble() ?? 1.0,
      intercept: (m['intercept'] as num?)?.toDouble() ?? 0.0,
      windowCenter: (m['windowCenter'] as num?)?.toDouble(),
      windowWidth: (m['windowWidth'] as num?)?.toDouble(),
      photometric: m['photometric'] as String?,
      frameFiles: framesList,
    );
  }
}

class _CachedInfo {
  final RadViewInfo info;
  final DateTime expiresAt;

  _CachedInfo(this.info, this.expiresAt);
}

/// Downloads viewing files part by part (see handoff Design).
class RadViewFetch {
  RadViewFetch({
    http.Client? httpClient,
    Future<RadViewInfo?> Function(String storagePath)? getInfo,
  })  : _client = httpClient ?? http.Client(),
        _getInfo = getInfo;

  static final RadViewFetch instance = RadViewFetch();

  final http.Client _client;
  final Future<RadViewInfo?> Function(String storagePath)? _getInfo;
  final Map<String, _CachedInfo> _cache = {};
  final Map<String, Future<File>> _inFlight = {};

  Future<RadViewInfo?> _defaultGetInfo(String storagePath) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('getImagingView');
      final result = await callable.call<dynamic>({'storagePath': storagePath});
      if (result.data is Map) {
        final map = Map<String, dynamic>.from(result.data as Map);
        return RadViewInfo.fromMap(map);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Calls `getImagingView`. Cached in memory for 9 minutes per storagePath
  /// (the URLs live 10). Returns null on any error.
  Future<RadViewInfo?> info(String storagePath) async {
    final cached = _cache[storagePath];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return cached.info;
    }
    _cache.remove(storagePath);

    try {
      final fetcher = _getInfo ?? _defaultGetInfo;
      final res = await fetcher(storagePath);
      if (res != null) {
        _cache[storagePath] = _CachedInfo(
          res,
          DateTime.now().add(const Duration(minutes: 9)),
        );
      }
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Makes sure `{studyDir}/.views/{imageId}/frame_{frame}.j2c` holds at least
  /// the preview (full == false) or the whole file (full == true). Returns the file.
  Future<File> ensure({
    required Directory studyDir,
    required String imageId,
    required String storagePath,
    required int frame,
    required bool full,
  }) {
    final viewsDir = Directory('${studyDir.path}/.views/$imageId');
    final file = File('${viewsDir.path}/frame_$frame.j2c');
    final sidecar = File('${viewsDir.path}/frame_$frame.json');

    final key = file.path;
    final previous = _inFlight[key];
    late final Future<File> current;
    current = (previous ?? Future<File>.value(file))
        .catchError((Object _) => file) // a failed earlier call mustn't fail this one
        .then((_) => _ensureFile(
              file: file,
              sidecar: sidecar,
              storagePath: storagePath,
              frame: frame,
              full: full,
            ))
        .whenComplete(() {
          if (identical(_inFlight[key], current)) _inFlight.remove(key);
        });
    _inFlight[key] = current;
    return current;
  }

  Future<File> _ensureFile({
    required File file,
    required File sidecar,
    required String storagePath,
    required int frame,
    required bool full,
  }) async {
    RadViewInfo? viewInfo = await info(storagePath);
    if (viewInfo == null || !viewInfo.ready) {
      throw StateError('Imaging view not ready for $storagePath');
    }
    if (frame < 0 || frame >= viewInfo.frameFiles.length) {
      throw RangeError('Frame $frame out of bounds (frames: ${viewInfo.frameFiles.length})');
    }

    RadViewFrame frameInfo = viewInfo.frameFiles[frame];

    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    int have = 0;
    if (await sidecar.exists()) {
      try {
        final Map<String, dynamic> sidecarJson =
            jsonDecode(await sidecar.readAsString());
        have = (sidecarJson['have'] as num?)?.toInt() ?? 0;
      } catch (_) {
        have = 0;
      }
    }

    if (await file.exists()) {
      final fileLen = await file.length();
      if (fileLen > have) {
        final raf = await file.open(mode: FileMode.writeOnlyAppend);
        await raf.truncate(have);
        await raf.close();
      } else if (fileLen < have) {
        have = fileLen;
      }
    } else {
      have = 0;
    }

    final int target = full ? frameInfo.total : frameInfo.previewEnd;
    if (have >= target) {
      return file;
    }

    Future<void> downloadRange({bool isRetry = false}) async {
      final request = http.Request('GET', Uri.parse(frameInfo.url));
      request.headers['Range'] = 'bytes=$have-${target - 1}';

      final streamedResponse = await _client.send(request);
      final statusCode = streamedResponse.statusCode;

      if (statusCode == 403 && !isRetry) {
        _cache.remove(storagePath);
        final refreshedInfo = await info(storagePath);
        if (refreshedInfo == null || !refreshedInfo.ready) {
          throw StateError('Failed to refresh imaging view for $storagePath');
        }
        viewInfo = refreshedInfo;
        frameInfo = viewInfo!.frameFiles[frame];
        return downloadRange(isRetry: true);
      }

      if (statusCode != 206 && !(statusCode == 200 && have == 0)) {
        throw HttpException('Unexpected HTTP status $statusCode downloading range');
      }

      final sink = file.openWrite(mode: FileMode.append);
      int bytesWritten = 0;

      try {
        if (statusCode == 200 && have == 0) {
          await for (final chunk in streamedResponse.stream) {
            final int remaining = target - bytesWritten;
            if (remaining <= 0) break;
            if (chunk.length <= remaining) {
              sink.add(chunk);
              bytesWritten += chunk.length;
            } else {
              sink.add(chunk.sublist(0, remaining));
              bytesWritten += remaining;
              break;
            }
          }
        } else {
          await for (final chunk in streamedResponse.stream) {
            sink.add(chunk);
            bytesWritten += chunk.length;
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      have += bytesWritten;

      final sidecarData = {
        'total': frameInfo.total,
        'previewEnd': frameInfo.previewEnd,
        'sha256': frameInfo.sha256,
        'have': have,
      };
      await sidecar.writeAsString(jsonEncode(sidecarData));
    }

    await downloadRange();

    if (have < target) {
      throw HttpException('Download ended early ($have of $target bytes)');
    }

    if (have == frameInfo.total) {
      final fileBytes = await file.readAsBytes();
      final digest = sha256.convert(fileBytes).toString();
      if (digest.toLowerCase() != frameInfo.sha256.toLowerCase()) {
        if (await file.exists()) await file.delete();
        if (await sidecar.exists()) await sidecar.delete();
        throw StateError('Checksum mismatch: expected ${frameInfo.sha256}, got $digest');
      }
    }

    return file;
  }
}
