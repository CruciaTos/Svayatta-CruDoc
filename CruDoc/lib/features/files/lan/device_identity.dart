import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages this installation's device identity (Task K1):
/// - A persistent 16-character [deviceId]
/// - An ECDSA P-256 private key stored strictly in secure storage (Keystore / DPAPI)
/// - A self-signed TLS certificate (valid 5 years) and its SHA-256 fingerprint [certSha256]
/// - Challenge/response authentication methods for LAN direct transfer.
class DeviceIdentity {
  DeviceIdentity._();
  static final DeviceIdentity instance = DeviceIdentity._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    wOptions: WindowsOptions(useBackwardCompatibility: false),
  );

  static const _keyDeviceId = 'crudoc.lan.deviceId';
  static const _keyDeviceName = 'crudoc.lan.deviceName';
  static const _keyPrivKey = 'crudoc.lan.privateKeyPem';
  static const _keyCertPem = 'crudoc.lan.certPem';
  static const _keyCertSha = 'crudoc.lan.certSha256';

  bool _initialized = false;
  late String _deviceId;
  late String _deviceName;
  late String _platform;
  late String _privateKeyPem;
  late String _certPem;
  late String _certSha256;

  // '' until [initialize] has finished, instead of a LateInitializationError
  // (a screen can build before the identity has loaded).
  String get deviceId => _initialized ? _deviceId : '';
  String get deviceName => _initialized ? _deviceName : '';
  String get platform => _initialized ? _platform : '';
  String get certPem => _initialized ? _certPem : '';
  String get certSha256 => _initialized ? _certSha256 : '';
  bool get isInitialized => _initialized;

  Future<void>? _initializing;

  /// Loads or generates the device identity on first use. Callers at the
  /// same time share one run, so two can never make two different keys.
  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _load().whenComplete(() => _initializing = null);
  }

  Future<void> _load() async {
    if (_initialized) return;

    _platform = Platform.isAndroid
        ? 'android'
        : (Platform.isWindows ? 'windows' : Platform.operatingSystem);

    final storedId = await _storage.read(key: _keyDeviceId);
    final storedPrivKey = await _storage.read(key: _keyPrivKey);
    final storedCert = await _storage.read(key: _keyCertPem);
    final storedSha = await _storage.read(key: _keyCertSha);
    final storedName = await _storage.read(key: _keyDeviceName);

    if (storedId != null &&
        storedPrivKey != null &&
        storedCert != null &&
        storedSha != null) {
      _deviceId = storedId;
      _privateKeyPem = storedPrivKey;
      _certPem = storedCert;
      _certSha256 = storedSha;
      _deviceName = storedName ?? _defaultDeviceName();
      _initialized = true;
      return;
    }

    // Generate new identity
    _deviceId = _generateRandomId(16);
    _deviceName = storedName ?? _defaultDeviceName();

    // 1. Generate ECDSA P-256 key pair
    final keyPair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final privKey = keyPair.privateKey as ECPrivateKey;
    final pubKey = keyPair.publicKey as ECPublicKey;

    _privateKeyPem = CryptoUtils.encodeEcPrivateKeyToPem(privKey);

    // 2. Generate CSR and self-signed certificate (5 years = 1825 days)
    final csrPem = X509Utils.generateEccCsrPem(
      {'CN': 'CruDoc-$_deviceId'},
      privKey,
      pubKey,
    );

    _certPem = X509Utils.generateSelfSignedCertificate(
      privKey,
      csrPem,
      1825,
      sans: ['localhost', '127.0.0.1'],
    );

    // 3. Calculate SHA-256 fingerprint of DER bytes
    final derBytes = CryptoUtils.getBytesFromPEMString(_certPem);
    _certSha256 = sha256.convert(derBytes).toString().toLowerCase();

    // 4. Persist securely
    await _storage.write(key: _keyDeviceId, value: _deviceId);
    await _storage.write(key: _keyDeviceName, value: _deviceName);
    await _storage.write(key: _keyPrivKey, value: _privateKeyPem);
    await _storage.write(key: _keyCertPem, value: _certPem);
    await _storage.write(key: _keyCertSha, value: _certSha256);

    _initialized = true;
  }

  /// Sets a custom friendly name for this device.
  Future<void> setDeviceName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _deviceName = trimmed;
    await _storage.write(key: _keyDeviceName, value: _deviceName);
  }

  /// Creates a [SecurityContext] for [HttpServer.bindSecure] using this device's cert and key.
  SecurityContext createServerSecurityContext() {
    final context = SecurityContext();
    context.useCertificateChainBytes(utf8.encode(_certPem));
    context.usePrivateKeyBytes(utf8.encode(_privateKeyPem));
    return context;
  }

  /// Signs the challenge payload with our private key.
  /// Payload format: `"crudoc-lan-v1" | serverDeviceId | nonce | clientCertSha256`.
  String signChallenge({
    required String serverDeviceId,
    required String nonce,
    required String clientCertSha256,
  }) {
    final message = challengeMessage(
      serverDeviceId: serverDeviceId,
      nonce: nonce,
      clientCertSha256: clientCertSha256,
    );
    final privKey = CryptoUtils.ecPrivateKeyFromPem(_privateKeyPem);
    final sig = CryptoUtils.ecSign(
      privKey,
      Uint8List.fromList(utf8.encode(message)),
    );
    // Serialize r and s as 32-byte hex or DER
    final rBytes = _bigIntTo32Bytes(sig.r);
    final sBytes = _bigIntTo32Bytes(sig.s);
    final combined = Uint8List(64);
    combined.setRange(0, 32, rBytes);
    combined.setRange(32, 64, sBytes);
    return base64Encode(combined);
  }

  /// Verifies a peer's challenge signature against their certificate PEM.
  static bool verifyChallenge({
    required String certPem,
    required String serverDeviceId,
    required String nonce,
    required String clientCertSha256,
    required String signatureBase64,
  }) {
    try {
      final message = challengeMessage(
        serverDeviceId: serverDeviceId,
        nonce: nonce,
        clientCertSha256: clientCertSha256,
      );

      final pubKey = _extractPublicKeyFromCert(certPem);
      if (pubKey == null) return false;

      final sigBytes = base64Decode(signatureBase64);
      if (sigBytes.length != 64) return false;

      final r = _bytesToBigInt(sigBytes.sublist(0, 32));
      final s = _bytesToBigInt(sigBytes.sublist(32, 64));
      final sig = ECSignature(r, s);

      return CryptoUtils.ecVerify(
        pubKey,
        Uint8List.fromList(utf8.encode(message)),
        sig,
      );
    } catch (e) {
      debugPrint('[DeviceIdentity] Verification error: $e');
      return false;
    }
  }

  static String challengeMessage({
    required String serverDeviceId,
    required String nonce,
    required String clientCertSha256,
  }) => 'crudoc-lan-v1|$serverDeviceId|$nonce|$clientCertSha256';

  static ECPublicKey? _extractPublicKeyFromCert(String certPem) {
    try {
      final certData = X509Utils.x509CertificateFromPem(certPem);
      // ignore: deprecated_member_use
      final hexStr = certData.publicKeyData.bytes;
      if (hexStr == null || hexStr.isEmpty) return null;
      final bytes = Uint8List(hexStr.length ~/ 2);
      for (var i = 0; i < hexStr.length; i += 2) {
        bytes[i ~/ 2] = int.parse(hexStr.substring(i, i + 2), radix: 16);
      }
      return CryptoUtils.ecPublicKeyFromDerBytes(bytes);
    } catch (e) {
      debugPrint('[DeviceIdentity] Failed to extract public key: $e');
      return null;
    }
  }

  static String _defaultDeviceName() {
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) return host;
    } catch (_) {}
    return Platform.isAndroid ? 'Android Device' : 'Windows PC';
  }

  static String _generateRandomId(int length) {
    const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  static Uint8List _bigIntTo32Bytes(BigInt number) {
    var hex = number.toRadixString(16);
    if (hex.length % 2 != 0) hex = '0$hex';
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    final result = Uint8List(32);
    if (bytes.length <= 32) {
      result.setRange(32 - bytes.length, 32, bytes);
    } else {
      result.setRange(0, 32, bytes.sublist(bytes.length - 32));
    }
    return result;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return BigInt.parse(hex, radix: 16);
  }
}
