import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// DICOM tags the radiology module reads, as (group << 16) | element.
abstract final class DicomTag {
  static const transferSyntax = 0x00020010;
  static const sopInstanceUid = 0x00080018;
  static const studyDate = 0x00080020;
  static const seriesDate = 0x00080021;
  static const acquisitionDate = 0x00080022;
  static const studyTime = 0x00080030;
  static const accession = 0x00080050;
  static const modality = 0x00080060;
  static const manufacturer = 0x00080070;
  static const institution = 0x00080080;
  static const institutionAddress = 0x00080081;
  static const referringPhysician = 0x00080090;
  static const stationName = 0x00081010;
  static const studyDescription = 0x00081030;
  static const seriesDescription = 0x0008103E;
  static const performingPhysician = 0x00081050;
  static const operatorsName = 0x00081070;
  static const modelName = 0x00081090;
  static const patientName = 0x00100010;
  static const patientId = 0x00100020;
  static const birthDate = 0x00100030;
  static const sex = 0x00100040;
  static const otherPatientIds = 0x00101000;
  static const patientAddress = 0x00101040;
  static const patientPhone = 0x00102154;
  static const identityRemoved = 0x00120062;
  static const bodyPart = 0x00180015;
  static const sliceThickness = 0x00180050;
  static const kvp = 0x00180060;
  static const spacingBetweenSlices = 0x00180088;
  static const deviceSerial = 0x00181000;
  static const exposureTime = 0x00181150;
  static const tubeCurrent = 0x00181151;
  static const exposure = 0x00181152;
  static const dap = 0x0018115E;
  static const imagerPixelSpacing = 0x00181164;
  static const studyInstanceUid = 0x0020000D;
  static const seriesInstanceUid = 0x0020000E;
  static const studyId = 0x00200010;
  static const seriesNumber = 0x00200011;
  static const instanceNumber = 0x00200013;
  static const imagePosition = 0x00200032;
  static const imageOrientation = 0x00200037;
  static const sliceLocation = 0x00201041;
  static const samplesPerPixel = 0x00280002;
  static const photometric = 0x00280004;
  static const planarConfiguration = 0x00280006;
  static const numberOfFrames = 0x00280008;
  static const rows = 0x00280010;
  static const columns = 0x00280011;
  static const pixelSpacing = 0x00280030;
  static const bitsAllocated = 0x00280100;
  static const bitsStored = 0x00280101;
  static const highBit = 0x00280102;
  static const pixelRepresentation = 0x00280103;
  static const windowCenter = 0x00281050;
  static const windowWidth = 0x00281051;
  static const rescaleIntercept = 0x00281052;
  static const rescaleSlope = 0x00281053;
  static const pixelData = 0x7FE00010;

  static const item = 0xFFFEE000;
  static const itemDelimiter = 0xFFFEE00D;
  static const sequenceDelimiter = 0xFFFEE0DD;
}

/// Transfer syntaxes.
abstract final class DicomSyntax {
  static const implicitLittle = '1.2.840.10008.1.2';
  static const explicitLittle = '1.2.840.10008.1.2.1';
  static const deflated = '1.2.840.10008.1.2.1.99';
  static const explicitBig = '1.2.840.10008.1.2.2';

  /// Uncompressed pixel data CruDoc can show.
  static bool isUncompressed(String ts) =>
      ts.isEmpty ||
      ts == implicitLittle ||
      ts == explicitLittle ||
      ts == deflated ||
      ts == explicitBig;

  /// "JPEG 2000", "JPEG-LS"… for the "not supported yet" message.
  static String name(String ts) {
    if (isUncompressed(ts)) return 'Uncompressed';
    if (ts == '1.2.840.10008.1.2.5') return 'RLE';
    if (ts.startsWith('1.2.840.10008.1.2.4.9')) return 'JPEG 2000';
    if (ts == '1.2.840.10008.1.2.4.80' || ts == '1.2.840.10008.1.2.4.81') return 'JPEG-LS';
    if (ts == '1.2.840.10008.1.2.4.57' || ts == '1.2.840.10008.1.2.4.70') {
      return 'JPEG Lossless';
    }
    if (ts.startsWith('1.2.840.10008.1.2.4.10')) return 'MPEG video';
    if (ts.startsWith('1.2.840.10008.1.2.4.20')) return 'HEVC video';
    if (ts.startsWith('1.2.840.10008.1.2.4.')) return 'JPEG';
    return 'Compressed';
  }
}

