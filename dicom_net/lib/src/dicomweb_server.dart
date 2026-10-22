import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'dataset.dart';
import 'dicom_json.dart';
import 'dicomweb_client.dart' show DicomWebAuth;
import 'multipart.dart';
import 'pacs_store.dart';

/// One request the server handled.
class DicomWebEvent {
  DicomWebEvent({
    required this.method,
    required this.path,
    required this.status,
    required this.summary,
    required this.remote,
  }) : at = DateTime.now();

  final DateTime at;
  final String method;
  final String path;
  final int status;

  /// "QIDO search · 3 studies", "WADO download · 12 files"…
  final String summary;
  final String remote;
}

/// A DICOMweb PACS over a [FolderPacsStore]: QIDO-RS (studies, series,
/// instances), WADO-RS (files and metadata) and STOW-RS.
///
/// Served at http://host:port/dicom-web (and at the root, for clients
/// given just host:port).
class DicomWebServer {
  DicomWebServer(
    this.store, {
    this.auth = DicomWebAuth.none,
    this.username = '',
    this.secret = '',
    this.onStored,
  });

  final FolderPacsStore store;
  final DicomWebAuth auth;
  final String username;
  final String secret;

  /// Called after STOW stores files.
  final void Function(List<StoredInstance>)? onStored;

  static const prefix = '/dicom-web';

  HttpServer? _server;
  final _events = StreamController<DicomWebEvent>.broadcast();

  Stream<DicomWebEvent> get events => _events.stream;
  int? get port => _server?.port;
  bool get running => _server != null;

  Future<void> start(int port) async {
    await stop();
    final s = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _server = s;
    s.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void _log(HttpRequest r, int status, String summary) => _events.add(
    DicomWebEvent(
      method: r.method,
      path: r.uri.toString(),
      status: status,
      summary: summary,
      remote: r.connectionInfo?.remoteAddress.address ?? '',
    ),
  );

  bool _authorized(HttpRequest r) {
    if (auth == DicomWebAuth.none) return true;
    final h = r.headers.value(HttpHeaders.authorizationHeader) ?? '';
    return switch (auth) {
      DicomWebAuth.basic =>
        h == 'Basic ${base64.encode(utf8.encode('$username:$secret'))}',
      DicomWebAuth.bearer => h == 'Bearer $secret',
      DicomWebAuth.none => true,
    };
  }

  Future<void> _handle(HttpRequest r) async {
    final res = r.response;
    try {
      if (!_authorized(r)) {
        res.statusCode = 401;
        res.headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          auth == DicomWebAuth.basic ? 'Basic realm="PACS"' : 'Bearer',
        );
        _log(r, 401, 'Sign-in refused');
        await res.close();
        return;
      }
      var path = r.uri.path;
      if (path.startsWith(prefix)) path = path.substring(prefix.length);
      final seg = path.split('/').where((s) => s.isNotEmpty).toList();

      if (r.method == 'POST' &&
          seg.isNotEmpty &&
          seg[0] == 'studies' &&
          seg.length <= 2) {
        await _stow(r);
        return;
      }
      if (r.method != 'GET' && r.method != 'HEAD') {
        await _status(r, 405, 'Method not allowed');
        return;
      }
      // /studies
      if (seg.length == 1 && seg[0] == 'studies') {
        await _qidoStudies(r);
        return;
      }
      if (seg.length >= 2 && seg[0] == 'studies') {
        final study = seg[1];
        final rest = seg.sublist(2);
        if (rest.isEmpty) return _wado(r, study);
        if (rest.length == 1 && rest[0] == 'metadata') {
          return _metadata(r, study);
        }
        if (rest.length == 1 && rest[0] == 'series') {
          return _qidoSeries(r, study);
        }
        if (rest.length == 1 && rest[0] == 'instances') {
          return _qidoInstances(r, study, null);
        }
        if (rest.length >= 2 && rest[0] == 'series') {
          final series = rest[1];
          final more = rest.sublist(2);
          if (more.isEmpty) return _wado(r, study, series: series);
          if (more.length == 1 && more[0] == 'metadata') {
            return _metadata(r, study, series: series);
          }
          if (more.length == 1 && more[0] == 'instances') {
            return _qidoInstances(r, study, series);
          }
          if (more.length >= 2 && more[0] == 'instances') {
            final sop = more[1];
            if (more.length == 2) {
              return _wado(r, study, series: series, sop: sop);
            }
            if (more.length == 3 && more[2] == 'metadata') {
              return _metadata(r, study, series: series, sop: sop);
            }
          }
        }
      }
      await _status(r, 404, 'Not found');
    } catch (e) {
      try {
        await _status(r, 500, 'Error: $e');
      } catch (_) {}
    }
  }

