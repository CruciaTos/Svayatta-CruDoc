import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

/// Where the 3D viewer page was opened: the page to load and the base path
/// the page reads the scan from.
class CbctOpened {
  const CbctOpened({required this.page, required this.base, required this.token});

  final Uri page;

  /// e.g. `/v/<token>/`; the page fetches `meta.json` and `full.i16` from here.
  final String base;
  final String token;
}

/// Serves the bundled CBCT viewer (`assets/cbct_viewer/`) and, behind a
/// per-open token, one scan's pack folder, on 127.0.0.1 only. The WebView
/// loads over plain HTTP because file:// would block ES modules and fetches.
class CbctServer {
  CbctServer._();

  static final CbctServer instance = CbctServer._();

  static const _root = 'assets/cbct_viewer/';

  /// The only files a pack folder may serve.
  static const _packFiles = {'meta.json', 'full.i16', 'mid.i16', 'preview.i16'};

  final Map<String, Directory> _packs = {};
  Future<int>? _port;

  Future<int> _ensureStarted() => _port ??= _start();

  Future<int> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    return server.port;
  }

  /// Registers [pack] under a fresh token and returns the page to load.
  Future<CbctOpened> open(Directory pack) async {
    final port = await _ensureStarted();
    final rng = math.Random.secure();
    final token = base64Url
        .encode(List<int>.generate(32, (_) => rng.nextInt(256)))
        .replaceAll('=', '');
    _packs[token] = pack;
    return CbctOpened(
      page: Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '/index.html'),
      base: '/v/$token/',
      token: token,
    );
  }

  void revoke(String token) => _packs.remove(token);

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
      if (path.contains('..') || path.contains('\\')) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      if (path.startsWith('/v/')) {
        await _servePack(path, res);
      } else {
        await _serveAsset(path == '/' ? '/index.html' : path, res);
      }
    } catch (_) {
      res.statusCode = HttpStatus.notFound;
    } finally {
      await res.close();
    }
  }

  Future<void> _servePack(String path, HttpResponse res) async {
    // /v/<token>/<file>
    final parts = path.split('/');
    final dir = parts.length == 4 ? _packs[parts[2]] : null;
    final name = parts.length == 4 ? parts[3] : '';
    if (dir == null || !_packFiles.contains(name)) {
      res.statusCode = HttpStatus.notFound;
      return;
    }
    final file = File(p.join(dir.path, name));
    if (!await file.exists()) {
      res.statusCode = HttpStatus.notFound;
      return;
    }
    res.headers.contentType = _type(name);
    res.contentLength = await file.length();
    await res.addStream(file.openRead());
  }

  Future<void> _serveAsset(String path, HttpResponse res) async {
    final data = await rootBundle.load('$_root${path.substring(1)}');
    res.headers.contentType = _type(path);
    res.contentLength = data.lengthInBytes;
    res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  static ContentType _type(String path) {
    final ext = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
    return switch (ext) {
      'html' => ContentType.html,
      'js' => ContentType('text', 'javascript', charset: 'utf-8'),
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'json' => ContentType.json,
      'ttf' => ContentType('font', 'ttf'),
      'woff2' => ContentType('font', 'woff2'),
      _ => ContentType.binary,
    };
  }
}