/// The DICOM file cannot be read.
class DicomFormatException implements Exception {
  DicomFormatException(this.message);
  final String message;
  @override
  String toString() => 'DicomFormatException: $message';
}

/// Pixel data is compressed in a format CruDoc can't decode yet.
class DicomUnsupportedException implements Exception {
  DicomUnsupportedException(this.syntaxName);
  final String syntaxName;
  @override
  String toString() => '$syntaxName DICOM images are not supported yet';
}

class _Element {
  _Element(this.tag, this.vr, this.start, this.valueOffset, this.length, this.end);

  final int tag;
  final String vr;

  /// Where the element's header starts and the whole element ends.
  final int start;
  final int end;
  final int valueOffset;

  /// -1 for undefined length.
  final int length;
}

const _undefined = 0xFFFFFFFF;
const _longVrs = {'OB', 'OD', 'OF', 'OL', 'OV', 'OW', 'SQ', 'SV', 'UC', 'UN', 'UR', 'UT', 'UV'};

/// Tags stored as binary in implicit VR files (everything else read is text).
const _implicitVr = <int, String>{
  DicomTag.samplesPerPixel: 'US',
  DicomTag.planarConfiguration: 'US',
  DicomTag.rows: 'US',
  DicomTag.columns: 'US',
  DicomTag.bitsAllocated: 'US',
  DicomTag.bitsStored: 'US',
  DicomTag.highBit: 'US',
  DicomTag.pixelRepresentation: 'US',
  DicomTag.pixelData: 'OW',
};

/// A parsed DICOM Part 10 file (or a bare dataset). Reads the header and
/// uncompressed pixel data; compressed pixel data is detected and
/// reported, not decoded.
class DicomFile {
  DicomFile._(this.bytes, this.transferSyntax, this.littleEndian, this.explicitVr,
      this._top, this._nested, this._metaEnd, this.hasPreamble);

  /// Whether [head] (the first 132+ bytes) looks like DICOM.
  static bool looksLikeDicom(Uint8List head) {
    if (head.length >= 132 &&
        head[128] == 0x44 &&
        head[129] == 0x49 &&
        head[130] == 0x43 &&
        head[131] == 0x4D) {
      return true;
    }
    // A bare dataset: starts with group 0x0008 (little endian).
    return head.length >= 8 && head[0] == 0x08 && head[1] == 0x00 && head[3] == 0x00;
  }