  Future<void> _status(HttpRequest r, int code, String summary) async {
    r.response.statusCode = code;
    _log(r, code, summary);
    await r.response.close();
  }

  Future<void> _json(HttpRequest r, Object body, String summary) async {
    final res = r.response;
    final list = body is List ? body : null;
    if (list != null && list.isEmpty) {
      res.statusCode = 204;
      _log(r, 204, '$summary · nothing found');
      await res.close();
      return;
    }
    res.statusCode = 200;
    res.headers.contentType = ContentType('application', 'dicom+json', charset: 'utf-8');
    res.write(jsonEncode(body));
    _log(r, 200, summary);
    await res.close();
  }

  // ───────────────────────────── QIDO ─────────────────────────────

  static bool _wild(String pattern, String value) {
    final re = RegExp(
      '^${RegExp.escape(pattern).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
      caseSensitive: false,
    );
    return re.hasMatch(value);
  }

  static bool _dateIn(String range, String date) {
    if (!range.contains('-')) return date == range.replaceAll(RegExp('[^0-9]'), '');
    final p = range.split('-');
    final from = p[0].replaceAll(RegExp('[^0-9]'), '');
    final to = p.length > 1 ? p[1].replaceAll(RegExp('[^0-9]'), '') : '';
    if (date.isEmpty) return false;
    return (from.isEmpty || date.compareTo(from) >= 0) &&
        (to.isEmpty || date.compareTo(to) <= 0);
  }

  /// Filters from the query string (keywords or hex tags).
  Map<DicomAttr, String> _filters(HttpRequest r) {
    final f = <DicomAttr, String>{};
    r.uri.queryParametersAll.forEach((k, v) {
      if (const {'limit', 'offset', 'includefield', 'fuzzymatching'}.contains(k)) {
        return;
      }
      final a = DicomAttr.find(k);
      if (a != null && v.isNotEmpty && v.first.isNotEmpty) f[a] = v.first;
    });
    return f;
  }

  static bool _matches(Map<DicomAttr, String> filters, String Function(DicomAttr) get) {
    for (final e in filters.entries) {
      final want = e.value;
      final have = get(e.key);
      switch (e.key) {
        case DicomAttr.studyDate:
          if (!_dateIn(want, have)) return false;
        case DicomAttr.modalitiesInStudy:
          final mods = have.split('\\');
          if (!want.split(RegExp(r'[\\,]')).any(mods.contains)) return false;
        case DicomAttr.studyInstanceUid ||
            DicomAttr.seriesInstanceUid ||
            DicomAttr.sopInstanceUid:
          if (!want.split(RegExp(r'[\\,]')).contains(have)) return false;
        default:
          if (!_wild(want, have)) return false;
      }
    }
    return true;
  }

  List<T> _page<T>(HttpRequest r, List<T> list) {
    final offset = int.tryParse(r.uri.queryParameters['offset'] ?? '') ?? 0;
    final limit = int.tryParse(r.uri.queryParameters['limit'] ?? '');
    final rest = list.skip(offset);
    return (limit == null ? rest : rest.take(limit)).toList();
  }

