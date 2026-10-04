import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_view_fetch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rad_view_fetch_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final syntheticBytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
  final expectedSha256 = sha256.convert(syntheticBytes).toString();
  const previewEnd = 300;
  final total = syntheticBytes.length;

  RadViewInfo makeTestInfo({
    String url = 'https://example.com/frame_0.j2c',
    String? hash,
  }) {
    return RadViewInfo(
      status: 'ready',
      codec: 'htj2k',
      width: 512,
      height: 512,
      frames: 1,
      frameFiles: [
        RadViewFrame(
          url: url,
          total: total,
          previewEnd: previewEnd,
          sha256: hash ?? expectedSha256,
        ),
      ],
    );
  }

  test('preview then full: range requests and exact full bytes', () async {
    final List<String> requestedRanges = [];

    final client = MockClient((request) async {
      final range = request.headers['Range'] ?? '';
      requestedRanges.add(range);

      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
      if (match == null) {
        return http.Response('Invalid range', 400);
      }
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      final chunk = syntheticBytes.sublist(start, end + 1);

      return http.Response.bytes(
        chunk,
        206,
        headers: {
          'Content-Range': 'bytes $start-$end/$total',
          'Content-Length': '${chunk.length}',
        },
      );
    });

    final fetch = RadViewFetch(
      httpClient: client,
      getInfo: (path) async => makeTestInfo(),
    );

    // 1. Preview
    final previewFile = await fetch.ensure(
      studyDir: tempDir,
      imageId: 'img1',
      storagePath: 'doctors/doc1/patients/pat1/clinical/imaging/test.dcm',
      frame: 0,
      full: false,
    );

    expect(requestedRanges.length, 1);
    expect(requestedRanges[0], 'bytes=0-${previewEnd - 1}');
    expect(await previewFile.length(), previewEnd);
    expect(await previewFile.readAsBytes(), syntheticBytes.sublist(0, previewEnd));

    // Sidecar check
    final sidecar = File('${tempDir.path}/.views/img1/frame_0.json');
    expect(await sidecar.exists(), isTrue);
    final sidecarData = jsonDecode(await sidecar.readAsString());
    expect(sidecarData['have'], previewEnd);

    // 2. Full
    final fullFile = await fetch.ensure(
      studyDir: tempDir,
      imageId: 'img1',
      storagePath: 'doctors/doc1/patients/pat1/clinical/imaging/test.dcm',
      frame: 0,
      full: true,
    );

    expect(requestedRanges.length, 2);
    expect(requestedRanges[1], 'bytes=$previewEnd-${total - 1}');
    expect(await fullFile.length(), total);
    expect(await fullFile.readAsBytes(), syntheticBytes);
  });

  test('resume: a .j2c longer than have is truncated before downloading', () async {
    final viewsDir = Directory('${tempDir.path}/.views/img1');
    await viewsDir.create(recursive: true);

    final j2cFile = File('${viewsDir.path}/frame_0.j2c');
    await j2cFile.writeAsBytes(syntheticBytes.sublist(0, 450));

    final sidecar = File('${viewsDir.path}/frame_0.json');
    await sidecar.writeAsString(jsonEncode({
      'total': total,
      'previewEnd': previewEnd,
      'sha256': expectedSha256,
      'have': 200,
    }));

    final List<String> requestedRanges = [];
    final client = MockClient((request) async {
      final range = request.headers['Range'] ?? '';
      requestedRanges.add(range);

      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
      final start = int.parse(match!.group(1)!);
      final end = int.parse(match.group(2)!);
      return http.Response.bytes(syntheticBytes.sublist(start, end + 1), 206);
    });

    final fetch = RadViewFetch(
      httpClient: client,
      getInfo: (path) async => makeTestInfo(),
    );

    final resultFile = await fetch.ensure(
      studyDir: tempDir,
      imageId: 'img1',
      storagePath: 'doctors/doc1/patients/pat1/clinical/imaging/test.dcm',
      frame: 0,
      full: false,
    );

    expect(requestedRanges.length, 1);
    expect(requestedRanges[0], 'bytes=200-${previewEnd - 1}');
    expect(await resultFile.length(), previewEnd);
    expect(await resultFile.readAsBytes(), syntheticBytes.sublist(0, previewEnd));
  });

  test('checksum mismatch throws and deletes the files', () async {
    final client = MockClient((request) async {
      final range = request.headers['Range'] ?? '';
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
      final start = int.parse(match!.group(1)!);
      final end = int.parse(match.group(2)!);
      return http.Response.bytes(syntheticBytes.sublist(start, end + 1), 206);
    });

    final fetch = RadViewFetch(
      httpClient: client,
      getInfo: (path) async => makeTestInfo(hash: 'bad_checksum_hash_0000'),
    );

    final viewsDir = Directory('${tempDir.path}/.views/img1');
    final j2cFile = File('${viewsDir.path}/frame_0.j2c');
    final sidecar = File('${viewsDir.path}/frame_0.json');

    await expectLater(
      () => fetch.ensure(
        studyDir: tempDir,
        imageId: 'img1',
        storagePath: 'doctors/doc1/patients/pat1/clinical/imaging/test.dcm',
        frame: 0,
        full: true,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await j2cFile.exists(), isFalse);
    expect(await sidecar.exists(), isFalse);
  });

  test('short download: throws HttpException and sidecar records partial bytes', () async {
    final client = MockClient((request) async {
      final range = request.headers['Range'] ?? '';
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
      final start = int.parse(match!.group(1)!);
      final end = int.parse(match.group(2)!);
      final requestedLen = end - start + 1;
      final halfLen = requestedLen ~/ 2;
      final chunk = syntheticBytes.sublist(start, start + halfLen);
      return http.Response.bytes(
        chunk,
        206,
        headers: {
          'Content-Range': 'bytes $start-${start + halfLen - 1}/$total',
          'Content-Length': '$halfLen',
        },
      );
    });

    final fetch = RadViewFetch(
      httpClient: client,
      getInfo: (path) async => makeTestInfo(),
    );

    await expectLater(
      () => fetch.ensure(
        studyDir: tempDir,
        imageId: 'img1',
        storagePath: 'doctors/doc1/patients/pat1/clinical/imaging/test.dcm',
        frame: 0,
        full: true,
      ),
      throwsA(isA<HttpException>()),
    );

    final sidecar = File('${tempDir.path}/.views/img1/frame_0.json');
    expect(await sidecar.exists(), isTrue);
    final sidecarData = jsonDecode(await sidecar.readAsString());
    expect(sidecarData['have'], total ~/ 2);
  });
}
