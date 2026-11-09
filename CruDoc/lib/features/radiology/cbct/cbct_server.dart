import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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
  /// [loadAsset] reads a bundled file by its asset key (tests pass a fake).
  CbctServer({Future<ByteData> Function(String key)? loadAsset})
    : _loadAsset = loadAsset ?? rootBundle.load;

  static final CbctServer instance = CbctServer();

  final Future<ByteData> Function(String key) _loadAsset;
  HttpServer? _http;

  /// What the page may read.
  static const _readFiles = {
    'meta.json',
    'full.i16',
    'mid.i16',
    'preview.i16',
    'poster_axial.png',
    'poster_coronal.png',
    'poster_sagittal.png',
    'poster_3d.png',
    'state.json',
  };

  /// The only files the page may write (besides `snap_<n>.png`).
  static const _writeFiles = {
    'state.json',
    'poster_axial.png',
    'poster_coronal.png',
    'poster_sagittal.png',
    'poster_3d.png',
  };
  static final _snapName = RegExp(r'^snap_\d{1,9}\.png$');
  static const _maxState = 256 * 1024;
  static const _maxPng = 12 * 1024 * 1024;

  /// The address the server listens on (loopback only); null until started.
  InternetAddress? get boundAddress => _http?.address;

  /// Stops the server and forgets every token.
  Future<void> close() async {
    _packs.clear();
    final http = _http;
    _http = null;
    _port = null;
    await http?.close(force: true);
  }

  static const _root = 'assets/cbct_viewer/';

  final Map<String, Directory> _packs = {};
  Future<int>? _port;

  Future<int> _ensureStarted() => _port ??= _start();

  Future<int> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http = server;
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
      final method = req.method;
      if (method != 'GET' && method != 'PUT') {
        res.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final path = Uri.decodeComponent(req.uri.path);
      if (path.contains('..') || path.contains('\\')) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      if (path.startsWith('/v/')) {
        if (method == 'PUT') {
          await _putPack(path, req, res);
        } else {
          await _servePack(path, res);
        }
      } else if (method == 'PUT') {
        res.statusCode = HttpStatus.notFound;
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
    if (dir == null || !_readFiles.contains(name)) {
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

  Future<void> _putPack(String path, HttpRequest req, HttpResponse res) async {
    // /v/<token>/<file>
    final parts = path.split('/');
    final dir = parts.length == 4 ? _packs[parts[2]] : null;
    final name = parts.length == 4 ? parts[3] : '';
    if (dir == null || !(_writeFiles.contains(name) || _snapName.hasMatch(name))) {
      res.statusCode = HttpStatus.notFound;
      return;
    }
    final limit = name == 'state.json' ? _maxState : _maxPng;
    if (req.contentLength > limit) {
      res.statusCode = HttpStatus.requestEntityTooLarge;
      return;
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in req) {
      body.add(chunk);
      if (body.length > limit) {
        res.statusCode = HttpStatus.requestEntityTooLarge;
        return;
      }
    }
    final bytes = body.takeBytes();
    if (name == 'state.json') {
      try {
        jsonDecode(utf8.decode(bytes));
      } on Object {
        res.statusCode = HttpStatus.badRequest;
        return;
      }
    } else if (!_isPng(bytes)) {
      res.statusCode = HttpStatus.badRequest;
      return;
    }
    if (!await dir.exists()) {
      res.statusCode = HttpStatus.notFound;
      return;
    }
    final tmp = File(p.join(dir.path, '$name.tmp'));
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(p.join(dir.path, name));
    res.statusCode = HttpStatus.noContent;
  }

  static bool _isPng(Uint8List b) =>
      b.length > 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47;

  Future<void> _serveAsset(String path, HttpResponse res) async {
    final data = await _loadAsset('$_root${path.substring(1)}');
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
      'png' => ContentType('image', 'png'),
      'ttf' => ContentType('font', 'ttf'),
      'woff2' => ContentType('font', 'woff2'),
      _ => ContentType.binary,
    };
  }
}