  String _base(HttpRequest r) {
    final host = r.headers.host ?? 'localhost';
    final port = r.headers.port;
    return 'http://$host:$port$prefix';
  }

  Map<DicomAttr, String> _studyAttrs(List<StoredInstance> list) {
    final first = list.first;
    final mods = {for (final i in list) i[DicomAttr.modality]}..remove('');
    return {
      for (final a in const [
        DicomAttr.patientName,
        DicomAttr.patientId,
        DicomAttr.patientBirthDate,
        DicomAttr.patientSex,
        DicomAttr.studyInstanceUid,
        DicomAttr.studyDate,
        DicomAttr.studyTime,
        DicomAttr.accessionNumber,
        DicomAttr.studyDescription,
        DicomAttr.referringPhysicianName,
        DicomAttr.studyId,
      ])
        a: first[a],
      DicomAttr.modalitiesInStudy: mods.join('\\'),
      DicomAttr.numberOfStudyRelatedSeries:
          '${{for (final i in list) i.seriesUid}.length}',
      DicomAttr.numberOfStudyRelatedInstances: '${list.length}',
    };
  }

  Future<void> _qidoStudies(HttpRequest r) async {
    final filters = _filters(r);
    final studies = <Map<String, Object>>[];
    for (final e in store.byStudy().entries) {
      final attrs = _studyAttrs(e.value);
      if (!_matches(filters, (a) => attrs[a] ?? e.value.first[a])) continue;
      studies.add({
        ...dicomJson(attrs),
        ...dicomJson({DicomAttr.retrieveUrl: '${_base(r)}/studies/${e.key}'}),
      });
    }
    final page = _page(r, studies);
    await _json(
      r,
      page,
      'Search studies${filters.isEmpty ? '' : ' (${filters.entries.map((e) => '${e.key.keyword}=${e.value}').join(', ')})'} · ${page.length} found',
    );
  }

  Future<void> _qidoSeries(HttpRequest r, String study) async {
    final list = store.instances.where((i) => i.studyUid == study).toList();
    final bySeries = <String, List<StoredInstance>>{};
    for (final i in list) {
      (bySeries[i.seriesUid] ??= []).add(i);
    }
    final filters = _filters(r);
    final out = <Map<String, Object>>[];
    for (final e in bySeries.entries) {
      final f = e.value.first;
      if (!_matches(filters, (a) => f[a])) continue;
      out.add(
        dicomJson({
          DicomAttr.studyInstanceUid: study,
          DicomAttr.seriesInstanceUid: e.key,
          DicomAttr.modality: f[DicomAttr.modality],
          DicomAttr.seriesNumber: f[DicomAttr.seriesNumber],
          DicomAttr.seriesDescription: f[DicomAttr.seriesDescription],
          DicomAttr.numberOfSeriesRelatedInstances: '${e.value.length}',
          DicomAttr.retrieveUrl: '${_base(r)}/studies/$study/series/${e.key}',
        }),
      );
    }
    await _json(r, _page(r, out), 'Search series · ${out.length} found');
  }

  Future<void> _qidoInstances(HttpRequest r, String study, String? series) async {
    final filters = _filters(r);
    final list = store.instances
        .where(
          (i) =>
              i.studyUid == study &&
              (series == null || i.seriesUid == series) &&
              _matches(filters, (a) => i[a]),
        )
        .toList();
    final out = [
      for (final i in list)
        dicomJson({
          DicomAttr.studyInstanceUid: i.studyUid,
          DicomAttr.seriesInstanceUid: i.seriesUid,
          DicomAttr.sopClassUid: i[DicomAttr.sopClassUid],
          DicomAttr.sopInstanceUid: i.sopUid,
          DicomAttr.instanceNumber: i[DicomAttr.instanceNumber],
          DicomAttr.rows: i[DicomAttr.rows],
          DicomAttr.columns: i[DicomAttr.columns],
          DicomAttr.numberOfFrames: i[DicomAttr.numberOfFrames],
        }),
    ];
    await _json(r, _page(r, out), 'Search instances · ${out.length} found');
  }

