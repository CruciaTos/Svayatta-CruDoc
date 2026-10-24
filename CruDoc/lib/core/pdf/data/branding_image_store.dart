import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

String sha256Hex(Uint8List b) => sha256.convert(b).toString();

class _PrepareImageArgs {
  const _PrepareImageArgs(this.raw, this.maxSide, this.cleanBackground);
  final Uint8List raw;
  final int maxSide;
  final bool cleanBackground;
}

Uint8List _prepareImageIsolate(_PrepareImageArgs args) {
  final raw = args.raw;
  final maxSide = args.maxSide;
  final cleanBackground = args.cleanBackground;

  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw const FormatException('Use a JPG, PNG or WebP picture');
  }
  var image = img.bakeOrientation(decoded);
  final longer = math.max(image.width, image.height);
  if (longer > maxSide) {
    if (image.width >= image.height) {
      image = img.copyResize(image, width: maxSide);
    } else {
      image = img.copyResize(image, height: maxSide);
    }
  }

  if (cleanBackground) {
    if (image.numChannels < 4) {
      image = image.convert(numChannels: 4);
    }
    for (final pixel in image) {
      final r = pixel.r;
      final g = pixel.g;
      final b = pixel.b;
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      if (lum >= 215) {
        pixel.a = 0;
      } else if (lum > 160) {
        pixel.a = ((215 - lum) / 55 * 255).round();
      }
    }
  }

  return Uint8List.fromList(img.encodePng(image));
}

/// Turns a picked file into a clean PNG: decode (JPG/PNG/WebP), apply
/// EXIF rotation, shrink so the longer side is at most [maxSide], and
/// optionally make the paper white transparent (signature photos).
/// Throws FormatException('Use a JPG, PNG or WebP picture') when it can't decode.
Future<Uint8List> prepareBrandingImage(
  Uint8List raw, {
  required int maxSide,
  bool cleanBackground = false,
}) async {
  if (raw.lengthInBytes > 15 * 1024 * 1024) {
    throw const FormatException('Picture must be 15 MB or smaller');
  }
  return compute(
    _prepareImageIsolate,
    _PrepareImageArgs(raw, maxSide, cleanBackground),
  );
}

enum BrandingImageProblem { none, notDownloaded, mismatch }

class BrandingImageResult {
  const BrandingImageResult(this.bytes, this.problem);
  final Uint8List? bytes;
  final BrandingImageProblem problem;
}

class BrandingImageStore {
  BrandingImageStore._();
  static final instance = BrandingImageStore._();

  final Map<String, Uint8List> _memoryCache = {};

  /// Bytes for [path] when they hash to [sha] (sha256, hex). Order:
  /// memory → device cache file → download (then cached). Null when
  /// missing, offline and not cached, or the hash doesn't match.
  Future<BrandingImageResult> load(String path, String sha) async {
    final cleanPath = path.trim();
    final cleanSha = sha.trim().toLowerCase();
    if (cleanPath.isEmpty || cleanSha.isEmpty) {
      return const BrandingImageResult(null, BrandingImageProblem.none);
    }

    // 1. Memory cache
    final mem = _memoryCache[cleanSha];
    if (mem != null) {
      return BrandingImageResult(mem, BrandingImageProblem.none);
    }

    // 2. Device cache file
    if (!kIsWeb) {
      try {
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/doc_assets/$cleanSha.png');
        if (await file.exists()) {
          final fileBytes = await file.readAsBytes();
          if (sha256Hex(fileBytes).toLowerCase() == cleanSha) {
            _memoryCache[cleanSha] = fileBytes;
            return BrandingImageResult(fileBytes, BrandingImageProblem.none);
          }
        }
      } catch (_) {}
    }

    // 3. Download from Firebase Storage
    try {
      final bytes = await FirebaseStorage.instance
          .ref(cleanPath)
          .getData(15 * 1024 * 1024)
          .timeout(const Duration(seconds: 10));

      if (bytes == null) {
        return const BrandingImageResult(
          null,
          BrandingImageProblem.notDownloaded,
        );
      }

      final downloadedSha = sha256Hex(bytes).toLowerCase();
      if (downloadedSha != cleanSha) {
        return const BrandingImageResult(null, BrandingImageProblem.mismatch);
      }

      await remember(cleanSha, bytes);
      return BrandingImageResult(bytes, BrandingImageProblem.none);
    } catch (_) {
      return const BrandingImageResult(
        null,
        BrandingImageProblem.notDownloaded,
      );
    }
  }

  /// Puts freshly uploaded bytes straight into the caches.
  Future<void> remember(String sha, Uint8List bytes) async {
    final cleanSha = sha.trim().toLowerCase();
    _memoryCache[cleanSha] = bytes;
    if (kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${dir.path}/doc_assets');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final file = File('${cacheDir.path}/$cleanSha.png');
      await file.writeAsBytes(bytes);
    } catch (_) {}
  }
}
