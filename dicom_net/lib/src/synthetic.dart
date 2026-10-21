import 'dart:math';
import 'dart:typed_data';

import 'dataset.dart';
import 'dicom_json.dart';
import 'uid.dart';

/// Made-up test studies (clearly named TEST^…) for exercising a PACS
/// connection: a panoramic, two intraoral images and a small CBCT.
abstract final class SyntheticStudies {
  static final _rand = Random();

  /// Part 10 files for [count] studies, cycling panoramic → intraoral → CBCT.
  static List<Uint8List> generate({int count = 3}) {
    final out = <Uint8List>[];
    final now = DateTime.now();
    for (var i = 0; i < count; i++) {
      final n = _rand.nextInt(9000) + 1000;
      final patient = (
        name: 'TEST^PATIENT ${String.fromCharCode(65 + i % 26)}$n',
        id: 'SIM-$n',
        dob: DateTime(1970 + _rand.nextInt(40), 1 + _rand.nextInt(12), 1 + _rand.nextInt(28)),
        sex: _rand.nextBool() ? 'F' : 'M',
      );
      final date = now.subtract(Duration(days: i, hours: _rand.nextInt(8)));
      switch (i % 3) {
        case 0:
          out.addAll(_panoramic(patient, date, n));
        case 1:
          out.addAll(_intraoral(patient, date, n));
        default:
          out.addAll(_cbct(patient, date, n));
      }
    }
    return out;
  }

  static DicomWriter _base(
    ({String name, String id, DateTime dob, String sex}) p,
    DateTime date, {
    required String studyUid,
    required String seriesUid,
    required String sopClass,
    required String sopUid,
    required String modality,
    required String studyDescription,
    required String seriesDescription,
    required int accession,
    required int instance,
  }) {
    final w = DicomWriter()
      ..string(DicomAttr.specificCharacterSet, 'ISO_IR 192')
      ..string(DicomAttr.sopClassUid, sopClass)
      ..string(DicomAttr.sopInstanceUid, sopUid)
      ..string(DicomAttr.studyDate, dicomDate(date))
      ..string(DicomAttr.studyTime, dicomTime(date))
      ..string(DicomAttr.accessionNumber, 'ACC$accession')
      ..string(DicomAttr.modality, modality)
      ..string(DicomAttr.manufacturer, 'CruDoc PACS Simulator')
      ..string(DicomAttr.institutionName, 'PACS Simulator')
      ..string(DicomAttr.referringPhysicianName, 'TEST^REFERRER')
      ..string(DicomAttr.studyDescription, studyDescription)
      ..string(DicomAttr.seriesDescription, seriesDescription)
      ..string(DicomAttr.patientName, p.name)
      ..string(DicomAttr.patientId, p.id)
      ..string(DicomAttr.patientBirthDate, dicomDate(p.dob))
      ..string(DicomAttr.patientSex, p.sex)
      ..string(DicomAttr.studyInstanceUid, studyUid)
      ..string(DicomAttr.seriesInstanceUid, seriesUid)
      ..string(DicomAttr.studyId, '$accession')
      ..string(DicomAttr.seriesNumber, '1')
      ..string(DicomAttr.instanceNumber, '$instance')
      ..us(DicomAttr.samplesPerPixel, 1)
      ..string(DicomAttr.photometric, 'MONOCHROME2')
      ..us(DicomAttr.bitsAllocated, 16)
      ..us(DicomAttr.bitsStored, 12)
      ..us(DicomAttr.highBit, 11)
      ..us(DicomAttr.pixelRepresentation, 0);
    return w;
  }

  static Uint8List _finish(DicomWriter w, String sopClass, String sopUid, int rows, int cols, Uint16List px) {
    w
      ..us(DicomAttr.rows, rows)
      ..us(DicomAttr.columns, cols)
      ..raw(DicomAttr.pixelData.tag, 'OW', px.buffer.asUint8List());
    return buildPart10(
      sopClassUid: sopClass,
      sopInstanceUid: sopUid,
      transferSyntax: DicomUid.explicitLittle,
      dataset: w.dataset(),
    );
  }

  static int _clamp(double v) => v.clamp(0, 4095).round();

