// Keeps the app's patient field encryption and the server's copy of it
// (functions/src/crypto/patientCipher.ts) in step.
//
// The server decrypts patient names and phones for WhatsApp reminders and the
// AI receptionist, and encrypts the patients the AI creates. If the two sides
// drift, the server reads ciphertext as a phone number (which is how
// reminders came to target random foreign numbers) or writes names the app
// can't read.
//
// The values below were produced by the Node code. The test prints values
// produced here; functions/test/patient-cipher.test.js decrypts those, so a
// change on either side fails a test on the other.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:doctor_management_app/core/services/encryption_key_manager.dart';
import 'package:doctor_management_app/core/services/field_cipher.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _clinicId = 'clinic_compat_test';
const _testPepper = 'test-pepper-not-the-real-one';

// Made by patientCipher.ts with the DEK below.
const _nodeKekHex =
    '613a7f949d4f78f42bde3dc2168e7ef0cce6bee9e8a4e500e472c64e3784071e';
const _nodeWrapped =
    'w8UtlC+kr3jtsehi.Tp2wVJqasUKVEZkrSpfDRxeP8RQXRY6CJmj8oUABTYWtkHLx2OpaKYhz/saHmjXx';
const _nodeName = 'enc:v1:qqgKseBzFbMfLfOz.AanED8ODEviUPQbf67VOiDo4qc2TZMwFGVLG2g==';
const _nodePhone = 'enc:v1:/oHZS/h4O8o+dc6d.dNxmBxkXa73f7iHajKjtiwpcX1rXWMNbvmYIpLFOoA==';
const _nodeMarathi = 'enc:v1:0vH9SbJL3B+EdojK.o9kOSHr66FAaIKR7rxPt+9aFFpJxZ/XBVAB9bA==';

Uint8List _dek() => Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) & 0xff));

// Mirrors EncryptionKeyManager._deriveKek / _wrap / _unwrap, which are private.
enc.Key _kek() => enc.Key(
  Uint8List.fromList(sha256.convert(utf8.encode('$_clinicId::$_testPepper')).bytes),
);

String _wrap(Uint8List dek, enc.Key kek) {
  final iv = enc.IV.fromSecureRandom(12);
  final encrypted = enc.Encrypter(
    enc.AES(kek, mode: enc.AESMode.gcm),
  ).encryptBytes(dek, iv: iv);
  return '${base64Encode(iv.bytes)}.${base64Encode(encrypted.bytes)}';
}

Uint8List _unwrap(String wrapped, enc.Key kek) {
  final parts = wrapped.split('.');
  final plain = enc.Encrypter(enc.AES(kek, mode: enc.AESMode.gcm)).decryptBytes(
    enc.Encrypted(base64Decode(parts[1])),
    iv: enc.IV(base64Decode(parts[0])),
  );
  return Uint8List.fromList(plain);
}

void main() {
  setUpAll(() async {
    // loadForDoctor takes the cached key from secure storage before it would
    // touch Firestore, so the real FieldCipher runs with a known key.
    FlutterSecureStorage.setMockInitialValues({
      'crudoc_dek_$_clinicId': base64Encode(_dek()),
    });
    await EncryptionKeyManager.instance.loadForDoctor(_clinicId);
  });

  test('KEK derivation matches the server', () {
    expect(_kek().bytes, equals(_hex(_nodeKekHex)));
  });

  test('a key wrapped by the server unwraps here', () {
    expect(_unwrap(_nodeWrapped, _kek()), equals(_dek()));
  });

  test('fields encrypted by the server decrypt with FieldCipher', () {
    expect(FieldCipher.decrypt(_nodeName), 'Ramesh Patil');
    expect(FieldCipher.decrypt(_nodePhone), '+91 98765 43210');
    expect(FieldCipher.decrypt(_nodeMarathi), 'रमेश');
  });

  test('values for the server test to decrypt', () {
    final wrapped = _wrap(_dek(), _kek());
    final name = FieldCipher.encrypt('Sunita Deshmukh');
    final phone = FieldCipher.encrypt('9822011111');
    expect(_unwrap(wrapped, _kek()), equals(_dek()));
    expect(FieldCipher.decrypt(name), 'Sunita Deshmukh');
    // Copied into functions/test/patient-cipher.test.js.
    // ignore: avoid_print
    print(jsonEncode({'wrapped': wrapped, 'name': name, 'phone': phone}));
  });
}

List<int> _hex(String hex) => [
  for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
];
