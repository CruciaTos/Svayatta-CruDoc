import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/files/data/file_offer_model.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'device_identity.dart';
import 'device_registry_service.dart';

class _LanSession {
  const _LanSession({
    required this.token,
    required this.clientDeviceId,
    required this.clientCertSha256,
    required this.clientUid,
    required this.expiresAt,
  });

  final String token;
  final String clientDeviceId;
  final String clientCertSha256;
  final String clientUid;
  final DateTime expiresAt;

  bool get isValid => DateTime.now().isBefore(expiresAt);
}

/// Internal HTTPS Server (TLS 1.3) bound inside CruDoc (Tasks N1, N2).
class LanServer {
  LanServer._();
  static final LanServer instance = LanServer._();

  static const int defaultPort = 47811;

  HttpServer? _server;
  int _port = 0;
  bool _running = false;

  int get port => _port;
  bool get isRunning => _running;

  final Map<String, DateTime> _nonces = {};
  final Map<String, _LanSession> _sessions = {};

  /// Open offers sent from this device to peers, by offer id. Keyed by
  /// offer (not by fingerprint) so the same file offered to two colleagues
  /// stays downloadable by both.
  final Map<String, FileOffer> _openOffers = {};

  /// Tracks active incoming transfer subscriptions/listeners.
  final StreamController<FileOffer> _incomingOffersController =
      StreamController<FileOffer>.broadcast();
  Stream<FileOffer> get incomingLanOffers => _incomingOffersController.stream;

