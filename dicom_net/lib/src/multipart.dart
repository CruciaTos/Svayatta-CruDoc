import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// multipart/related bodies as DICOMweb uses them (WADO-RS responses,
/// STOW-RS requests).
abstract final class Multipart {
  static String newBoundary() {
    final r = Random.secure();
    return 'DICOMNET-${List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join()}';
  }

  /// The Content-Type header for a body built with [boundary].
  static String contentType(String boundary, {String type = 'application/dicom'}) =>
      'multipart/related; type="$type"; boundary=$boundary';

  static Uint8List build(
    List<Uint8List> parts,
    String boundary, {
    String partType = 'application/dicom',
  }) {
    final out = BytesBuilder(copy: false);
    for (final p in parts) {
      out
        ..add(ascii.encode('--$boundary\r\nContent-Type: $partType\r\n\r\n'))
        ..add(p)
        ..add(ascii.encode('\r\n'));
    }
    out.add(ascii.encode('--$boundary--\r\n'));
    return out.takeBytes();
  }

  /// The boundary parameter of a Content-Type header, or null.
  static String? boundaryOf(String? contentType) {
    if (contentType == null) return null;
    final m = RegExp(
      r'boundary\s*=\s*("([^"]+)"|([^;\s]+))',
      caseSensitive: false,
    ).firstMatch(contentType);
    return m == null ? null : (m.group(2) ?? m.group(3));
  }

  /// The parts' contents (headers stripped).
  static List<Uint8List> parse(Uint8List body, String boundary) {
    final delim = ascii.encode('--$boundary');
    final parts = <Uint8List>[];
    var i = _indexOf(body, delim, 0);
    while (i >= 0) {
      var start = i + delim.length;
      // "--" after the boundary ends the body.
      if (start + 1 < body.length &&
          body[start] == 0x2D &&
          body[start + 1] == 0x2D) {
        break;
      }
      final headersEnd = _indexOf(body, const [13, 10, 13, 10], start);
      if (headersEnd < 0) break;
      start = headersEnd + 4;
      final next = _indexOf(body, delim, start);
      if (next < 0) break;
      var end = next;
      if (end >= 2 && body[end - 2] == 13 && body[end - 1] == 10) end -= 2;
      parts.add(Uint8List.sublistView(body, start, end));
      i = next;
    }
    return parts;
  }

  static int _indexOf(Uint8List hay, List<int> needle, int from) {
    final first = needle[0];
    final last = hay.length - needle.length;
    outer:
    for (var i = from; i <= last; i++) {
      if (hay[i] != first) continue;
      for (var j = 1; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
