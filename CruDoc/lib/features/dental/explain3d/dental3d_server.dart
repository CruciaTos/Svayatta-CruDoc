import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Serves the bundled "show the patient" 3D page (`assets/dental3d/`) on
/// 127.0.0.1 only, behind a random per-open token: `/v/<token>/<file>`.
/// The WebView loads over plain HTTP because file:// would block ES modules,
/// fetches and the Draco WASM decoder. Read-only; nothing else is served.
class Dental3dServer {
  /// [loadAsset] reads a bundled file by its asset key (tests pass a fake).
  Dental3dServer({Future<ByteData> Function(String key)? loadAsset})
    : _loadAsset = loadAsset ?? rootBundle.load;

  static final Dental3dServer instance = Dental3dServer();

  static const _root = 'assets/dental3d/';

  final Future<ByteData> Function(String key) _loadAsset;
  final Set<String> _tokens = {};
  HttpServer? _http;
  Future<int>? _port;

  Future<int> _ensureStarted() => _port ??= _start();

  Future<int> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http = server;
    server.listen(_handle);
    return server.port;
  }

  /// Registers a fresh token and returns the page to load.
  Future<({Uri page, String token})> open() async {
    final port = await _ensureStarted();
    final rng = math.Random.secure();
    final token = base64Url
        .encode(List<int>.generate(32, (_) => rng.nextInt(256)))
        .replaceAll('=', '');
    _tokens.add(token);
    return (
      page: Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        path: '/v/$token/index.html',
      ),
      token: token,
    );
  }

  void revoke(String token) => _tokens.remove(token);

  /// Stops the server and forgets every token.
  Future<void> close() async {
    _tokens.clear();
    final http = _http;
    _http = null;
    _port = null;
    await http?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff');
    try {
      if (req.method != 'GET') {
        res.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final path = Uri.decodeComponent(req.uri.path);
      if (path.contains('..') || path.contains('\\') || path.contains('//')) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      // /v/<token>/<file...>
      final parts = path.split('/');
      if (parts.length < 4 ||
          parts[0].isNotEmpty ||
          parts[1] != 'v' ||
          !_tokens.contains(parts[2])) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final rest = parts.sublist(3);
      if (rest.any((s) => s.isEmpty || s == '.')) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final rel = rest.join('/');
      final data = await _loadAsset('$_root$rel');
      res.headers.contentType = _type(rel);
      res.contentLength = data.lengthInBytes;
      res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } catch (_) {
      res.statusCode = HttpStatus.notFound;
    } finally {
      await res.close();
    }
  }

  static ContentType _type(String path) {
    final ext = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
    return switch (ext) {
      'html' => ContentType.html,
      'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'json' => ContentType.json,
      'glb' => ContentType('model', 'gltf-binary'),
      'gltf' => ContentType('model', 'gltf+json'),
      'wasm' => ContentType('application', 'wasm'),
      'png' => ContentType('image', 'png'),
      'webp' => ContentType('image', 'webp'),
      'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
      'svg' => ContentType('image', 'svg+xml'),
      'woff2' => ContentType('font', 'woff2'),
      'ttf' => ContentType('font', 'ttf'),
      _ => ContentType.binary,
    };
  }
}