  /// Starts the HTTPS server.
  Future<int> start() async {
    if (_running && _server != null) return _port;

    await DeviceIdentity.instance.initialize();
    final securityContext = DeviceIdentity.instance.createServerSecurityContext();

    try {
      // Try default port 47811 first
      _server = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        defaultPort,
        securityContext,
      );
      _port = defaultPort;
    } catch (_) {
      // Fallback to ephemeral port
      _server = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        0,
        securityContext,
      );
      _port = _server!.port;
    }

    _running = true;
    _server!.listen(_handleRequest, onError: (e) {
      debugPrint('[LanServer] Error: $e');
    });

    debugPrint('[LanServer] Listening securely on port $_port');
    return _port;
  }

  /// Registers an open offer so recipient can pull the blob bytes.
  void registerOpenOffer(FileOffer offer) {
    _openOffers[offer.id] = offer;
  }

  void unregisterOpenOffer(String offerId) {
    _openOffers.remove(offerId);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    try {
      if (method == 'GET' && path == '/v1/hello') {
        await _handleHello(request);
      } else if (method == 'POST' && path == '/v1/session') {
        await _handleSession(request);
      } else {
        // Authenticated endpoints require a valid session
        final session = _authenticate(request);
        if (session == null) {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..write(jsonEncode({'error': 'Unauthorized or session expired'}))
            ..close();
          return;
        }

        if (method == 'POST' && path == '/v1/offers') {
          await _handleReceiveOffer(request, session);
        } else if (method == 'GET' && path.startsWith('/v1/blobs/')) {
          await _handleServeBlob(request, session);
        } else if (method == 'POST' && path.startsWith('/v1/offers/') && path.endsWith('/status')) {
          await _handleOfferStatus(request, session);
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write(jsonEncode({'error': 'Not found'}))
            ..close();
        }
      }
    } catch (e, st) {
      debugPrint('[LanServer] Request failed: $e\n$st');
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write(jsonEncode({'error': 'Internal server error'}))
          ..close();
      } catch (_) {}
    }
  }

  // ──────────────────────────── Handshake ────────────────────────────

  Future<void> _handleHello(HttpRequest request) async {
    _cleanupExpiredNonces();

    final nonce = _generateRandomHex(32);
    _nonces[nonce] = DateTime.now().add(const Duration(seconds: 60));

    final data = {
      'deviceId': DeviceIdentity.instance.deviceId,
      'nonce': nonce,
    };

    request.response
      ..headers.contentType = ContentType.json
      ..statusCode = HttpStatus.ok
      ..write(jsonEncode(data))
      ..close();
  }

  Future<void> _handleSession(HttpRequest request) async {
    _cleanupExpiredNonces();

    final bodyStr = await utf8.decoder.bind(request).join();
    final body = jsonDecode(bodyStr) as Map<String, dynamic>;

    final clientDeviceId = body['deviceId'] as String? ?? '';
    final signatureBase64 = body['signature'] as String? ?? '';
    final nonce = body['nonce'] as String? ?? '';

    // Verify nonce
    final nonceExp = _nonces[nonce];
    if (nonceExp == null || DateTime.now().isAfter(nonceExp)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write(jsonEncode({'error': 'Invalid or expired nonce'}))
        ..close();
      return;
    }
    _nonces.remove(nonce);

    // Look up client device in registry
    final clientDevice = DeviceRegistryService.instance.cachedDevices
        .where((d) => d.id == clientDeviceId)
        .firstOrNull;

    if (clientDevice == null || clientDevice.certPem.isEmpty) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write(jsonEncode({'error': 'Device not recognized in clinic registry'}))
        ..close();
      return;
    }

    // Verify challenge signature
    final isValid = DeviceIdentity.verifyChallenge(
      certPem: clientDevice.certPem,
      serverDeviceId: DeviceIdentity.instance.deviceId,
      nonce: nonce,
      clientCertSha256: clientDevice.certSha256,
      signatureBase64: signatureBase64,
    );

    if (!isValid) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write(jsonEncode({'error': 'Invalid signature'}))
        ..close();
      return;
    }

    // Issue 15-minute session token
    final token = _generateRandomHex(32);
    final session = _LanSession(
      token: token,
      clientDeviceId: clientDeviceId,
      clientCertSha256: clientDevice.certSha256,
      clientUid: clientDevice.uid,
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
    _sessions[token] = session;

    request.response
      ..headers.contentType = ContentType.json
      ..statusCode = HttpStatus.ok
      ..write(jsonEncode({'token': token, 'expiresIn': 900}))
      ..close();
  }

  _LanSession? _authenticate(HttpRequest request) {
    final authHeader = request.headers.value(HttpHeaders.authorizationHeader);
    if (authHeader == null || !authHeader.startsWith('Bearer ')) return null;

    final token = authHeader.substring('Bearer '.length).trim();
    final session = _sessions[token];
    if (session == null || !session.isValid) {
      _sessions.remove(token);
      return null;
    }
    return session;
  }

  // ──────────────────────────── Endpoints ────────────────────────────

  Future<void> _handleReceiveOffer(HttpRequest request, _LanSession session) async {
    final bodyStr = await utf8.decoder.bind(request).join();
    final map = jsonDecode(bodyStr) as Map<String, dynamic>;

    // Only offers addressed to the person signed in here, and only while
    // they may keep patient files (see, and write, clinical records).
    final me = FilesRepository.instance.uid;
    final access = ClinicSession.instance.access;
    final mayReceive =
        access == null ||
        (access.can(ClinicPermission.clinicalView) &&
            access.can(ClinicPermission.clinicalEdit));
    if (me.isEmpty || map['to'] != me || !mayReceive) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write(jsonEncode({'error': 'This device does not take this offer'}))
        ..close();
      return;
    }

    // Who sent it is the verified device's owner, never what the body says;
    // the clinic is this device's own.
    map['from'] = session.clientUid;
    final offer = FileOffer.fromFirestore(
      id: map['id'] as String? ?? _generateRandomHex(16),
      clinicId: FilesRepository.instance.doctorId,
      data: map,
    );

    _incomingOffersController.add(offer);

    request.response
      ..headers.contentType = ContentType.json
      ..statusCode = HttpStatus.ok
      ..write(jsonEncode({'status': 'received'}))
      ..close();
  }

  Future<void> _handleServeBlob(HttpRequest request, _LanSession session) async {
    final sha256 = request.uri.pathSegments.last;

    // Check caller has an open offer for this fingerprint
    final openOffer = _openOffers.values
        .where((o) => o.sha256 == sha256 && o.to == session.clientUid)
        .firstOrNull;
    if (openOffer == null) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write(jsonEncode({'error': 'No open offer for this file fingerprint to caller'}))
        ..close();
      return;
    }

    final origFile = await FilesRepository.instance.file(openOffer.fileId);
    if (origFile == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write(jsonEncode({'error': 'Original file record not found'}))
        ..close();
      return;
    }

    final file = await FilesRepository.instance.localCopy(origFile);
    if (!await file.exists()) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write(jsonEncode({'error': 'File not found on disk'}))
        ..close();
      return;
    }

    final totalLength = await file.length();
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    int start = 0;
    int end = totalLength - 1;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final rangeValues = rangeHeader.substring('bytes='.length).split('-');
      final parsedStart = int.tryParse(rangeValues[0]);
      if (parsedStart != null) start = parsedStart;
      if (rangeValues.length > 1 && rangeValues[1].isNotEmpty) {
        final parsedEnd = int.tryParse(rangeValues[1]);
        if (parsedEnd != null && parsedEnd < totalLength) end = parsedEnd;
      }

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$totalLength',
      );
    } else {
      request.response.statusCode = HttpStatus.ok;
    }

    final contentLength = end - start + 1;
    request.response.headers.contentLength = contentLength;
    request.response.headers.contentType = ContentType.binary;

    final stream = file.openRead(start, end + 1);
    await stream.pipe(request.response);
  }

  Future<void> _handleOfferStatus(HttpRequest request, _LanSession session) async {
    final segments = request.uri.pathSegments;
    final offerId = segments[segments.length - 2];

    final bodyStr = await utf8.decoder.bind(request).join();
    final body = jsonDecode(bodyStr) as Map<String, dynamic>;
    final status = body['status'] as String? ?? '';

    if (status == 'accepted' || status == 'declined') {
      // Only the offer's recipient can close it.
      if (_openOffers[offerId]?.to == session.clientUid) {
        _openOffers.remove(offerId);
      }
    }

    request.response
      ..headers.contentType = ContentType.json
      ..statusCode = HttpStatus.ok
      ..write(jsonEncode({'ok': true}))
      ..close();
  }

  // ──────────────────────────── Helpers ────────────────────────────

  void _cleanupExpiredNonces() {
    final now = DateTime.now();
    _nonces.removeWhere((_, exp) => now.isAfter(exp));
    _sessions.removeWhere((_, s) => !s.isValid);
  }

  static String _generateRandomHex(int bytesCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(bytesCount, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _running = false;
  }
}
