import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crudoc_j2k/crudoc_j2k.dart';
import 'package:flutter_test/flutter_test.dart';

File _findFixture(String name) {
  final candidate1 = File('test/fixtures/$name');
  if (candidate1.existsSync()) return candidate1;
  final candidate2 = File('packages/crudoc_j2k/test/fixtures/$name');
  if (candidate2.existsSync()) return candidate2;
  throw StateError(
    'Fixture $name not found at test/fixtures/$name or packages/crudoc_j2k/test/fixtures/$name',
  );
}

void main() {
  final libEnv = Platform.environment['CRUDOC_J2K_LIB'];
  final bool shouldSkip = libEnv == null || libEnv.isEmpty;

  group('crudoc_j2k test', () {
    late Uint8List j2cBytes;
    late Uint8List rawlBytes;
    late Map<String, dynamic> metadata;

    setUpAll(() {
      if (shouldSkip) return;

      final metaFile = _findFixture('synthetic.json');
      metadata = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;

      final j2cFile = _findFixture('synthetic_a.j2c');
      j2cBytes = j2cFile.readAsBytesSync();

      final rawlFile = _findFixture('synthetic.rawl');
      rawlBytes = rawlFile.readAsBytesSync();
    });

    test('full decode equals synthetic.rawl (read as little-endian uint16) exactly', () {
      final img = decodeJ2k(j2cBytes, reduce: 0);

      expect(img.width, metadata['width']);
      expect(img.height, metadata['height']);
      expect(img.precision, metadata['bitsStored']);
      expect(img.signed, metadata['signed']);

      final int totalPixels = img.width * img.height;
      expect(img.pixels.length, totalPixels);

      final ByteData rawByteData = ByteData.sublistView(rawlBytes);
      for (int i = 0; i < totalPixels; i++) {
        final int expectedPixel = rawByteData.getUint16(i * 2, Endian.little);
        if (img.pixels[i] != expectedPixel) {
          fail('Pixel mismatch at index $i: expected $expectedPixel, got ${img.pixels[i]}');
        }
      }
    });

    test('preview decode gives half resolution', () {
      final int previewEnd = metadata['previewEnd_a'] as int;
      final previewBytes = Uint8List.fromList([
        ...j2cBytes.sublist(0, previewEnd),
        0xFF,
        0xD9,
      ]);

      final img = decodeJ2k(previewBytes, reduce: 1);
      final int origW = metadata['width'] as int;
      final int origH = metadata['height'] as int;
      final int expectedW = (origW + 1) ~/ 2;
      final int expectedH = (origH + 1) ~/ 2;

      expect(img.width, expectedW);
      expect(img.height, expectedH);
      expect(img.pixels.length, expectedW * expectedH);
    });
  }, skip: shouldSkip ? 'CRUDOC_J2K_LIB environment variable not set' : null);
}
