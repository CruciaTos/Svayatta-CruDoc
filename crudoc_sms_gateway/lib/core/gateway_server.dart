import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import 'duplicate_guard.dart';
import 'gateway_security.dart';
import 'models.dart';
import 'native_sms_engine.dart';

/// The on-device HTTP server that listens for SMS-send commands from
/// the CruDoc Windows PC over the local clinic Wi-Fi.
///
/// Endpoints:
///   GET  /status     → Device & gateway status
///   POST /pair       → Pairing handshake
///   POST /sms/send   → Send an SMS via native SIM
///   POST /heartbeat  → Health check ping
class GatewayServer {
  GatewayServer._();
  static final GatewayServer instance = GatewayServer._();

  static const int defaultPort = 8080;
  static const _storage = FlutterSecureStorage();
  static const _gatewayIdKey = 'gateway_id';
  static const _secretKey = 'gateway_secret';
  static const _pairedKey = 'gateway_paired';

  HttpServer? _server;
  final _uuid = const Uuid();
  final _battery = Battery();
  final _networkInfo = NetworkInfo();

  GatewayStatus _status = GatewayStatus.offline;
  bool _isBusy = false;
  String? _gatewayId;
  String? _secret;
  String? _localIp;

  // Callbacks to notify UI
  void Function(GatewayStatus status)? onStatusChanged;
  void Function(SmsLogEntry entry)? onSmsLog;

  GatewayStatus get status => _status;
  String? get gatewayId => _gatewayId;
  String? get localIp => _localIp;
  int get port => defaultPort;
  bool get isRunning => _server != null;

