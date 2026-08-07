import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionKeyManager {
  EncryptionKeyManager._();

  static final EncryptionKeyManager instance = EncryptionKeyManager._();

  static final FlutterSecureStorage _secureStorage = kIsWeb
      ? const FlutterSecureStorage()
      : const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  // NOTE: this is a defense-in-depth constant, not a secret the app can
  // truly keep — anyone with the app binary can extract it. See the class
  // doc comment above for what this scheme does and doesn't protect against.
  static const String _appPepper =
      '7TKgLHp1WG3Mh2yywTCgZWDXJ7rLcwZ161LiZ9ct8SE=';

  enc.Key? _activeKey;
  String? _activeDoctorId;

  /// The currently loaded per-doctor key, if [loadForDoctor] has completed.
  enc.Key? get currentKey => _activeKey;

  bool get isReady => _activeKey != null;

  /// Loads (creating if necessary) the DEK for [doctorId]. Safe to call
  /// repeatedly — it's a no-op if the key for this doctor is already loaded.
  Future<void> loadForDoctor(String doctorId) async {
    if (_activeDoctorId == doctorId && _activeKey != null) return;

    final cacheKey = 'crudoc_dek_$doctorId';
    final cachedRawKey = await _secureStorage.read(key: cacheKey);
    if (cachedRawKey != null) {
      _activeKey = enc.Key(base64Decode(cachedRawKey));
      _activeDoctorId = doctorId;
      return;
    }

    final kek = _deriveKek(doctorId);
    final doc = await FirebaseFirestore.instance
        .collection('doctor_keys')
        .doc(doctorId)
        .get();

    late final enc.Key dek;
    if (doc.exists && doc.data()?['wrappedKey'] is String) {
      dek = _unwrap(doc.data()!['wrappedKey'] as String, kek);
    } else {
      dek = enc.Key.fromSecureRandom(32);
      final wrapped = _wrap(dek, kek);
      await FirebaseFirestore.instance
          .collection('doctor_keys')
          .doc(doctorId)
          .set({
        'wrappedKey': wrapped,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await _secureStorage.write(
      key: cacheKey,
      value: base64Encode(dek.bytes),
    );
    _activeKey = dek;
    _activeDoctorId = doctorId;
  }

  /// Clears the in-memory key (called on sign-out). The wrapped key and the
  /// secure-storage cache are left intact so the doctor doesn't lose access
  /// to their data next time they sign in on this or another device.
  void clear() {
    _activeKey = null;
    _activeDoctorId = null;
  }

  enc.Key _deriveKek(String doctorId) {
    final digest = sha256.convert(utf8.encode('$doctorId::$_appPepper'));
    return enc.Key(Uint8List.fromList(digest.bytes));
  }

  String _wrap(enc.Key dek, enc.Key kek) {
    final iv = enc.IV.fromSecureRandom(12);
    final encrypter = enc.Encrypter(enc.AES(kek, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encryptBytes(dek.bytes, iv: iv);
    return '${base64Encode(iv.bytes)}.${base64Encode(encrypted.bytes)}';
  }

  enc.Key _unwrap(String wrapped, enc.Key kek) {
    final parts = wrapped.split('.');
    final iv = enc.IV(base64Decode(parts[0]));
    final cipherBytes = base64Decode(parts[1]);
    final encrypter = enc.Encrypter(enc.AES(kek, mode: enc.AESMode.gcm));
    final plainBytes = encrypter.decryptBytes(
      enc.Encrypted(cipherBytes),
      iv: iv,
    );
    return enc.Key(Uint8List.fromList(plainBytes));
  }
}

// TODO(security-upgrade): for a stronger threat model than the pepper-based
// KEK above, add an optional doctor-chosen "data passphrase" set once during
// onboarding: derive the KEK with `Pbkdf2(passphrase, salt: doctorId, iterations: 100000)`
// instead of `_deriveKek`, and prompt for the same passphrase the first time
// each new device signs in. Show the doctor a one-time recovery code when
// they set it, since there is no server-side password reset for it.