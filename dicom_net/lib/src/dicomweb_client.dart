import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'dataset.dart';
import 'dicom_json.dart';
import 'multipart.dart';

enum DicomWebAuth { none, basic, bearer }

/// A failure talking to a PACS, said plainly.
class DicomWebException implements Exception {
  DicomWebException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// What a STOW-RS upload did.
class StowResult {
  const StowResult({required this.stored, required this.failed});
  final int stored;
  final int failed;
}

/// Talks to a PACS over DICOMweb: QIDO-RS search, WADO-RS download,
/// STOW-RS upload.
class DicomWebClient {
  DicomWebClient(
    String baseUrl, {
    this.auth = DicomWebAuth.none,
    this.username = '',
    this.secret = '',
    this.timeout = const Duration(seconds: 15),
  }) : base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  /// The DICOMweb root without a trailing slash.
  final String base;
  final DicomWebAuth auth;
  final String username;

  /// Password or token.
  final String secret;

  /// For connecting and the first response byte; downloads can run longer.
  final Duration timeout;

  HttpClient _http() => HttpClient()..connectionTimeout = timeout;

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$base$path');
    return query == null || query.isEmpty
        ? u
        : u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  void _authorize(HttpClientRequest req) {
    switch (auth) {
      case DicomWebAuth.none:
        break;
      case DicomWebAuth.basic:
        req.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic ${base64.encode(utf8.encode('$username:$secret'))}',
        );
      case DicomWebAuth.bearer:
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
    }
  }

  Future<HttpClientResponse> _send(
    HttpClient http,
    String method,
    Uri uri, {
    required String accept,
    String? contentType,
    Uint8List? body,
  }) async {
    try {
      final req = await http.openUrl(method, uri).timeout(timeout);
      req.headers.set(HttpHeaders.acceptHeader, accept);
      _authorize(req);
      if (body != null) {
        req.headers.set(HttpHeaders.contentTypeHeader, contentType!);
        req.contentLength = body.length;
        req.add(body);
      }
      return await req.close().timeout(
        body == null ? timeout : timeout * 8,
      );
    } on SocketException catch (e) {
      throw DicomWebException(
        'Can\'t reach ${uri.host}:${uri.port}. Check the address, that the PACS '
        'is running and that this device is on the same network. (${e.osError?.message ?? e.message})',
      );
    } on TimeoutException {
      throw DicomWebException(
        '${uri.host}:${uri.port} didn\'t answer in ${timeout.inSeconds} seconds.',
      );
    } on HandshakeException {
      throw DicomWebException(
        'The secure (https) connection to ${uri.host} failed. Check its certificate, '
        'or use http:// if the PACS doesn\'t offer https.',
      );
    } on FormatException catch (e) {
      throw DicomWebException('That address isn\'t valid: ${e.message}');
    }
  }

  Future<Uint8List> _read(HttpClientResponse res, {void Function(int, int?)? onProgress}) async {
    final out = BytesBuilder(copy: false);
    final total = res.contentLength >= 0 ? res.contentLength : null;
    await for (final chunk in res) {
      out.add(chunk);
      onProgress?.call(out.length, total);
    }
    return out.takeBytes();
  }

  Never _fail(HttpClientResponse res, String doing) {
    final code = res.statusCode;
    res.drain<void>().catchError((_) {});
    throw DicomWebException(switch (code) {
      401 || 403 =>
        'The PACS refused the sign-in ($code). Check the username and password or token.',
      404 =>
        'Nothing found at this address ($code) while $doing. Check the DICOMweb path — '
            'Orthanc uses /dicom-web, dcm4chee /dcm4chee-arc/aets/DCM4CHEE/rs.',
      406 || 415 => 'The PACS doesn\'t accept this request format ($code) while $doing.',
      _ => 'The PACS answered $code while $doing.',
    }, status: code);
  }

  /// Checks the address and sign-in with a one-result study search.
  Future<void> ping() async {
    final http = _http();
    try {
      final res = await _send(
        http,
        'GET',
        _uri('/studies', {'limit': '1'}),
        accept: 'application/dicom+json',
      );
      if (res.statusCode != 200 && res.statusCode != 204) {
        _fail(res, 'checking the connection');
      }
      final body = await _read(res);
      if (res.statusCode == 200 && body.isNotEmpty) {
        try {
          if (jsonDecode(utf8.decode(body)) is! List) throw const FormatException();
        } on FormatException {
          throw DicomWebException(
            'Something answered at this address, but it isn\'t DICOMweb. '
            'Check the path after the port.',
          );
        }
      }
    } finally {
      http.close(force: true);
    }
  }