  /// Starts the local HTTP server.
  Future<void> start() async {
    if (_server != null) return;

    try {
      _localIp = await _networkInfo.getWifiIP();
      _gatewayId = await _storage.read(key: _gatewayIdKey);
      _secret = await _storage.read(key: _secretKey);

      if (_gatewayId == null) {
        _gatewayId = _uuid.v4();
        await _storage.write(key: _gatewayIdKey, value: _gatewayId!);
      }

      final router = Router()
        ..get('/status', _handleStatus)
        ..post('/pair', _handlePair)
        ..post('/sms/send', _handleSmsSend)
        ..post('/heartbeat', _handleHeartbeat);

      final handler = const shelf.Pipeline()
          .addMiddleware(shelf.logRequests())
          .addMiddleware(_corsMiddleware())
          .addHandler(router.call);

      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, defaultPort);
      _updateStatus(GatewayStatus.ready);
      debugPrint('GatewayServer: Listening on $_localIp:$defaultPort');
    } catch (e) {
      debugPrint('GatewayServer: Failed to start: $e');
      _updateStatus(GatewayStatus.error);
    }
  }

  /// Stops the local HTTP server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _updateStatus(GatewayStatus.offline);
    debugPrint('GatewayServer: Stopped');
  }

  /// Returns pairing information for QR code display.
  Future<Map<String, String>> getPairingInfo() async {
    _localIp = await _networkInfo.getWifiIP();
    return {
      'gatewayId': _gatewayId ?? '',
      'ip': _localIp ?? '',
      'port': defaultPort.toString(),
    };
  }

  /// Returns true if the gateway is currently paired with a PC.
  Future<bool> isPaired() async {
    return (await _storage.read(key: _pairedKey)) == 'true';
  }

  /// Unpairs the gateway, clearing the shared secret.
  Future<void> unpair() async {
    _secret = null;
    await _storage.delete(key: _secretKey);
    await _storage.write(key: _pairedKey, value: 'false');
  }

  // ─── Endpoint Handlers ─────────────────────────────────────────

  /// GET /status — Returns gateway + device status.
  Future<shelf.Response> _handleStatus(shelf.Request request) async {
    final simInfo = await NativeSmsEngine.instance.getSimInfo();
    final batteryLevel = await _battery.batteryLevel;

    return _json(200, {
      'gatewayId': _gatewayId,
      'status': _status.name,
      'ip': _localIp,
      'port': defaultPort,
      'paired': await isPaired(),
      'battery': batteryLevel,
      'sim': simInfo,
      'appVersion': '1.0.0',
    });
  }

  /// POST /pair — Pairing handshake. Generates a shared secret
  /// and returns it to the requesting PC.
  Future<shelf.Response> _handlePair(shelf.Request request) async {
    try {
      final body = await _readJsonBody(request);
      if (body == null) return _json(400, {'error': 'Invalid JSON body'});

      // If already paired, reject unless force re-pair is requested
      final alreadyPaired = await isPaired();
      final force = body['force'] as bool? ?? false;
      if (alreadyPaired && !force) {
        return _json(409, {
          'error': 'Already paired. Send force: true to re-pair.',
          'gatewayId': _gatewayId,
        });
      }

      // Generate new shared secret
      _secret = _uuid.v4() + _uuid.v4(); // 64-char high-entropy secret
      await _storage.write(key: _secretKey, value: _secret!);
      await _storage.write(key: _pairedKey, value: 'true');

      debugPrint('GatewayServer: Paired successfully');

      return _json(200, {
        'gatewayId': _gatewayId,
        'secret': _secret,
        'status': 'paired',
      });
    } catch (e) {
      return _json(500, {'error': 'Pairing failed: $e'});
    }
  }

  /// POST /sms/send — Validates auth, checks for duplicates, and dispatches SMS.
  Future<shelf.Response> _handleSmsSend(shelf.Request request) async {
    try {
      // ── Auth check ──
      if (_secret == null || _secret!.isEmpty) {
        return _json(401, {'error': 'Gateway not paired'});
      }

      final body = await _readJsonBody(request);
      if (body == null) return _json(400, {'error': 'Invalid JSON body'});

      final gatewayId = body['gatewayId'] as String? ?? '';
      final requestId = body['requestId'] as String? ?? '';
      final timestamp = body['timestamp'] as int? ?? 0;
      final phone = body['phoneNumber'] as String? ?? '';
      final message = body['message'] as String? ?? '';
      final signature = body['signature'] as String? ?? '';

      // ── Validate required fields ──
      if (requestId.isEmpty || phone.isEmpty || message.isEmpty) {
        return _json(400, {'error': 'requestId, phoneNumber, and message are required'});
      }

      // ── Validate gateway ID ──
      if (gatewayId != _gatewayId) {
        return _json(401, {'error': 'Gateway ID mismatch'});
      }

      // ── Anti-replay: check timestamp (30s window) ──
      if (!GatewaySecurity.isTimestampValid(timestamp)) {
        return _json(403, {'error': 'Request expired (timestamp outside 30s window)'});
      }

      // ── HMAC-SHA256 signature validation ──
      final expectedPayload = GatewaySecurity.buildSignablePayload(
        gatewayId: gatewayId,
        requestId: requestId,
        timestamp: timestamp,
        phone: phone,
        message: message,
      );
      if (!GatewaySecurity.verify(expectedPayload, signature, _secret!)) {
        return _json(401, {'error': 'Invalid signature'});
      }

      // ── Duplicate check ──
      if (await DuplicateGuard.instance.isDuplicate(requestId)) {
        final cached = await DuplicateGuard.instance.getCachedResult(requestId);
        debugPrint('GatewayServer: Duplicate requestId=$requestId, returning cached result');

        _logSms(requestId, phone, message, 'duplicate', null);
        return shelf.Response.ok(
          cached ?? jsonEncode({'requestId': requestId, 'status': 'duplicate'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // ── Validate phone number (basic E.164 check) ──
      final sanitizedPhone = _sanitizePhone(phone);
      if (sanitizedPhone == null) {
        return _json(400, {'error': 'Invalid phone number format'});
      }

      // ── Send SMS ──
      if (_isBusy) {
        return _json(503, {'error': 'Gateway busy, try again shortly'});
      }
      _isBusy = true;
      _updateStatus(GatewayStatus.busy);

      try {
        final result = await NativeSmsEngine.instance.sendSms(
          phone: sanitizedPhone,
          message: message,
        );

        final status = result['status'] as String? ?? 'failed';
        final error = result['error'] as String?;

        final responseBody = jsonEncode({
          'requestId': requestId,
          'status': status,
          if (error != null) 'error': error,
        });

        // Record in duplicate guard
        await DuplicateGuard.instance.record(requestId, responseBody);

        _logSms(requestId, sanitizedPhone, message, status, error);

        return shelf.Response.ok(
          responseBody,
          headers: {'Content-Type': 'application/json'},
        );
      } finally {
        _isBusy = false;
        _updateStatus(GatewayStatus.ready);
      }
    } catch (e) {
      return _json(500, {'error': 'Internal error: $e'});
    }
  }

  /// POST /heartbeat — Simple health ping.
  Future<shelf.Response> _handleHeartbeat(shelf.Request request) async {
    final batteryLevel = await _battery.batteryLevel;
    final simInfo = await NativeSmsEngine.instance.getSimInfo();

    return _json(200, {
      'gatewayId': _gatewayId,
      'status': _status.name,
      'battery': batteryLevel,
      'sim': simInfo,
      'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  // ─── Helpers ───────────────────────────────────────────────────

  void _updateStatus(GatewayStatus newStatus) {
    _status = newStatus;
    onStatusChanged?.call(newStatus);
  }

  void _logSms(String requestId, String phone, String message, String status, String? error) {
    onSmsLog?.call(SmsLogEntry(
      requestId: requestId,
      phone: phone,
      message: message,
      status: status,
      error: error,
      timestamp: DateTime.now(),
    ));
  }

  String? _sanitizePhone(String phone) {
    // Strip spaces, dashes, parentheses
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    // Must start with + and digits, or just digits, 7-15 digits
    if (RegExp(r'^\+?\d{7,15}$').hasMatch(cleaned)) {
      return cleaned;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _readJsonBody(shelf.Request request) async {
    try {
      final bodyStr = await request.readAsString();
      return jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  shelf.Response _json(int statusCode, Map<String, dynamic> body) {
    return shelf.Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'Content-Type': 'application/json'},
    );
  }

  shelf.Middleware _corsMiddleware() {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        if (request.method == 'OPTIONS') {
          return shelf.Response.ok('', headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          });
        }
        final response = await innerHandler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
        });
      };
    };
  }
}