  static List<Uint8List> _panoramic(
    ({String name, String id, DateTime dob, String sex}) p,
    DateTime date,
    int n,
  ) {
    const cols = 1024, rows = 512;
    final px = Uint16List(rows * cols);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final u = (x - cols / 2) / (cols / 2);
        // Upper and lower arches as parabolas, teeth as bright bands.
        final upper = rows * 0.42 - 70 * (1 - u * u);
        final lower = rows * 0.58 + 70 * (1 - u * u);
        var v = 600 + 500 * (1 - u * u) * 0.5;
        final tooth = (x ~/ 30).isEven || (x % 30) > 4;
        if (y > upper - 90 && y < upper && tooth && u.abs() < 0.85) v = 2600 + 400 * (1 - (upper - y) / 90);
        if (y > lower && y < lower + 90 && tooth && u.abs() < 0.85) v = 2600 + 400 * (1 - (y - lower) / 90);
        if ((y - upper).abs() < 4 || (y - lower).abs() < 4) v = 3400;
        px[y * cols + x] = _clamp(v + _rand.nextInt(120));
      }
    }
    final study = newDicomUid(), series = newDicomUid(), sop = newDicomUid();
    final w = _base(
      p,
      date,
      studyUid: study,
      seriesUid: series,
      sopClass: DicomUid.dxPresentation,
      sopUid: sop,
      modality: 'PX',
      studyDescription: 'OPG Panoramic',
      seriesDescription: 'Panoramic',
      accession: n,
      instance: 1,
    )..string(DicomAttr.pixelSpacing, '0.1\\0.1')
     ..string(DicomAttr.bodyPartExamined, 'JAW')
     ..string(DicomAttr.windowCenter, '2048')
     ..string(DicomAttr.windowWidth, '4096');
    return [_finish(w, DicomUid.dxPresentation, sop, rows, cols, px)];
  }

  static List<Uint8List> _intraoral(
    ({String name, String id, DateTime dob, String sex}) p,
    DateTime date,
    int n,
  ) {
    const cols = 400, rows = 300;
    final study = newDicomUid(), series = newDicomUid();
    final out = <Uint8List>[];
    for (var k = 0; k < 2; k++) {
      final px = Uint16List(rows * cols);
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < cols; x++) {
          var v = 500.0;
          for (final cx in [130 + k * 20, 270 - k * 20]) {
            final dx = (x - cx).abs();
            // Crown on top, root tapering down.
            final width = y < 120 ? 60.0 : 60.0 * (1 - (y - 120) / 220);
            if (dx < width && y > 30 && y < 280) v = 2400 + (y < 120 ? 900 : 0) - dx * 6;
            if (dx < width * 0.25 && y > 90 && y < 260) v = 1300;
          }
          px[y * cols + x] = _clamp(v + _rand.nextInt(100));
        }
      }
      final sop = newDicomUid();
      final w = _base(
        p,
        date,
        studyUid: study,
        seriesUid: series,
        sopClass: DicomUid.ioPresentation,
        sopUid: sop,
        modality: 'IO',
        studyDescription: 'IOPA Periapical',
        seriesDescription: 'Periapical',
        accession: n,
        instance: k + 1,
      )..string(DicomAttr.pixelSpacing, '0.02\\0.02')
       ..string(DicomAttr.windowCenter, '2048')
       ..string(DicomAttr.windowWidth, '4096');
      out.add(_finish(w, DicomUid.ioPresentation, sop, rows, cols, px));
    }
    return out;
  }

  static List<Uint8List> _cbct(
    ({String name, String id, DateTime dob, String sex}) p,
    DateTime date,
    int n,
  ) {
    const size = 96, slices = 40;
    const spacing = 0.4;
    final study = newDicomUid(), series = newDicomUid();
    final out = <Uint8List>[];
    for (var z = 0; z < slices; z++) {
      final px = Uint16List(size * size);
      final zz = (z - slices / 2) / (slices / 2);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final dx = (x - size / 2) / (size * 0.42);
          final dy = (y - size * 0.6) / (size * 0.42);
          final r = sqrt(dx * dx + dy * dy + zz * zz * 0.6);
          var hu = -1000.0; // air
          if (r < 1.0) hu = 40; // soft tissue
          // A U-shaped bony arch.
          final arch = sqrt(dx * dx + dy * dy);
          if (dy < 0.2 && (arch - 0.6).abs() < 0.12 && zz.abs() < 0.6) hu = 1200;
          px[y * size + x] = (hu + 1024 + _rand.nextInt(40)).clamp(0, 4095).round();
        }
      }
      final sop = newDicomUid();
      final w = _base(
        p,
        date,
        studyUid: study,
        seriesUid: series,
        sopClass: DicomUid.ctImage,
        sopUid: sop,
        modality: 'CT',
        studyDescription: 'CBCT Maxilla Mandible',
        seriesDescription: 'CBCT Axial',
        accession: n,
        instance: z + 1,
      )..string(DicomAttr.pixelSpacing, '$spacing\\$spacing')
       ..string(DicomAttr.sliceThickness, '$spacing')
       ..string(DicomAttr.imagePosition, '0\\0\\${(z * spacing).toStringAsFixed(2)}')
       ..string(DicomAttr.imageOrientation, '1\\0\\0\\0\\1\\0')
       ..string(DicomAttr.rescaleIntercept, '-1024')
       ..string(DicomAttr.rescaleSlope, '1')
       ..string(DicomAttr.windowCenter, '400')
       ..string(DicomAttr.windowWidth, '2000')
       ..string(DicomAttr.bodyPartExamined, 'JAW');
      out.add(_finish(w, DicomUid.ctImage, sop, size, size, px));
    }
    return out;
  }
}