  /// QIDO-RS study search. Name matching is partial; [modalities] with
  /// more than one value is filtered here, since many PACS take only one.
  Future<List<DicomStudySummary>> searchStudies({
    String patientName = '',
    String patientId = '',
    String accession = '',
    DateTime? from,
    DateTime? to,
    Set<String> modalities = const {},
    int limit = 100,
  }) async {
    final q = <String, String>{
      'limit': '$limit',
      'includefield': [
        DicomAttr.studyDescription,
        DicomAttr.modalitiesInStudy,
        DicomAttr.numberOfStudyRelatedSeries,
        DicomAttr.numberOfStudyRelatedInstances,
        DicomAttr.patientBirthDate,
        DicomAttr.patientSex,
        DicomAttr.referringPhysicianName,
      ].map((a) => a.hex).join(','),
      if (patientName.trim().isNotEmpty)
        DicomAttr.patientName.keyword: '*${patientName.trim()}*',
      if (patientId.trim().isNotEmpty)
        DicomAttr.patientId.keyword: patientId.trim(),
      if (accession.trim().isNotEmpty)
        DicomAttr.accessionNumber.keyword: accession.trim(),
      if (from != null || to != null)
        DicomAttr.studyDate.keyword:
            '${from == null ? '' : dicomDate(from)}-${to == null ? '' : dicomDate(to)}',
      if (modalities.length == 1)
        DicomAttr.modalitiesInStudy.keyword: modalities.first,
    };
    final http = _http();
    try {
      final res = await _send(
        http,
        'GET',
        _uri('/studies', q),
        accept: 'application/dicom+json',
      );
      if (res.statusCode == 204) {
        await res.drain<void>();
        return const [];
      }
      if (res.statusCode != 200) _fail(res, 'searching');
      final body = await _read(res);
      if (body.isEmpty) return const [];
      final list = jsonDecode(utf8.decode(body));
      if (list is! List) {
        throw DicomWebException('The PACS sent an answer CruDoc can\'t read.');
      }
      final studies = [
        for (final o in list)
          if (o is Map<String, dynamic>) DicomStudySummary.fromJson(o),
      ];
      if (modalities.length > 1) {
        studies.retainWhere(
          (s) => s.modalities.isEmpty || s.modalities.any(modalities.contains),
        );
      }
      return studies;
    } on FormatException {
      throw DicomWebException('The PACS sent an answer CruDoc can\'t read.');
    } finally {
      http.close(force: true);
    }
  }

  /// WADO-RS: every instance of a study, as Part 10 files.
  Future<List<Uint8List>> retrieveStudy(
    String studyUid, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final http = _http();
    try {
      final uri = _uri('/studies/$studyUid');
      // Ask for files as stored; older servers only take the plain form.
      var res = await _send(
        http,
        'GET',
        uri,
        accept: 'multipart/related; type="application/dicom"; transfer-syntax=*',
      );
      if (res.statusCode == 406 || res.statusCode == 400) {
        await res.drain<void>();
        res = await _send(
          http,
          'GET',
          uri,
          accept: 'multipart/related; type="application/dicom"',
        );
      }
      if (res.statusCode != 200) _fail(res, 'downloading the study');
      final boundary = Multipart.boundaryOf(
        res.headers.value(HttpHeaders.contentTypeHeader),
      );
      final body = await _read(res, onProgress: onProgress);
      if (boundary == null) {
        if (DicomInstance.looksLikeDicom(body)) return [body];
        throw DicomWebException('The PACS sent the study in a form CruDoc can\'t read.');
      }
      return Multipart.parse(body, boundary)
          .where(DicomInstance.looksLikeDicom)
          .toList();
    } finally {
      http.close(force: true);
    }
  }

  /// STOW-RS: uploads Part 10 files.
  Future<StowResult> store(List<Uint8List> files) async {
    if (files.isEmpty) return const StowResult(stored: 0, failed: 0);
    final boundary = Multipart.newBoundary();
    final body = Multipart.build(files, boundary);
    final http = _http();
    try {
      final res = await _send(
        http,
        'POST',
        _uri('/studies'),
        accept: 'application/dicom+json',
        contentType: Multipart.contentType(boundary),
        body: body,
      );
      final code = res.statusCode;
      if (code != 200 && code != 202 && code != 409) _fail(res, 'sending');
      final text = utf8.decode(await _read(res), allowMalformed: true);
      var failed = code == 409 ? files.length : 0;
      if (code == 202) {
        try {
          final j = jsonDecode(text);
          final f = j is Map ? j['00081198'] : null;
          final v = f is Map ? f['Value'] : null;
          failed = v is List ? v.length : 0;
        } on FormatException {
          failed = 0;
        }
      }
      return StowResult(stored: files.length - failed, failed: failed);
    } finally {
      http.close(force: true);
    }
  }
}
