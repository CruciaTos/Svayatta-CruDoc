import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:doctor_management_app/features/files/lan/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generates EC P-256 key pair, CSR, self-signed certificate and signs/verifies', () {
    // 1. Generate EC key pair
    final keyPair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final privateKey = keyPair.privateKey as ECPrivateKey;
    final publicKey = keyPair.publicKey as ECPublicKey;

    expect(privateKey, isNotNull);
    expect(publicKey, isNotNull);

    // 2. PEM conversions
    final privPem = CryptoUtils.encodeEcPrivateKeyToPem(privateKey);
    final pubPem = CryptoUtils.encodeEcPublicKeyToPem(publicKey);
    expect(privPem, contains('BEGIN EC PRIVATE KEY'));
    expect(pubPem, contains('BEGIN PUBLIC KEY'));

    final restoredPriv = CryptoUtils.ecPrivateKeyFromPem(privPem);
    final restoredPub = CryptoUtils.ecPublicKeyFromPem(pubPem);
    expect(restoredPriv, isNotNull);
    expect(restoredPub, isNotNull);

    // 3. CSR generation
    final csrPem = X509Utils.generateEccCsrPem(
      {'CN': 'CruDoc-test1234'},
      privateKey,
      publicKey,
    );
    expect(csrPem, contains('BEGIN CERTIFICATE REQUEST'));

    // 4. Self-signed certificate generation (5 years = 1825 days)
    final certPem = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csrPem,
      1825,
      sans: ['localhost', '127.0.0.1'],
    );
    expect(certPem, contains('BEGIN CERTIFICATE'));

    // 5. SHA-256 fingerprint of certificate
    final derBytes = CryptoUtils.getBytesFromPEMString(certPem);
    final certSha256 = sha256.convert(derBytes).toString();
    expect(certSha256.length, 64);

    // 6. Sign and verify
    final payload = utf8.encode('crudoc-lan-v1|serverDevice|nonce123|clientCertSha');
    final sig = CryptoUtils.ecSign(privateKey, Uint8List.fromList(payload));
    expect(sig, isNotNull);

    final verified = CryptoUtils.ecVerify(publicKey, Uint8List.fromList(payload), sig);
    expect(verified, isTrue);

    // Tampered payload fails
    final tampered = utf8.encode('crudoc-lan-v1|tampered|nonce123|clientCertSha');
    final verifiedTampered = CryptoUtils.ecVerify(publicKey, Uint8List.fromList(tampered), sig);
    expect(verifiedTampered, isFalse);
  });

  test('DeviceIdentity challenge format verification', () {
    final keyPair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final privKey = keyPair.privateKey as ECPrivateKey;
    final pubKey = keyPair.publicKey as ECPublicKey;

    final csr = X509Utils.generateEccCsrPem({'CN': 'CruDoc-dev1'}, privKey, pubKey);
    final cert = X509Utils.generateSelfSignedCertificate(privKey, csr, 365, sans: ['localhost']);

    const serverDevice = 'server_abc_12345';
    const nonce = 'random_nonce_60s_valid';
    const clientCertSha = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    final message = DeviceIdentity.challengeMessage(
      serverDeviceId: serverDevice,
      nonce: nonce,
      clientCertSha256: clientCertSha,
    );
    final sig = CryptoUtils.ecSign(privKey, Uint8List.fromList(utf8.encode(message)));

    // Serialize 64 bytes
    var rHex = sig.r.toRadixString(16);
    if (rHex.length % 2 != 0) rHex = '0$rHex';
    var sHex = sig.s.toRadixString(16);
    if (sHex.length % 2 != 0) sHex = '0$sHex';

    final rBytes = <int>[];
    for (var i = 0; i < rHex.length; i += 2) {
      rBytes.add(int.parse(rHex.substring(i, i + 2), radix: 16));
    }
    final sBytes = <int>[];
    for (var i = 0; i < sHex.length; i += 2) {
      sBytes.add(int.parse(sHex.substring(i, i + 2), radix: 16));
    }
    final combined = Uint8List(64);
    if (rBytes.length <= 32) {
      combined.setRange(32 - rBytes.length, 32, rBytes);
    } else {
      combined.setRange(0, 32, rBytes.sublist(rBytes.length - 32));
    }
    if (sBytes.length <= 32) {
      combined.setRange(64 - sBytes.length, 64, sBytes);
    } else {
      combined.setRange(32, 64, sBytes.sublist(sBytes.length - 32));
    }

    final sigBase64 = base64Encode(combined);

    final isValid = DeviceIdentity.verifyChallenge(
      certPem: cert,
      serverDeviceId: serverDevice,
      nonce: nonce,
      clientCertSha256: clientCertSha,
      signatureBase64: sigBase64,
    );
    expect(isValid, isTrue);

    // Wrong nonce fails
    final isWrongNonceValid = DeviceIdentity.verifyChallenge(
      certPem: cert,
      serverDeviceId: serverDevice,
      nonce: 'wrong_nonce',
      clientCertSha256: clientCertSha,
      signatureBase64: sigBase64,
    );
    expect(isWrongNonceValid, isFalse);
  });
}
