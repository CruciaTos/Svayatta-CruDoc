import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A small .xlsx reader and writer on top of `archive` (the `excel` package
/// needs archive 3, which this app can't use). Reads cell text only, which is
/// all a patient list needs; writes one plain sheet.
class XlsxBook {
  XlsxBook._(this._archive, this.sheetNames, this._sheetPaths);

  final Archive _archive;
  final List<String> sheetNames;
  final List<String> _sheetPaths;

  /// Throws [FormatException] when [bytes] aren't an .xlsx file.
  factory XlsxBook.open(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('Not an xlsx file');
    }
    String? read(String name) {
      final f = archive.findFile(name);
      if (f == null) return null;
      return utf8.decode(f.content, allowMalformed: true);
    }

    final workbook = read('xl/workbook.xml');
    if (workbook == null) throw const FormatException('Not an xlsx file');
    final rels = read('xl/_rels/workbook.xml.rels') ?? '';
    final targets = <String, String>{};
    for (final m in RegExp(r'<Relationship\b([^>]*?)/?>').allMatches(rels)) {
      final a = _attrs(m.group(1)!);
      final id = a['Id'];
      final target = a['Target'];
      if (id != null && target != null) targets[id] = target;
    }
    final names = <String>[];
    final paths = <String>[];
    var n = 0;
    for (final m in RegExp(r'<sheet\b([^>]*?)/?>').allMatches(workbook)) {
      n++;
      final a = _attrs(m.group(1)!);
      var target = targets[a['r:id'] ?? ''] ?? 'worksheets/sheet$n.xml';
      target = target.startsWith('/')
          ? target.substring(1)
          : 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
      names.add(_unescape(a['name'] ?? 'Sheet $n'));
      paths.add(target);
    }
    if (names.isEmpty) throw const FormatException('No sheets');
    return XlsxBook._(archive, names, paths);
  }

  List<String>? _shared;

  List<String> _sharedStrings() {
    if (_shared != null) return _shared!;
    final f = _archive.findFile('xl/sharedStrings.xml');
    final out = <String>[];
    if (f != null) {
      final xml = utf8.decode(f.content, allowMalformed: true);
      for (final si in RegExp(r'<si\b[^>]*?(?:/>|>(.*?)</si>)', dotAll: true)
          .allMatches(xml)) {
        out.add(_textOf(si.group(1) ?? ''));
      }
    }
    return _shared = out;
  }

  /// Every row of sheet [index] as text, empty cells as ''. Rows are padded
  /// to the widest row.
  List<List<String>> rows(int index) {
    final f = _archive.findFile(_sheetPaths[index]);
    if (f == null) throw const FormatException('Sheet missing');
    final xml = utf8.decode(f.content, allowMalformed: true);
    final shared = _sharedStrings();
    final out = <List<String>>[];
    var width = 0;
    for (final r in RegExp(r'<row\b[^>]*?(?:/>|>(.*?)</row>)', dotAll: true)
        .allMatches(xml)) {
      final cells = <String>[];
      final body = r.group(1) ?? '';
      var next = 0;
      for (final c in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true)
          .allMatches(body)) {
        final a = _attrs(c.group(1)!);
        final col = _column(a['r']) ?? next;
        while (cells.length < col) {
          cells.add('');
        }
        final inner = c.group(2) ?? '';
        final t = a['t'];
        String value;
        if (t == 'inlineStr') {
          value = _textOf(inner);
        } else {
          final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(inner);
          final raw = v == null ? '' : _unescape(v.group(1)!);
          if (t == 's') {
            final i = int.tryParse(raw.trim());
            value = i != null && i >= 0 && i < shared.length ? shared[i] : '';
          } else if (t == 'b') {
            value = raw.trim() == '1' ? 'TRUE' : 'FALSE';
          } else {
            value = raw;
          }
        }
        if (col < cells.length) {
          cells[col] = value;
        } else {
          cells.add(value);
        }
        next = col + 1;
      }
      if (cells.length > width) width = cells.length;
      out.add(cells);
    }
    for (final r in out) {
      while (r.length < width) {
        r.add('');
      }
    }
    return out;
  }

  /// A one-sheet workbook; every value is written as text.
  static Uint8List write(List<List<String>> rows, {String sheet = 'Sheet1'}) {
    final sb = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>',
    );
    for (var r = 0; r < rows.length; r++) {
      sb.write('<row r="${r + 1}">');
      for (var c = 0; c < rows[r].length; c++) {
        final v = rows[r][c];
        if (v.isEmpty) continue;
        sb.write(
          '<c r="${_letters(c)}${r + 1}" t="inlineStr"><is>'
          '<t xml:space="preserve">${_escape(v)}</t></is></c>',
        );
      }
      sb.write('</row>');
    }
    sb.write('</sheetData></worksheet>');

    const head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          '[Content_Types].xml',
          '$head<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
              '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
              '<Default Extension="xml" ContentType="application/xml"/>'
              '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
              '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
              '</Types>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          '_rels/.rels',
          '$head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
              '</Relationships>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/workbook.xml',
          '$head<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
              'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
              '<sheets><sheet name="${_escape(sheet)}" sheetId="1" r:id="rId1"/></sheets></workbook>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/_rels/workbook.xml.rels',
          '$head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
              '</Relationships>',
        ),
      )
      ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', sb.toString()));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static Map<String, String> _attrs(String s) => {
    for (final m in RegExp(r'([\w:]+)\s*=\s*"([^"]*)"').allMatches(s))
      m.group(1)!: m.group(2)!,
  };

  /// Text of every `<t>` in [xml], skipping phonetic runs.
  static String _textOf(String xml) {
    final clean = xml.replaceAll(
      RegExp(r'<rPh\b.*?</rPh>', dotAll: true),
      '',
    );
    final b = StringBuffer();
    for (final t in RegExp(r'<t\b[^>]*?(?:/>|>(.*?)</t>)', dotAll: true)
        .allMatches(clean)) {
      b.write(_unescape(t.group(1) ?? ''));
    }
    return b.toString();
  }

  static int? _column(String? ref) {
    if (ref == null) return null;
    final m = RegExp(r'^([A-Za-z]+)').firstMatch(ref);
    if (m == null) return null;
    var n = 0;
    for (final u in m.group(1)!.toUpperCase().codeUnits) {
      n = n * 26 + (u - 64);
    }
    return n - 1;
  }

  static String _letters(int index) {
    var n = index + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static String _escape(String s) => s
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _unescape(String s) => s.replaceAllMapped(
    RegExp(r'&(#x[0-9A-Fa-f]+|#\d+|amp|lt|gt|quot|apos);'),
    (m) {
      final e = m.group(1)!;
      switch (e) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final code = e.startsWith('#x')
          ? int.tryParse(e.substring(2), radix: 16)
          : int.tryParse(e.substring(1));
      return code == null ? m.group(0)! : String.fromCharCode(code);
    },
  );
}
