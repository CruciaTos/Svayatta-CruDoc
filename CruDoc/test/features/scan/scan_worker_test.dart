import 'dart:typed_data';

import 'package:camera/camera.dart';
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:doctor_management_app/features/scan/data/docscan/pixels.dart';
import 'package:doctor_management_app/features/scan/data/docscan/scan_engine.dart';
import 'package:doctor_management_app/features/scan/data/docscan/scan_worker.dart';

import 'docscan_test.dart' as scene;

/// An Android-style YUV_420_888 frame: Y with row padding, and U/V planes
/// that interleave (pixel stride 2), the way CameraX delivers them.
CameraImage androidFrame(Uint8List upright, int w, int h) {
  final sensor = rotateGray(GrayImage(w, h, upright), 270); // landscape
  final sw = sensor.width, sh = sensor.height;
  const pad = 32;
  final yRow = sw + pad;
  final y = Uint8List(yRow * sh);
  for (var r = 0; r < sh; r++) {
    y.setRange(r * yRow, r * yRow + sw, sensor.data, r * sw);
  }
  final cw = sw ~/ 2, ch = sh ~/ 2;
  final cRow = cw * 2 + pad;
  // One VU-interleaved buffer, seen as two overlapping planes. A bluish
  // page (U high) checks colour comes out right too.
  final vu = Uint8List(cRow * ch);
  for (var r = 0; r < ch; r++) {
    for (var c = 0; c < cw; c++) {
      vu[r * cRow + 2 * c] = 128; // V
      vu[r * cRow + 2 * c + 1] = 160; // U
    }
  }
  return CameraImage.fromPlatformInterface(
    CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
      width: sw,
      height: sh,
      planes: [
        CameraImagePlane(bytes: y, bytesPerRow: yRow, bytesPerPixel: 1),
        CameraImagePlane(
          bytes: Uint8List.sublistView(vu, 1),
          bytesPerRow: cRow,
          bytesPerPixel: 2,
        ),
        CameraImagePlane(
          bytes: Uint8List.sublistView(vu, 0, vu.length - 1),
          bytesPerRow: cRow,
          bytesPerPixel: 2,
        ),
      ],
    ),
  );
}

void main() {
  test(
    'frames go through the worker isolate and come back as one page',
    () async {
      final worker = await ScanWorker.start();
      addTearDown(worker.dispose);
      final image = androidFrame(
        scene.renderScene(scene.fw, scene.fh, scene.tilted),
        scene.fw,
        scene.fh,
      );
      final updates = <WorkerUpdate>[];
      final sub = worker.updates.listen(updates.add);
      addTearDown(sub.cancel);

      var offered = 0;
      var refused = 0;
      for (var i = 0; i < 14; i++) {
        if (worker.offer(
          image,
          rotation: 90,
          quarterTurns: 0,
          fullRange: true,
        )) {
          offered++;
        }
        // A second offer while busy is skipped, never queued.
        if (!worker.offer(
          image,
          rotation: 90,
          quarterTurns: 0,
          fullRange: true,
        )) {
          refused++;
        }
        while (worker.busy) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(offered, 14);
      expect(refused, 14);
      expect(updates, hasLength(14));

      final pages = [
        for (final u in updates)
          if (u.page != null) u.page!,
      ];
      expect(pages, hasLength(1));
      expect(updates.last.phase, ScanPhase.saved);

      // The outline is in screen fractions, matching the scene's page.
      final q = updates[updates.length - 2].quad!;
      expect(q.tl.x * scene.fw, closeTo(scene.tilted.tl.x, 6));
      expect(q.br.y * scene.fh, closeTo(scene.tilted.br.y, 6));

      // Paper comes out light and slightly blue (U above neutral).
      final out = img.decodeJpg(pages.single.jpeg)!;
      final p = out.getPixel(out.width ~/ 2, out.height - 20);
      expect(p.b, greaterThan(p.r + 20));
      expect(p.luminance, greaterThan(180));
    },
  );

  test('a phone held sideways turns the saved page', () async {
    final worker = await ScanWorker.start();
    addTearDown(worker.dispose);
    final image = androidFrame(
      scene.renderScene(scene.fw, scene.fh, scene.tilted),
      scene.fw,
      scene.fh,
    );
    WorkerUpdate? withPage;
    final sub = worker.updates.listen((u) {
      if (u.page != null) withPage = u;
    });
    addTearDown(sub.cancel);
    for (var i = 0; i < 14 && withPage == null; i++) {
      worker.offer(image, rotation: 90, quarterTurns: 1, fullRange: true);
      while (worker.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
    final page = withPage!.page!;
    expect(page.width, greaterThan(page.height));
  });
}