  /// Reads the first bytes of a file to check [looksLikeDicom].
  static Future<bool> isDicomFile(File f) async {
    try {
      final raf = await f.open();
      try {
        final head = await raf.read(132);
        return looksLikeDicom(head);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<DicomFile> load(File f) async => parse(await f.readAsBytes());

  static DicomFile parse(Uint8List input) {
    var bytes = input;
    var pos = 0;
    var hasPreamble = false;
    final top = <int, _Element>{};
    final nested = <int, _Element>{};
    var ts = '';

    if (bytes.length >= 132 &&
        bytes[128] == 0x44 &&
        bytes[129] == 0x49 &&
        bytes[130] == 0x43 &&
        bytes[131] == 0x4D) {
      hasPreamble = true;
      pos = 132;
      // File meta information: always explicit VR little endian.
      final meta = _Walker(bytes, true, true, top, nested);
      while (pos + 8 <= bytes.length) {
        final group = bytes[pos] | (bytes[pos + 1] << 8);
        if (group != 0x0002) break;
        pos = meta.element(pos, recordTop: true);
      }
      final tsEl = top[DicomTag.transferSyntax];
      if (tsEl != null) {
        ts = _text(bytes, tsEl.valueOffset, tsEl.length);
      }
    }
    final metaEnd = pos;

    var little = ts != DicomSyntax.explicitBig;
    var explicit = ts.isNotEmpty && ts != DicomSyntax.implicitLittle;
    if (ts.isEmpty) {
      // No meta: guess explicit if two VR letters follow the first tag.
      if (pos + 6 <= bytes.length) {
        final a = bytes[pos + 4], b = bytes[pos + 5];
        explicit = a >= 0x41 && a <= 0x5A && b >= 0x41 && b <= 0x5A;
      }
    }

    if (ts == DicomSyntax.deflated) {
      final inflated = ZLibCodec(raw: true).decode(bytes.sublist(pos));
      bytes = Uint8List.fromList([...bytes.sublist(0, pos), ...inflated]);
    }

    final walker = _Walker(bytes, little, explicit, top, nested);
    try {
      while (pos + 8 <= bytes.length) {
        pos = walker.element(pos, recordTop: true);
      }
    } on RangeError {
      // Truncated file: keep what was read.
    } on DicomFormatException {
      if (top.isEmpty) rethrow;
    }
    if (!top.containsKey(DicomTag.rows) && !top.containsKey(DicomTag.patientName) &&
        !top.containsKey(DicomTag.sopInstanceUid)) {
      throw DicomFormatException('Not a DICOM dataset');
    }
    return DicomFile._(bytes, ts, little, explicit, top, nested, metaEnd, hasPreamble);
  }

  final Uint8List bytes;
  final String transferSyntax;
  final bool littleEndian;
  final bool explicitVr;
  final bool hasPreamble;
  final Map<int, _Element> _top;
  final Map<int, _Element> _nested;
  final int _metaEnd;

  _Element? _find(int tag) => _top[tag] ?? _nested[tag];

  bool has(int tag) => _find(tag) != null;

  // ───────────────────────────── Values ─────────────────────────────

  static String _text(Uint8List b, int offset, int length) {
    if (length <= 0) return '';
    final end = (offset + length).clamp(0, b.length);
    var s = latin1.decode(b.sublist(offset, end), allowInvalid: true);
    s = s.replaceAll('\u0000', '');
    return s.trim();
  }

  String? string(int tag) {
    final e = _find(tag);
    if (e == null || e.length < 0) return null;
    final s = _text(bytes, e.valueOffset, e.length);
    return s.isEmpty ? null : s;
  }

  /// A person name with the DICOM carets turned into spaces
  /// ("DOE^JOHN" → "John Doe").
  String? personName(int tag) {
    final raw = string(tag);
    if (raw == null) return null;
    final parts = raw.split('=').first.split('^').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    String cap(String s) => s.length <= 1 ? s.toUpperCase() : s[0].toUpperCase() + s.substring(1).toLowerCase();
    final family = cap(parts.first);
    final given = parts.skip(1).map(cap).join(' ');
    return given.isEmpty ? family : '$given $family';
  }

  String _vrOf(_Element e) => e.vr.isNotEmpty ? e.vr : (_implicitVr[e.tag] ?? 'XX');

  List<double>? numbers(int tag) {
    final e = _find(tag);
    if (e == null || e.length <= 0) return null;
    final vr = _vrOf(e);
    final bd = ByteData.sublistView(bytes, e.valueOffset, e.valueOffset + e.length);
    final endian = littleEndian ? Endian.little : Endian.big;
    switch (vr) {
      case 'US':
        return [for (var i = 0; i + 2 <= e.length; i += 2) bd.getUint16(i, endian).toDouble()];
      case 'SS':
        return [for (var i = 0; i + 2 <= e.length; i += 2) bd.getInt16(i, endian).toDouble()];
      case 'UL':
        return [for (var i = 0; i + 4 <= e.length; i += 4) bd.getUint32(i, endian).toDouble()];
      case 'SL':
        return [for (var i = 0; i + 4 <= e.length; i += 4) bd.getInt32(i, endian).toDouble()];
      case 'FL':
        return [for (var i = 0; i + 4 <= e.length; i += 4) bd.getFloat32(i, endian)];
      case 'FD':
        return [for (var i = 0; i + 8 <= e.length; i += 8) bd.getFloat64(i, endian)];
    }
    final s = _text(bytes, e.valueOffset, e.length);
    final out = <double>[];
    for (final part in s.split('\\')) {
      final v = double.tryParse(part.trim());
      if (v != null) out.add(v);
    }
    return out.isEmpty ? null : out;
  }

  double? number(int tag) => numbers(tag)?.first;
  int? integer(int tag) => number(tag)?.round();

  static DateTime? _dicomDate(String? d, [String? t]) {
    if (d == null || d.length < 8) return null;
    final y = int.tryParse(d.substring(0, 4));
    final m = int.tryParse(d.substring(4, 6));
    final day = int.tryParse(d.substring(6, 8));
    if (y == null || m == null || day == null) return null;
    var hh = 0, mm = 0;
    if (t != null && t.length >= 4) {
      hh = int.tryParse(t.substring(0, 2)) ?? 0;
      mm = int.tryParse(t.substring(2, 4)) ?? 0;
    }
    return DateTime(y, m, day, hh, mm);
  }

  DateTime? date(int dateTag, [int? timeTag]) =>
      _dicomDate(string(dateTag), timeTag == null ? null : string(timeTag));

  // ─────────────────────────── Image header ───────────────────────────

  int get rows => integer(DicomTag.rows) ?? 0;
  int get columns => integer(DicomTag.columns) ?? 0;
  int get frames => integer(DicomTag.numberOfFrames) ?? (hasPixels ? 1 : 0);
  int get bitsAllocated => integer(DicomTag.bitsAllocated) ?? 16;
  int get bitsStored => integer(DicomTag.bitsStored) ?? bitsAllocated;
  bool get signed => (integer(DicomTag.pixelRepresentation) ?? 0) == 1;
  int get samplesPerPixel => integer(DicomTag.samplesPerPixel) ?? 1;
  String get photometric => string(DicomTag.photometric) ?? 'MONOCHROME2';
  bool get monochrome1 => photometric == 'MONOCHROME1';
  bool get isColor => samplesPerPixel >= 3;
  double get slope => number(DicomTag.rescaleSlope) ?? 1;
  double get intercept => number(DicomTag.rescaleIntercept) ?? 0;

  bool get hasPixels => _top.containsKey(DicomTag.pixelData);

  bool get isCompressed {
    final e = _top[DicomTag.pixelData];
    return !DicomSyntax.isUncompressed(transferSyntax) || (e != null && e.length < 0);
  }

  /// Millimetres per pixel (Pixel Spacing, else Imager Pixel Spacing).
  double? get pixelSpacingMm =>
      numbers(DicomTag.pixelSpacing)?.first ?? numbers(DicomTag.imagerPixelSpacing)?.first;

  int get _bytesPerSample => (bitsAllocated + 7) ~/ 8;
  int get frameBytes => rows * columns * samplesPerPixel * _bytesPerSample;

  int _frameOffset(int frame) {
    final e = _top[DicomTag.pixelData];
    if (e == null) throw DicomFormatException('No pixel data');
    if (isCompressed) throw DicomUnsupportedException(DicomSyntax.name(transferSyntax));
    final off = e.valueOffset + frame * frameBytes;
    if (off + frameBytes > bytes.length) throw DicomFormatException('Pixel data is cut short');
    return off;
  }

  /// One frame's stored values as signed integers (masked to Bits Stored
  /// and sign-extended). Grayscale only.
  Int32List storedFrame(int frame) {
    final off = _frameOffset(frame);
    final n = rows * columns;
    final out = Int32List(n);
    final bits = bitsStored;
    final mask = bits >= 32 ? 0xFFFFFFFF : (1 << bits) - 1;
    final signBit = 1 << (bits - 1);
    final sgn = signed;
    switch (bitsAllocated) {
      case 8:
        for (var i = 0; i < n; i++) {
          var v = bytes[off + i] & mask;
          if (sgn && (v & signBit) != 0) v -= (1 << bits);
          out[i] = v;
        }
      case 16:
        final bd = ByteData.sublistView(bytes, off, off + n * 2);
        final endian = littleEndian ? Endian.little : Endian.big;
        for (var i = 0; i < n; i++) {
          var v = bd.getUint16(i * 2, endian) & mask;
          if (sgn && (v & signBit) != 0) v -= (1 << bits);
          out[i] = v;
        }
      case 32:
        final bd = ByteData.sublistView(bytes, off, off + n * 4);
        final endian = littleEndian ? Endian.little : Endian.big;
        for (var i = 0; i < n; i++) {
          out[i] = sgn ? bd.getInt32(i * 4, endian) : bd.getUint32(i * 4, endian);
        }
      default:
        throw DicomUnsupportedException('$bitsAllocated-bit');
    }
    return out;
  }

  /// One frame as modality values (stored × slope + intercept).
  Float32List frameValues(int frame) {
    final stored = storedFrame(frame);
    final s = slope, b = intercept;
    final out = Float32List(stored.length);
    for (var i = 0; i < stored.length; i++) {
      out[i] = stored[i] * s + b;
    }
    return out;
  }

  /// One colour frame as RGBA bytes (RGB or YBR_FULL, 8-bit).
  Uint8List frameRgba(int frame) {
    final off = _frameOffset(frame);
    final n = rows * columns;
    final planar = (integer(DicomTag.planarConfiguration) ?? 0) == 1;
    final ybr = photometric.startsWith('YBR');
    final out = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      int r, g, b;
      if (planar) {
        r = bytes[off + i];
        g = bytes[off + n + i];
        b = bytes[off + 2 * n + i];
      } else {
        r = bytes[off + i * 3];
        g = bytes[off + i * 3 + 1];
        b = bytes[off + i * 3 + 2];
      }
      if (ybr) {
        final y = r.toDouble(), cb = g - 128.0, cr = b - 128.0;
        r = (y + 1.402 * cr).round().clamp(0, 255);
        g = (y - 0.344136 * cb - 0.714136 * cr).round().clamp(0, 255);
        b = (y + 1.772 * cb).round().clamp(0, 255);
      }
      out[i * 4] = r;
      out[i * 4 + 1] = g;
      out[i * 4 + 2] = b;
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  // ─────────────────────────── Anonymised copy ───────────────────────────

  /// Identifying tags cleared on an anonymised export (basic profile).
  static const identifyingTags = <int>{
    DicomTag.patientName,
    DicomTag.patientId,
    DicomTag.birthDate,
    DicomTag.otherPatientIds,
    DicomTag.patientAddress,
    DicomTag.patientPhone,
    DicomTag.institution,
    DicomTag.institutionAddress,
    DicomTag.referringPhysician,
    DicomTag.performingPhysician,
    DicomTag.operatorsName,
    DicomTag.accession,
    DicomTag.studyId,
    DicomTag.stationName,
    DicomTag.deviceSerial,
  };

  /// A copy of the file with identifying tags replaced ([replace], tag to
  /// new text) or removed, private tags dropped and "identity removed"
  /// set. Little-endian files only; returns null for big-endian.
  Uint8List? anonymised({Map<int, String> replace = const {}, bool dropPrivate = true}) {
    if (!littleEndian) return null;
    final values = <int, String>{
      DicomTag.patientName: 'Anonymous',
      DicomTag.patientId: 'ANON',
      DicomTag.birthDate: '',
      DicomTag.identityRemoved: 'YES',
      ...replace,
    };
    final out = BytesBuilder(copy: false);
    if (hasPreamble) out.add(bytes.sublist(0, _metaEnd));

    final datasetTags = _top.keys.where((t) => (t >> 16) != 0x0002).toList()..sort();
    final pending = values.keys.where((t) => !_top.containsKey(t)).toList()..sort();
    var pi = 0;

    void writeNew(int tag, String text) {
      final vr = switch (tag) {
        DicomTag.patientName || DicomTag.referringPhysician ||
        DicomTag.performingPhysician || DicomTag.operatorsName => 'PN',
        DicomTag.birthDate => 'DA',
        DicomTag.identityRemoved => 'CS',
        _ => 'LO',
      };
      var v = latin1.encode(text);
      if (v.length.isOdd) v = Uint8List.fromList([...v, 0x20]);
      final h = ByteData(explicitVr ? 8 : 8);
      h.setUint16(0, tag >> 16, Endian.little);
      h.setUint16(2, tag & 0xFFFF, Endian.little);
      if (explicitVr) {
        h.setUint8(4, vr.codeUnitAt(0));
        h.setUint8(5, vr.codeUnitAt(1));
        h.setUint16(6, v.length, Endian.little);
      } else {
        h.setUint32(4, v.length, Endian.little);
      }
      out
        ..add(h.buffer.asUint8List())
        ..add(v);
    }

    for (final tag in datasetTags) {
      while (pi < pending.length && pending[pi] < tag) {
        writeNew(pending[pi], values[pending[pi]]!);
        pi++;
      }
      final e = _top[tag]!;
      final group = tag >> 16;
      if (dropPrivate && group.isOdd) continue;
      if (values.containsKey(tag)) {
        writeNew(tag, values[tag]!);
      } else if (identifyingTags.contains(tag)) {
        writeNew(tag, '');
      } else {
        out.add(bytes.sublist(e.start, e.end));
      }
    }
    while (pi < pending.length) {
      writeNew(pending[pi], values[pending[pi]]!);
      pi++;
    }
    return out.takeBytes();
  }
}

/// Walks elements, recording top-level ones and the first nested
/// occurrence of each tag.
class _Walker {
  _Walker(this.b, this.little, this.explicit, this.top, this.nested);

  final Uint8List b;
  final bool little;
  final bool explicit;
  final Map<int, _Element> top;
  final Map<int, _Element> nested;

  int _u16(int p) => little ? b[p] | (b[p + 1] << 8) : (b[p] << 8) | b[p + 1];
  int _u32(int p) => little
      ? b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)
      : (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];

  /// Reads the element at [pos]; returns where the next one starts.
  int element(int pos, {bool recordTop = false}) {
    final start = pos;
    final group = _u16(pos);
    final elem = _u16(pos + 2);
    final tag = (group << 16) | elem;
    pos += 4;

    var vr = '';
    int length;
    if (group == 0xFFFE) {
      length = _u32(pos);
      pos += 4;
    } else if (explicit) {
      vr = String.fromCharCodes([b[pos], b[pos + 1]]);
      if (!RegExp(r'^[A-Z]{2}$').hasMatch(vr)) {
        throw DicomFormatException('Bad VR at $start');
      }
      if (_longVrs.contains(vr)) {
        length = _u32(pos + 4);
        pos += 8;
      } else {
        length = _u16(pos + 2);
        pos += 4;
      }
    } else {
      length = _u32(pos);
      pos += 4;
    }
    final valueOffset = pos;

    int end;
    if (length == _undefined) {
      if (tag == DicomTag.pixelData) {
        end = _skipItems(pos, record: false);
      } else {
        // A sequence (or UN) of undefined length.
        end = _skipItems(pos, record: true);
      }
      length = -1;
    } else {
      if (vr == 'SQ' && length > 0) {
        _walkDefinedSequence(pos, pos + length);
      }
      end = pos + length;
    }
    if (end > b.length) end = b.length;
    final e = _Element(tag, vr, start, valueOffset, length, end);
    if (recordTop) {
      top.putIfAbsent(tag, () => e);
    } else {
      nested.putIfAbsent(tag, () => e);
    }
    return end;
  }

  /// Items of a defined-length sequence: record their elements.
  void _walkDefinedSequence(int pos, int end) {
    try {
      while (pos + 8 <= end) {
        final tag = (_u16(pos) << 16) | _u16(pos + 2);
        final len = _u32(pos + 4);
        pos += 8;
        if (tag != DicomTag.item) return;
        final itemEnd = len == _undefined ? end : pos + len;
        while (pos + 8 <= itemEnd) {
          final t = (_u16(pos) << 16) | _u16(pos + 2);
          if (t == DicomTag.itemDelimiter) {
            pos += 8;
            break;
          }
          pos = element(pos);
        }
        if (len != _undefined) pos = itemEnd;
      }
    } catch (_) {
      // Nested values are a bonus; ignore damage inside sequences.
    }
  }

  /// Skips items up to the sequence delimiter; returns the end.
  int _skipItems(int pos, {required bool record}) {
    while (pos + 8 <= b.length) {
      final tag = (_u16(pos) << 16) | _u16(pos + 2);
      final len = _u32(pos + 4);
      pos += 8;
      if (tag == DicomTag.sequenceDelimiter) return pos;
      if (tag != DicomTag.item) {
        throw DicomFormatException('Expected an item at ${pos - 8}');
      }
      if (len == _undefined) {
        // Elements until the item delimiter.
        while (pos + 8 <= b.length) {
          final t = (_u16(pos) << 16) | _u16(pos + 2);
          if (t == DicomTag.itemDelimiter) {
            pos += 8;
            break;
          }
          pos = element(pos);
        }
      } else {
        if (record) {
          var p = pos;
          try {
            while (p + 8 <= pos + len) {
              p = element(p);
            }
          } catch (_) {}
        }
        pos += len;
      }
    }
    return pos;
  }
}
