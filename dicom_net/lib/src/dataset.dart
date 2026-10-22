import 'dart:convert';
import 'dart:typed_data';

import 'uid.dart';

/// The attributes this package reads, writes and searches on.
enum DicomAttr {
  specificCharacterSet(0x00080005, 'CS', 'SpecificCharacterSet'),
  sopClassUid(0x00080016, 'UI', 'SOPClassUID'),
  sopInstanceUid(0x00080018, 'UI', 'SOPInstanceUID'),
  studyDate(0x00080020, 'DA', 'StudyDate'),
  studyTime(0x00080030, 'TM', 'StudyTime'),
  accessionNumber(0x00080050, 'SH', 'AccessionNumber'),
  modality(0x00080060, 'CS', 'Modality'),
  modalitiesInStudy(0x00080061, 'CS', 'ModalitiesInStudy'),
  manufacturer(0x00080070, 'LO', 'Manufacturer'),
  institutionName(0x00080080, 'LO', 'InstitutionName'),
  referringPhysicianName(0x00080090, 'PN', 'ReferringPhysicianName'),
  retrieveUrl(0x00081190, 'UR', 'RetrieveURL'),
  studyDescription(0x00081030, 'LO', 'StudyDescription'),
  seriesDescription(0x0008103E, 'LO', 'SeriesDescription'),
  patientName(0x00100010, 'PN', 'PatientName'),
  patientId(0x00100020, 'LO', 'PatientID'),
  patientBirthDate(0x00100030, 'DA', 'PatientBirthDate'),
  patientSex(0x00100040, 'CS', 'PatientSex'),
  bodyPartExamined(0x00180015, 'CS', 'BodyPartExamined'),
  sliceThickness(0x00180050, 'DS', 'SliceThickness'),
  studyInstanceUid(0x0020000D, 'UI', 'StudyInstanceUID'),
  seriesInstanceUid(0x0020000E, 'UI', 'SeriesInstanceUID'),
  studyId(0x00200010, 'SH', 'StudyID'),
  seriesNumber(0x00200011, 'IS', 'SeriesNumber'),
  instanceNumber(0x00200013, 'IS', 'InstanceNumber'),
  imagePosition(0x00200032, 'DS', 'ImagePositionPatient'),
  imageOrientation(0x00200037, 'DS', 'ImageOrientationPatient'),
  numberOfStudyRelatedSeries(0x00201206, 'IS', 'NumberOfStudyRelatedSeries'),
  numberOfStudyRelatedInstances(
    0x00201208,
    'IS',
    'NumberOfStudyRelatedInstances',
  ),
  numberOfSeriesRelatedInstances(
    0x00201209,
    'IS',
    'NumberOfSeriesRelatedInstances',
  ),
  samplesPerPixel(0x00280002, 'US', 'SamplesPerPixel'),
  photometric(0x00280004, 'CS', 'PhotometricInterpretation'),
  numberOfFrames(0x00280008, 'IS', 'NumberOfFrames'),
  rows(0x00280010, 'US', 'Rows'),
  columns(0x00280011, 'US', 'Columns'),
  pixelSpacing(0x00280030, 'DS', 'PixelSpacing'),
  bitsAllocated(0x00280100, 'US', 'BitsAllocated'),
  bitsStored(0x00280101, 'US', 'BitsStored'),
  highBit(0x00280102, 'US', 'HighBit'),
  pixelRepresentation(0x00280103, 'US', 'PixelRepresentation'),
  windowCenter(0x00281050, 'DS', 'WindowCenter'),
  windowWidth(0x00281051, 'DS', 'WindowWidth'),
  rescaleIntercept(0x00281052, 'DS', 'RescaleIntercept'),
  rescaleSlope(0x00281053, 'DS', 'RescaleSlope'),
  pixelData(0x7FE00010, 'OW', 'PixelData');

  const DicomAttr(this.tag, this.vr, this.keyword);

  final int tag;
  final String vr;
  final String keyword;

  /// "0020000D".
  String get hex => tag.toRadixString(16).toUpperCase().padLeft(8, '0');

  static final Map<int, DicomAttr> byTag = {for (final a in values) a.tag: a};

  /// By keyword ("PatientName") or hex tag ("00100010").
  static DicomAttr? find(String key) {
    for (final a in values) {
      if (a.keyword.toLowerCase() == key.toLowerCase() ||
          a.hex == key.toUpperCase()) {
        return a;
      }
    }
    return null;
  }
}

/// Long-length VRs in explicit VR encoding.
const _longVr = {
  'OB', 'OD', 'OF', 'OL', 'OV', 'OW', 'SQ', 'UC', 'UN', 'UR', 'UT', 'SV', 'UV', //
};

const _undefined = 0xFFFFFFFF;
const _item = 0xFFFEE000;
const _itemEnd = 0xFFFEE00D;
const _seqEnd = 0xFFFEE0DD;

class DicomFormatException implements Exception {
  DicomFormatException(this.message);
  final String message;
  @override
  String toString() => 'DicomFormatException: $message';
}