  // ───────────────────────────── WADO ─────────────────────────────

  List<StoredInstance> _select(String study, String? series, String? sop) =>
      store.instances
          .where(
            (i) =>
                i.studyUid == study &&
                (series == null || i.seriesUid == series) &&
                (sop == null || i.sopUid == sop),
          )
          .toList()
        ..sort(
          (a, b) => (int.tryParse(a[DicomAttr.instanceNumber]) ?? 0).compareTo(
            int.tryParse(b[DicomAttr.instanceNumber]) ?? 0,
          ),
        );

  Future<void> _wado(
    HttpRequest r,
    String study, {
    String? series,
    String? sop,
  }) async {
    final list = _select(study, series, sop);
    if (list.isEmpty) {
      await _status(r, 404, 'Download · study not found');
      return;
    }
    final accept = r.headers.value(HttpHeaders.acceptHeader) ?? '*/*';
    if (!accept.contains('multipart/related') &&
        !accept.contains('*/*') &&
        !accept.contains('application/dicom')) {
      await _status(r, 406, 'Download · unsupported Accept "$accept"');
      return;
    }
    final files = [for (final i in list) await store.read(i)];
    final boundary = Multipart.newBoundary();
    final body = Multipart.build(files, boundary);
    final res = r.response
      ..statusCode = 200
      ..headers.set(HttpHeaders.contentTypeHeader, Multipart.contentType(boundary))
      ..contentLength = body.length;
    res.add(body);
    _log(
      r,
      200,
      'Download ${sop != null ? 'instance' : series != null ? 'series' : 'study'} · '
      '${files.length} file${files.length == 1 ? '' : 's'}, ${(body.length / 1024).toStringAsFixed(0)} KB',
    );
    await res.close();
  }

  Future<void> _metadata(
    HttpRequest r,
    String study, {
    String? series,
    String? sop,
  }) async {
    final list = _select(study, series, sop);
    if (list.isEmpty) {
      await _status(r, 404, 'Metadata · not found');
      return;
    }
    await _json(r, [
      for (final i in list) dicomJson(i.attrs),
    ], 'Metadata · ${list.length} instances');
  }

  // ───────────────────────────── STOW ─────────────────────────────

  Future<void> _stow(HttpRequest r) async {
    final boundary = Multipart.boundaryOf(r.headers.value(HttpHeaders.contentTypeHeader));
    final body = BytesBuilder(copy: false);
    await for (final c in r) {
      body.add(c);
    }
    if (boundary == null) {
      await _status(r, 415, 'Upload · not multipart/related');
      return;
    }
    final parts = Multipart.parse(body.takeBytes(), boundary);
    final stored = <StoredInstance>[];
    var failed = 0;
    final remote = r.connectionInfo?.remoteAddress.address ?? '';
    for (final p in parts) {
      try {
        stored.add(
          await store.add(Uint8List.fromList(p), source: 'Received from $remote'),
        );
      } catch (_) {
        failed++;
      }
    }
    if (stored.isNotEmpty) onStored?.call(stored);
    final code = failed == 0 ? 200 : (stored.isEmpty ? 409 : 202);
    final res = r.response
      ..statusCode = code
      ..headers.contentType = ContentType('application', 'dicom+json', charset: 'utf-8');
    res.write(
      jsonEncode({
        '00081199': {
          'vr': 'SQ',
          'Value': [
            for (final s in stored)
              dicomJson({
                DicomAttr.sopClassUid: s[DicomAttr.sopClassUid],
                DicomAttr.sopInstanceUid: s.sopUid,
              }),
          ],
        },
        if (failed > 0)
          '00081198': {
            'vr': 'SQ',
            'Value': List.generate(failed, (_) => <String, Object>{}),
          },
      }),
    );
    _log(
      r,
      code,
      'Upload · ${stored.length} stored${failed > 0 ? ', $failed failed' : ''}',
    );
    await res.close();
  }
}
