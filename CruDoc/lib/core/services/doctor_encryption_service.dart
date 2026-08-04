import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';

/// Encrypts doctor profile fields using a doctor-specific key derived from the
/// doctor UID. This keeps the data unreadable in Firestore while still allowing
/// the app to decrypt it for the correct doctor on login.
class DoctorEncryptionService {
  static const String _prefix = 'enc:v1:';

  static String encryptForDoctor(String? plainText, String doctorId) {
    if (plainText == null || plainText.isEmpty) return plainText ?? '';
    if (plainText.startsWith(_prefix)) return plainText;

    final key = _deriveKey(doctorId);
    final iv = enc.IV.fromSecureRandom(12);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '$_prefix${base64Encode(iv.bytes)}.${encrypted.base64}';
  }

  static String decryptForDoctor(String? value, String doctorId) {
    if (value == null || value.isEmpty) return value ?? '';
    if (!value.startsWith(_prefix)) return value;

    final key = _deriveKey(doctorId);

    try {
      final body = value.substring(_prefix.length);
      final parts = body.split('.');
      final iv = enc.IV(base64Decode(parts[0]));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      return encrypter.decrypt(enc.Encrypted.fromBase64(parts[1]), iv: iv);
    } catch (_) {
      return value;
    }
  }

  static enc.Key _deriveKey(String doctorId) {
    final digest = sha256.convert(utf8.encode('crudoc-doctor-profile::$doctorId'));
    return enc.Key(Uint8List.fromList(digest.bytes));
  }
}