/// One DICOM Part 10 file: its header and the top-level attributes this
/// package knows (sequences and pixel data are skipped, not decoded).
class DicomInstance {
  DicomInstance._({
    required this.bytes,
    required this.transferSyntax,
    required this.sopClassUid,
    required this.sopInstanceUid,
    required this.datasetOffset,
    required Map<int, Uint8List> values,
    required this.hasPixels,
  }) : _values = values;

  /// The whole file.
  final Uint8List bytes;
  final String transferSyntax;
  final String sopClassUid;
  final String sopInstanceUid;

  /// Where the dataset (after the file meta header) starts in [bytes].
  final int datasetOffset;
  final bool hasPixels;
  final Map<int, Uint8List> _values;

  /// The dataset without the file meta header, as sent over DIMSE.
  Uint8List get dataset => Uint8List.sublistView(bytes, datasetOffset);

  bool get isExplicit => transferSyntax != DicomUid.implicitLittle;

  String? string(DicomAttr a) {
    final v = _values[a.tag];
    if (v == null) return null;
    final s = utf8
        .decode(v, allowMalformed: true)
        .replaceAll('\u0000', '')
        .trim();
    return s.isEmpty ? null : s;
  }

  int? integer(DicomAttr a) {
    final v = _values[a.tag];
    if (v == null || v.isEmpty) return null;
    if (a.vr == 'US' && v.length >= 2) {
      return ByteData.sublistView(v).getUint16(0, Endian.little);
    }
    return int.tryParse(string(a)?.split('\\').first.trim() ?? '');
  }

  /// "Doe^Jane" as "Doe Jane".
  String personName(DicomAttr a) =>
      (string(a) ?? '').split('=').first.replaceAll('^', ' ').trim();

  static bool looksLikeDicom(Uint8List b) =>
      b.length > 132 &&
      b[128] == 0x44 &&
      b[129] == 0x49 &&
      b[130] == 0x43 &&
      b[131] == 0x4D;

  /// Reads a Part 10 file ("DICM" after a 128-byte preamble).
  static DicomInstance parse(Uint8List bytes) {
    if (!looksLikeDicom(bytes)) {
      throw DicomFormatException('Not a DICOM Part 10 file');
    }
    final r = _Reader(bytes, 132, explicit: true);
    final meta = <int, Uint8List>{};
    while (r.pos + 8 <= bytes.length && r.peekGroup() == 0x0002) {
      final e = r.next();
      if (e.value != null) meta[e.tag] = e.value!;
    }
    String str(int tag) => meta[tag] == null
        ? ''
        : latin1.decode(meta[tag]!).replaceAll('\u0000', '').trim();
    final ts = str(0x00020010);
    if (ts.isEmpty) throw DicomFormatException('No transfer syntax');
    final offset = r.pos;
    final values = <int, Uint8List>{};
    var hasPixels = false;
    if (ts == '1.2.840.10008.1.2.2' || ts == '1.2.840.10008.1.2.1.99') {
      // Big endian and deflate aren't read; the file is still stored and
      // served as it is.
    } else {
      final body = _Reader(bytes, offset, explicit: ts != DicomUid.implicitLittle);
      try {
        while (body.pos + 8 <= bytes.length) {
          final e = body.next();
          if (e.tag == DicomAttr.pixelData.tag) {
            hasPixels = true;
            break;
          }
          if (e.value != null && DicomAttr.byTag.containsKey(e.tag)) {
            values[e.tag] = e.value!;
          }
        }
      } on RangeError {
        // Truncated after the attributes we need.
      }
    }
    String fromBody(DicomAttr a) => values[a.tag] == null
        ? ''
        : latin1.decode(values[a.tag]!).replaceAll('\u0000', '').trim();
    return DicomInstance._(
      bytes: bytes,
      transferSyntax: ts,
      sopClassUid: str(0x00020002).isNotEmpty
          ? str(0x00020002)
          : fromBody(DicomAttr.sopClassUid),
      sopInstanceUid: str(0x00020003).isNotEmpty
          ? str(0x00020003)
          : fromBody(DicomAttr.sopInstanceUid),
      datasetOffset: offset,
      values: values,
      hasPixels: hasPixels,
    );
  }
}

class _Element {
  _Element(this.tag, this.vr, this.value);
  final int tag;
  final String vr;

  /// Null for sequences and undefined-length values (skipped).
  final Uint8List? value;
}

class _Reader {
  _Reader(this.b, this.pos, {required this.explicit})
    : d = ByteData.sublistView(b);

  final Uint8List b;
  final ByteData d;
  int pos;
  final bool explicit;

  int peekGroup() => d.getUint16(pos, Endian.little);

  int _tag() {
    final g = d.getUint16(pos, Endian.little);
    final e = d.getUint16(pos + 2, Endian.little);
    pos += 4;
    return (g << 16) | e;
  }

