import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Computes the SHA-256 hash (64 lowercase hex characters) of a file
/// by streaming its bytes in chunks inside a background isolate.
///
/// Running inside a background isolate ensures that hashing large files
/// (e.g. 250 MB DICOM studies or high-res images) does not block the UI thread.
Future<String> computeFileSha256(String filePath) {
  return Isolate.run(() async {
    final file = File(filePath);
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  });
}

/// Computes the SHA-256 hash of an in-memory byte list.
String computeBytesSha256(Uint8List bytes) {
  return sha256.convert(bytes).toString();
}
