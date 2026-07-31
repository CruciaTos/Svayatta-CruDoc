import 'dart:convert';

import 'package:encrypt/encrypt.dart' as enc;

import 'encryption_key_manager.dart';

/// Encrypts/decrypts individual sensitive string fields (patient name,
/// phone, diagnosis, notes, etc.) using the current doctor's DEK from
/// [EncryptionKeyManager].
///
/// Deliberately field-level rather than whole-document: fields that
/// Firestore/SQLite need to query, sort, or filter on (ids, timestamps,
/// booleans, amounts, `doctorId`) are left in plain form. Only free-text
/// PHI is encrypted.
///
/// Values are tagged with a short prefix so already-encrypted data isn't
/// re-encrypted, and so plaintext written before this feature existed
/// still reads back correctly instead of throwing.
class FieldCipher {
  static const String _prefix = 'enc:v1:';

  static bool get isReady => EncryptionKeyManager.instance.isReady;

  /// Encrypts [plainText]. Returns it unchanged if empty or if no key is
  /// loaded yet (caller should ensure [EncryptionKeyManager.loadForDoctor]
  /// has completed before syncing; this fallback just avoids crashing a
  /// write if it hasn't).
  static String encrypt(String? plainText) {
    if (plainText == null || plainText.isEmpty) return plainText ?? '';
    if (plainText.startsWith(_prefix)) return plainText; // already encrypted

    final key = EncryptionKeyManager.instance.currentKey;
    if (key == null) return plainText;

    final iv = enc.IV.fromSecureRandom(12);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '$_prefix${base64Encode(iv.bytes)}.${encrypted.base64}';
  }

  /// Decrypts a value produced by [encrypt]. Values without the marker
  /// prefix are returned unchanged (legacy/plaintext data).
  static String decrypt(String? value) {
    if (value == null || value.isEmpty) return value ?? '';
    if (!value.startsWith(_prefix)) return value;

    final key = EncryptionKeyManager.instance.currentKey;
    if (key == null) return value; // can't decrypt yet — surface ciphertext rather than crash

    try {
      final body = value.substring(_prefix.length);
      final parts = body.split('.');
      final iv = enc.IV(base64Decode(parts[0]));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      return encrypter.decrypt(enc.Encrypted.fromBase64(parts[1]), iv: iv);
    } catch (_) {
      // Wrong/missing key (e.g. mid-migration) — surface ciphertext rather
      // than throw and break the whole list render.
      return value;
    }
  }
}