  _Element next() {
    final tag = _tag();
    if (tag == _item || tag == _itemEnd || tag == _seqEnd) {
      pos += 4;
      return _Element(tag, '', null);
    }
    var vr = '';
    int len;
    final isMeta = (tag >> 16) == 0x0002;
    if (explicit || isMeta) {
      vr = String.fromCharCodes(b, pos, pos + 2);
      pos += 2;
      if (_longVr.contains(vr)) {
        pos += 2;
        len = d.getUint32(pos, Endian.little);
        pos += 4;
      } else {
        len = d.getUint16(pos, Endian.little);
        pos += 2;
      }
    } else {
      vr = DicomAttr.byTag[tag]?.vr ?? 'UN';
      len = d.getUint32(pos, Endian.little);
      pos += 4;
    }
    if (len == _undefined) {
      _skipUndefined();
      return _Element(tag, vr, null);
    }
    if (vr == 'SQ') {
      pos += len;
      return _Element(tag, vr, null);
    }
    final v = Uint8List.sublistView(b, pos, pos + len);
    pos += len;
    return _Element(tag, vr, v);
  }

  /// Skips a sequence or encapsulated pixel data of undefined length.
  void _skipUndefined() {
    while (true) {
      final tag = _tag();
      final len = d.getUint32(pos, Endian.little);
      pos += 4;
      if (tag == _seqEnd) return;
      if (tag == _item) {
        if (len != _undefined) {
          pos += len;
        } else {
          // Item of undefined length: elements until the item end.
          while (true) {
            if (d.getUint16(pos, Endian.little) == 0xFFFE &&
                d.getUint16(pos + 2, Endian.little) == 0xE00D) {
              pos += 8;
              break;
            }
            next();
          }
        }
      } else {
        throw DicomFormatException('Bad sequence at $pos');
      }
    }
  }
}

/// Writes datasets in explicit VR little endian, in ascending tag order.
class DicomWriter {
  final _els = <int, (String, Uint8List)>{};

  void string(DicomAttr a, String value) => raw(a.tag, a.vr, _pad(a.vr, value));

  void stringTag(int tag, String vr, String value) =>
      raw(tag, vr, _pad(vr, value));

  void us(DicomAttr a, int v) =>
      raw(a.tag, 'US', Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

  void raw(int tag, String vr, Uint8List value) => _els[tag] = (vr, value);

  static Uint8List _pad(String vr, String s) {
    final b = utf8.encode(s);
    if (b.length.isEven) return Uint8List.fromList(b);
    return Uint8List.fromList([...b, vr == 'UI' ? 0 : 0x20]);
  }

  /// The dataset alone.
  Uint8List dataset() {
    final out = BytesBuilder(copy: false);
    final tags = _els.keys.toList()..sort();
    for (final t in tags) {
      final (vr, v) = _els[t]!;
      _writeElement(out, t, vr, v);
    }
    return out.takeBytes();
  }

  static void _writeElement(BytesBuilder out, int tag, String vr, Uint8List v) {
    final h = ByteData(12);
    h.setUint16(0, tag >> 16, Endian.little);
    h.setUint16(2, tag & 0xFFFF, Endian.little);
    h.setUint8(4, vr.codeUnitAt(0));
    h.setUint8(5, vr.codeUnitAt(1));
    if (_longVr.contains(vr)) {
      h.setUint16(6, 0, Endian.little);
      h.setUint32(8, v.length, Endian.little);
      out.add(h.buffer.asUint8List(0, 12));
    } else {
      h.setUint16(6, v.length, Endian.little);
      out.add(h.buffer.asUint8List(0, 8));
    }
    out.add(v);
  }
}

/// Wraps a [dataset] in a Part 10 file: preamble, "DICM" and the file
/// meta header.
Uint8List buildPart10({
  required String sopClassUid,
  required String sopInstanceUid,
  required String transferSyntax,
  required Uint8List dataset,
  String sourceAe = '',
}) {
  final meta = BytesBuilder(copy: false);
  void el(int tag, String vr, Uint8List v) =>
      DicomWriter._writeElement(meta, tag, vr, v);
  Uint8List ui(String s) => DicomWriter._pad('UI', s);
  el(0x00020001, 'OB', Uint8List.fromList([0, 1]));
  el(0x00020002, 'UI', ui(sopClassUid));
  el(0x00020003, 'UI', ui(sopInstanceUid));
  el(0x00020010, 'UI', ui(transferSyntax));
  el(0x00020012, 'UI', ui(DicomUid.implementationClass));
  el(0x00020013, 'SH', DicomWriter._pad('SH', DicomUid.implementationVersion));
  if (sourceAe.isNotEmpty) el(0x00020016, 'AE', DicomWriter._pad('AE', sourceAe));
  final metaBytes = meta.takeBytes();

  final out = BytesBuilder(copy: false)
    ..add(Uint8List(128))
    ..add(ascii.encode('DICM'));
  final len = ByteData(4)..setUint32(0, metaBytes.length, Endian.little);
  DicomWriter._writeElement(out, 0x00020000, 'UL', len.buffer.asUint8List());
  out
    ..add(metaBytes)
    ..add(dataset);
  return out.takeBytes();
}
