import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// Serves the bundled 3D muscle viewer (`assets/muscle_viewer/`) on
/// 127.0.0.1 so the WebView loads it over plain HTTP. Loading from file://
/// would block the ES modules and the model fetch.
///
/// Binds to the loopback interface only (no firewall prompt, not reachable
/// from the network) and serves nothing but those static, public files.
class MuscleAssetServer {
  MuscleAssetServer._();

  static const _root = 'assets/muscle_viewer/';
  static Future<Uri>? _ready;

  /// The viewer's base URL; starts the server on first use.
  static Future<Uri> ensureStarted() => _ready ??= _start();

  static Future<Uri> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    return Uri.parse('http://127.0.0.1:${server.port}/');
  }

  static Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      var path = Uri.decodeComponent(req.uri.path);
      if (path.isEmpty || path == '/') path = '/index.html';
      if (path.contains('..')) {
        res.statusCode = HttpStatus.forbidden;
        return;
      }
      final data = await rootBundle.load('$_root${path.substring(1)}');
      res.headers.contentType = _type(path);
      res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
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
      'js' => ContentType('text', 'javascript', charset: 'utf-8'),
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'json' => ContentType.json,
      'glb' => ContentType('model', 'gltf-binary'),
      'txt' => ContentType.text,
      _ => ContentType.binary,
    };
  }
}
