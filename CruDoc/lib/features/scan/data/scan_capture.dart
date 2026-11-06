import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/features/scan/data/docscan/page_render.dart';
import 'package:doctor_management_app/features/scan/presentation/document_camera_page.dart';

/// One scanned page: found, cropped and straightened by the scanner, then
/// re-encoded small enough to keep. [jpeg] is the copy saved with whatever
/// the scan is used for, and the copy the AI reads.
class ScannedPage {
  const ScannedPage({
    required this.jpeg,
    required this.thumb,
    required this.width,
    required this.height,
  });

  final Uint8List jpeg;

  /// About 360 px on the long edge, for the strips on the review pages.
  final Uint8List thumb;
  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 0.71 : width / height;
}

/// The scanner could not open (no camera permission, scanner missing).
class ScanCaptureException implements Exception {
  const ScanCaptureException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Takes pictures of paper. Phones open CruDoc's document camera
/// ([DocumentCameraPage]): it finds the page's four corners live, waits
/// until the page is steady, sharp and well lit, picks the best of several
/// frames and straightens it. If that camera cannot open, the system
/// scanner (ML Kit on Android, Vision on iOS) is used instead. Computers
/// pick picture files.
abstract final class ScanCapture {
  /// Kept pages: sharp enough to read small print, small enough to sync.
  static const int _maxLongEdge = PageRender.maxLongEdge;
  static const int _jpegQuality = PageRender.jpegQuality;
  static const int _thumbLongEdge = PageRender.thumbLongEdge;

  static bool get hasCamera =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// The pages in order; empty when the person backed out.
  static Future<List<ScannedPage>> capture(
    BuildContext context, {
    int maxPages = 10,
  }) async {
    if (hasCamera) {
      final result = await DocumentCameraPage.open(context, maxPages: maxPages);
      if (result.error != null) throw ScanCaptureException(result.error!);
      if (!result.fallback) {
        return [
          for (final p in result.pages)
            ScannedPage(
              jpeg: p.jpeg,
              thumb: p.thumb,
              width: p.width,
              height: p.height,
            ),
        ];
      }
    }
    final paths = hasCamera ? await _scan(maxPages) : await _pick(maxPages);
    if (paths.isEmpty) return const [];
    final pages = <ScannedPage>[];
    for (final path in paths) {
      try {
        final page = await compute(_shrink, await File(path).readAsBytes());
        if (page != null) pages.add(page);
      } catch (e) {
        debugPrint('[ScanCapture] skipped a page: $e');
      }
    }
    // The scanner's own full-size files are copied; let them go.
    if (hasCamera) {
      unawaited(CunningDocumentScanner.cleanCache().catchError((Object _) {}));
    }
    return pages;
  }

  /// One scanned page saved as a JPEG in the app's temporary folder, for
  /// readers that need a file (ML Kit receipt reading). Null when the
  /// person backed out.
  static Future<String?> captureOneToFile(BuildContext context) async {
    final pages = await capture(context, maxPages: 1);
    if (pages.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      'scan_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(pages.first.jpeg, flush: true);
    return file.path;
  }

  static Future<List<String>> _scan(int maxPages) async {
    try {
      final paths = await CunningDocumentScanner.getPictures(
        noOfPages: maxPages,
        // Android shows a gallery shortcut in the camera; iOS would ask
        // "camera or gallery" first, so it opens straight on the camera.
        scannerSource: Platform.isAndroid
            ? ScannerSource.cameraAndGallery
            : ScannerSource.camera,
        iosScannerOptions: IosScannerOptions(
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: 0.9,
        ),
      );
      return paths ?? const [];
    } on CunningDocumentScannerException catch (e) {
      throw ScanCaptureException(
        e.code == 'permission_denied'
            ? 'CruDoc needs the camera to scan. Allow it in Settings and try again.'
            : "The scanner couldn't open (${e.code ?? e.message}).",
      );
    }
  }

  static Future<List<String>> _pick(int maxPages) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    return [
      for (final f in result?.files ?? const <PlatformFile>[])
        if (f.path != null) f.path!,
    ].take(maxPages).toList();
  }
}

/// Top-level so it runs on a background isolate.
ScannedPage? _shrink(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var page = img.bakeOrientation(decoded);
  page = _fit(page, ScanCapture._maxLongEdge);
  final thumb = _fit(page, ScanCapture._thumbLongEdge);
  return ScannedPage(
    jpeg: img.encodeJpg(page, quality: ScanCapture._jpegQuality),
    thumb: img.encodeJpg(thumb, quality: 70),
    width: page.width,
    height: page.height,
  );
}

img.Image _fit(img.Image image, int longEdge) {
  final long = math.max(image.width, image.height);
  if (long <= longEdge) return image;
  final scale = longEdge / long;
  return img.copyResize(
    image,
    width: (image.width * scale).round(),
    height: (image.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
}
