import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/dicom/dicom_file.dart';
import 'package:doctor_management_app/features/radiology/viewer/annotation_painter.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_pane.dart';

/// Draws [pane] as the doctor sees it — the image through its window,
/// zoom, rotation and flips, with the annotations and scale bar burned
/// in when [withAnnotations] — at [ratio]× the pane's size.
Future<ui.Image?> radRenderPaneView(
  RadPane pane, {
  required List<RadAnnotation> annotations,
  required double? mmPerPx,
  bool withAnnotations = true,
  double ratio = 2,
  RadRoiCache? roi,
}) async {
  final px = pane.px;
  final size = pane.viewport;
  if (px == null || size.isEmpty) return null;
  final full = await pane.renderFull();
  if (full == null) return null;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)..scale(ratio);
  canvas.drawRect(Offset.zero & size, Paint()..color = RadInk.viewport);
  canvas.save();
  pane.applyTransform(canvas);
  canvas.drawImageRect(
    full,
    Rect.fromLTWH(0, 0, full.width.toDouble(), full.height.toDouble()),
    Rect.fromLTWH(0, 0, px.width.toDouble(), px.height.toDouble()),
    Paint()..filterQuality = pane.zoom >= 2.5 ? FilterQuality.none : FilterQuality.high,
  );
  canvas.restore();
  if (withAnnotations) {
    RadAnnotationPainter(toScreen: pane.pointToScreen, mmPerPx: mmPerPx, roi: roi, px: px)
        .paintAll(canvas, annotations);
    if (mmPerPx != null && pane.zoom > 0) radPaintScaleBar(canvas, size, mmPerPx / pane.zoom);
  }
  final picture = rec.endRecording();
  final out = await picture.toImage((size.width * ratio).round(), (size.height * ratio).round());
  picture.dispose();
  full.dispose();
  return out;
}

Future<Uint8List?> radEncodePng(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.png))?.buffer.asUint8List();

/// JPEG at quality 92, encoded off the UI thread.
Future<Uint8List?> radEncodeJpg(ui.Image image) async {
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (raw == null) return null;
  return _encodeJpg(raw.buffer, image.width, image.height);
}

Future<Uint8List> _encodeJpg(ByteBuffer rgba, int w, int h) => Isolate.run(() => img.encodeJpg(
      img.Image.fromBytes(width: w, height: h, bytes: rgba, numChannels: 4),
      quality: 92,
    ));

/// A file-name-safe version of [s].
String radSafeName(String s) =>
    s.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(RegExp(r'_+'), '_');

/// "Priya_Shah_OPG_2025-03-12".
String radExportName(RadStudy s) =>
    radSafeName('${s.patientName} ${s.modality.short} ${DateFormat('yyyy-MM-dd').format(s.studyDate)}');

/// Asks where to save [bytes]; returns the path, or null if cancelled.
Future<String?> radSaveBytes({
  required String dialogTitle,
  required String fileName,
  required String extension,
  required Uint8List bytes,
}) async {
  final path = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: [extension],
    bytes: bytes,
  );
  if (path == null) return null;
  // Some platforms only return the path; make sure the file is written.
  final f = File(path);
  if (!await f.exists() || await f.length() != bytes.length) {
    await f.writeAsBytes(bytes, flush: true);
  }
  return path;
}

/// Renders the pane with annotations and saves it in the study folder
/// as `keys/<id>.png`. The caller adds the returned key image to the
/// study.
Future<RadKeyImage?> radWriteKeyImage(
  RadiologyController ctl,
  RadStudy study,
  RadPane pane, {
  required List<RadAnnotation> annotations,
  required double? mmPerPx,
  RadRoiCache? roi,
}) async {
  final view = await radRenderPaneView(pane, annotations: annotations, mmPerPx: mmPerPx, roi: roi);
  if (view == null) return null;
  final png = await radEncodePng(view);
  view.dispose();
  if (png == null) return null;
  final id = radId('key_');
  final rel = 'keys/$id.png';
  final f = await ctl.fileOf(study, rel);
  await f.parent.create(recursive: true);
  await f.writeAsBytes(png, flush: true);
  return RadKeyImage(id: id, imageId: pane.imageId, pngPath: rel, createdAt: DateTime.now());
}

/// A de-identified copy of a DICOM file (patient name, ID, birth date,
/// institution and staff removed). Null for big-endian files.
Future<Uint8List?> radAnonymisedDicom(File f) {
  final path = f.path;
  return Isolate.run(() => DicomFile.parse(File(path).readAsBytesSync()).anonymised());
}

/// Header values for the Image info tab, read off the UI thread. Missing
/// values are left out.
Future<List<(String, String)>> radDicomHeader(File f) {
  final path = f.path;
  return Isolate.run(() {
    final d = DicomFile.parse(File(path).readAsBytesSync());
    final out = <(String, String)>[];
    void add(String label, String? v) {
      if (v != null && v.trim().isNotEmpty) out.add((label, v.trim()));
    }

    String? nums(int tag, {String unit = ''}) {
      final n = d.numbers(tag);
      if (n == null) return null;
      return '${n.map((v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3)).join(' \\ ')}$unit';
    }

    add('Manufacturer', d.string(DicomTag.manufacturer));
    add('Model', d.string(DicomTag.modelName));
    add('Station', d.string(DicomTag.stationName));
    add('Modality', d.string(DicomTag.modality));
    add('Study', d.string(DicomTag.studyDescription));
    add('Series', d.string(DicomTag.seriesDescription));
    add('Series number', nums(DicomTag.seriesNumber));
    add('Instance', nums(DicomTag.instanceNumber));
    final acquired = d.date(DicomTag.acquisitionDate);
    if (acquired != null) add('Acquired', DateFormat('d MMM yyyy').format(acquired));
    add('Body part', d.string(DicomTag.bodyPart));
    add('Transfer syntax', DicomSyntax.name(d.transferSyntax));
    add('Photometric', d.photometric);
    add('Size', '${d.columns} × ${d.rows}');
    add('Frames', d.frames > 1 ? '${d.frames}' : null);
    add('Bits stored', '${d.bitsStored} of ${d.bitsAllocated}');
    add('Pixel spacing', nums(DicomTag.pixelSpacing, unit: ' mm'));
    add('Imager pixel spacing', nums(DicomTag.imagerPixelSpacing, unit: ' mm'));
    add('Slice thickness', nums(DicomTag.sliceThickness, unit: ' mm'));
    add('Window centre', nums(DicomTag.windowCenter));
    add('Window width', nums(DicomTag.windowWidth));
    add('Rescale', d.has(DicomTag.rescaleSlope) ? '× ${d.slope} + ${d.intercept}' : null);
    add('Tube voltage', nums(DicomTag.kvp, unit: ' kVp'));
    add('Tube current', nums(DicomTag.tubeCurrent, unit: ' mA'));
    add('Exposure time', nums(DicomTag.exposureTime, unit: ' ms'));
    add('Exposure', nums(DicomTag.exposure, unit: ' mAs'));
    add('Dose-area product', nums(DicomTag.dap));
    add('Identity removed', d.string(DicomTag.identityRemoved));
    return out;
  });
}
