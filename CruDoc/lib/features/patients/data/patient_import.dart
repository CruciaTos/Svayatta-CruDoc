import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/xlsx_lite.dart';
import 'package:doctor_management_app/features/patients/domain/duplicate_patient.dart';

/// The CruDoc fields a file column can feed.
enum ImportField {
  firstName('First name', [
    'firstname', 'fname', 'givenname', 'forename', //
  ]),
  lastName('Last name', [
    'lastname', 'lname', 'surname', 'familyname', //
  ]),
  fullName('Full name', [
    'name', 'patientname', 'fullname', 'nameofpatient', 'patient', //
  ]),
  phone('Phone', [
    'phone', 'mobile', 'contact', 'mobileno', 'phoneno', 'contactno',
    'mobilenumber', 'phonenumber', 'telephone', 'cell', 'whatsapp',
    'contactnumber', //
  ]),
  gender('Gender', ['gender', 'sex']),
  dateOfBirth('Date of birth', [
    'dob', 'dateofbirth', 'birthdate', 'birthday', //
  ]),
  age('Age', ['age', 'ageyears', 'ageyrs']),
  email('Email', ['email', 'emailid', 'emailaddress', 'mail']),
  address('Address', ['address', 'addr', 'residence']),
  diagnosis('Diagnosis / chief complaint', [
    'diagnosis', 'complaint', 'chiefcomplaint', 'cc', 'problem', 'condition', //
  ]),
  notes('Notes', ['notes', 'remarks', 'remark', 'comments', 'note', 'history']),
  oldId('Old patient ID', [
    'regno', 'patientid', 'caseno', 'uhid', 'id', 'opdno', 'registrationno',
    'patientno', 'mrn', 'fileno', 'regnumber', //
  ]);

  const ImportField(this.label, this.synonyms);
  final String label;
  final List<String> synonyms;
}

/// Field → file column index (null: not matched).
typedef ImportMapping = Map<ImportField, int?>;

/// What the file held, ready for column matching.
class ParsedTable {
  const ParsedTable({
    this.error,
    this.headers = const [],
    this.rows = const [],
    this.sheetNames = const [],
    this.sheet = 0,
  });

  /// A friendly reason the file couldn't be read, else null.
  final String? error;
  final List<String> headers;

  /// Data rows (below the header), each as wide as [headers].
  final List<List<String>> rows;
  final List<String> sheetNames;
  final int sheet;
}

class TableRequest {
  const TableRequest(this.bytes, this.fileName, this.sheet);
  final Uint8List bytes;
  final String fileName;
  final int sheet;
}

/// Reads a .xlsx or .csv file. Runs in an isolate (see `compute`).
ParsedTable parseTableFile(TableRequest req) {
  final name = req.fileName.toLowerCase();
  if (name.endsWith('.xls')) {
    return const ParsedTable(
      error: 'Save it as .xlsx or .csv and try again.',
    );
  }
  const unreadable = ParsedTable(
    error: "Couldn't read this file. Check it opens in Excel, then try again.",
  );
  try {
    List<List<String>> raw;
    var names = const <String>[];
    var sheet = 0;
    if (name.endsWith('.xlsx')) {
      final book = XlsxBook.open(req.bytes);
      names = book.sheetNames;
      sheet = req.sheet.clamp(0, names.length - 1);
      raw = book.rows(sheet);
    } else if (name.endsWith('.csv') || name.endsWith('.txt')) {
      raw = _csvRows(req.bytes);
    } else {
      return const ParsedTable(error: 'Choose an .xlsx or .csv file.');
    }
    return _tableFrom(raw, names, sheet);
  } catch (_) {
    return unreadable;
  }
}

List<List<String>> _csvRows(Uint8List bytes) {
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  final body = Uint8List.sublistView(bytes, start);
  String text;
  try {
    text = utf8.decode(body);
  } catch (_) {
    text = latin1.decode(body);
  }
  final delimiter = _detectDelimiter(text);
  final rows = Csv(
    fieldDelimiter: delimiter,
    autoDetect: false,
    skipEmptyLines: true,
  ).decode(text);
  return [
    for (final r in rows) [for (final c in r) c?.toString() ?? ''],
  ];
}

String _detectDelimiter(String text) {
  final nl = text.indexOf('\n');
  final line = nl < 0 ? text : text.substring(0, nl);
  final counts = {',': 0, ';': 0, '\t': 0};
  var quoted = false;
  for (final ch in line.split('')) {
    if (ch == '"') {
      quoted = !quoted;
    } else if (!quoted && counts.containsKey(ch)) {
      counts[ch] = counts[ch]! + 1;
    }
  }
  var best = ',';
  var n = 0;
  counts.forEach((d, c) {
    if (c > n) {
      n = c;
      best = d;
    }
  });
  return best;
}

ParsedTable _tableFrom(List<List<String>> raw, List<String> names, int sheet) {
  bool blank(List<String> r) => r.every((c) => c.trim().isEmpty);
  final h = raw.indexWhere((r) => !blank(r));
  if (h < 0) {
    return ParsedTable(
      error: 'This file has no rows to import.',
      sheetNames: names,
      sheet: sheet,
    );
  }
  var width = 0;
  for (var i = h; i < raw.length; i++) {
    if (raw[i].length > width) width = raw[i].length;
  }
  final headers = [
    for (var i = 0; i < width; i++)
      i < raw[h].length && raw[h][i].trim().isNotEmpty
          ? raw[h][i].trim()
          : 'Column ${i + 1}',
  ];
  final rows = <List<String>>[];
  for (var i = h + 1; i < raw.length; i++) {
    if (blank(raw[i])) continue;
    rows.add([
      for (var c = 0; c < width; c++)
        c < raw[i].length ? raw[i][c].trim() : '',
    ]);
  }
  if (rows.isEmpty) {
    return ParsedTable(
      error: 'This file has headers but no patient rows.',
      sheetNames: names,
      sheet: sheet,
    );
  }
  return ParsedTable(
    headers: headers,
    rows: rows,
    sheetNames: names,
    sheet: sheet,
  );
}

// ---------------------------------------------------------------- matching

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Guesses the columns from their headers; each column is used once.
ImportMapping guessMapping(List<String> headers) {
  final normal = [for (final h in headers) _norm(h)];
  final used = <int>{};
  final out = <ImportField, int?>{};
  for (final f in ImportField.values) {
    int? hit;
    for (var i = 0; i < normal.length; i++) {
      if (!used.contains(i) && f.synonyms.contains(normal[i])) {
        hit = i;
        break;
      }
    }
    if (hit != null) used.add(hit);
    out[f] = hit;
  }
  return out;
}

String _mappingKey(List<String> headers) {
  // FNV-1a, so the key is the same on every run.
  var h = 0x811c9dc5;
  for (final u in headers.map(_norm).join('|').codeUnits) {
    h = ((h ^ u) * 0x01000193) & 0xFFFFFFFF;
  }
  return 'patient_import_mapping_${h.toRadixString(16)}';
}

/// The mapping used last time for these same headers, else a guess.
Future<ImportMapping> loadMapping(List<String> headers) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_mappingKey(headers));
    if (s != null) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      final out = <ImportField, int?>{};
      for (final f in ImportField.values) {
        final v = m[f.name];
        out[f] = v is int && v >= 0 && v < headers.length ? v : null;
      }
      return out;
    }
  } catch (_) {}
  return guessMapping(headers);
}

Future<void> saveMapping(List<String> headers, ImportMapping mapping) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _mappingKey(headers),
      jsonEncode({for (final e in mapping.entries) e.key.name: e.value}),
    );
  } catch (_) {}
}

// ----------------------------------------------------------------- parsing

enum RowStatus { ready, duplicate, error }

class ImportRow {
  ImportRow({
    required this.number,
    required this.raw,
    required this.status,
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.gender = '',
    this.email = '',
    this.age = '',
    this.dateOfBirth,
    this.diagnosis = const [],
    this.notes = '',
    this.warnings = const [],
    this.reason,
  });

  /// Row number in the file (the header is row 1 of the data's sheet).
  final int number;
  final List<String> raw;
  RowStatus status;

  /// No date of birth and no usable age: saved with today's date.
  bool get lacksDobAndAge =>
      status != RowStatus.error &&
      dateOfBirth == null &&
      _ageYears(age) == null;
  final String firstName;
  final String lastName;
  final String phone;
  final String gender;
  final String email;
  final String age;
  final DateTime? dateOfBirth;
  final List<String> diagnosis;

  /// Notes before the "Imported from" tag.
  final String notes;
  final List<String> warnings;

  /// Why the row is a duplicate or an error.
  String? reason;

  String get displayName => '$firstName $lastName'.trim();
}

class ImportPlan {
  const ImportPlan(this.rows);
  final List<ImportRow> rows;

  int get ready => rows.where((r) => r.status == RowStatus.ready).length;
  int get duplicates =>
      rows.where((r) => r.status == RowStatus.duplicate).length;
  int get errors => rows.where((r) => r.status == RowStatus.error).length;

  /// Rows that will be imported with today's date (no DOB and no usable age).
  int get noDob => rows.where((r) => r.lacksDobAndAge).length;
}

/// Age in years from a free-text age cell, else null.
int? _ageYears(String age) {
  final years = int.tryParse(RegExp(r'\d{1,3}').stringMatch(age) ?? '');
  return years != null && years <= 120 ? years : null;
}

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

String? _tail(String phone) {
  final d = _digits(phone);
  if (d.length < 7) return null;
  return d.length > 10 ? d.substring(d.length - 10) : d;
}

/// Phone as typed, keeping digits and a leading +. Excel often stores a
/// number as 9876543210.0 or 9.87654321E9.
String cleanPhone(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  if (RegExp(r'^\d+\.0+$').hasMatch(s)) s = s.split('.').first;
  if (RegExp(r'^\d(\.\d+)?[eE]\+?\d+$').hasMatch(s)) {
    final d = double.tryParse(s);
    if (d != null) s = d.toStringAsFixed(0);
  }
  final plus = s.startsWith('+');
  final digits = _digits(s);
  return digits.isEmpty ? '' : '${plus ? '+' : ''}$digits';
}

String _gender(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'm' || 'male':
      return 'Male';
    case 'f' || 'female':
      return 'Female';
    case 'o' || 'other':
      return 'Other';
  }
  return '';
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// dd/mm/yyyy and dd-mm-yyyy first (Indian), then yyyy-mm-dd, then
/// dd-Mon-yyyy and Excel serial numbers. Null when it isn't a real date.
DateTime? parseImportDate(String raw, DateTime now) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  DateTime? make(int y, int m, int d) {
    if (y < 100) y += y > now.year % 100 ? 1900 : 2000;
    if (y < 1900 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    final t = DateTime(y, m, d);
    if (t.month != m || t.day != d) return null;
    return t.isAfter(now) ? null : t;
  }

  var m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2}|\d{4})').firstMatch(s);
  if (m != null) {
    return make(
      int.parse(m.group(3)!),
      int.parse(m.group(2)!),
      int.parse(m.group(1)!),
    );
  }
  m = RegExp(r'^(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})').firstMatch(s);
  if (m != null) {
    return make(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }
  m = RegExp(r'^(\d{1,2})[ \-]([A-Za-z]{3})[a-z]*[ \-,]+(\d{2}|\d{4})$')
      .firstMatch(s);
  if (m != null) {
    final mo = _months[m.group(2)!.toLowerCase()];
    if (mo == null) return null;
    return make(int.parse(m.group(3)!), mo, int.parse(m.group(1)!));
  }
  final serial = double.tryParse(s);
  if (serial != null && serial >= 3000 && serial < 80000) {
    final t = DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
    return t.isAfter(now) ? null : DateTime(t.year, t.month, t.day);
  }
  return null;
}

/// Turns the file's rows into patients-to-be, with duplicate checks against
/// [existing] and earlier rows. Never invents a value: what can't be read is
/// left blank and noted.
ImportPlan buildImportPlan({
  required ParsedTable table,
  required ImportMapping mapping,
  required List<Patient> existing,
  required bool addOtherColumns,
  required DateTime now,
}) {
  String cell(List<String> r, ImportField f) {
    final i = mapping[f];
    return i == null || i >= r.length ? '' : r[i].trim();
  }

  final existingTails = <String>{};
  for (final p in existing) {
    final t = _tail(p.phone);
    if (t != null) existingTails.add(t);
  }
  final seenInFile = <String, int>{};
  final mappedCols = <int>{for (final v in mapping.values) ?v};
  final rows = <ImportRow>[];

  for (var n = 0; n < table.rows.length; n++) {
    final r = table.rows[n];
    final number = n + 2;
    var first = cell(r, ImportField.firstName);
    var last = cell(r, ImportField.lastName);
    final full = cell(r, ImportField.fullName);
    if (first.isEmpty && last.isEmpty && full.isNotEmpty) {
      final cut = full.trim().lastIndexOf(' ');
      if (cut > 0) {
        first = full.substring(0, cut).trim();
        last = full.substring(cut + 1).trim();
      } else {
        first = full.trim();
      }
    }
    if (first.isEmpty && last.isNotEmpty) {
      first = last;
      last = '';
    }
    if (first.isEmpty) {
      rows.add(
        ImportRow(
          number: number,
          raw: r,
          status: RowStatus.error,
          reason: 'No name',
        ),
      );
      continue;
    }

    final warnings = <String>[];
    final phone = cleanPhone(cell(r, ImportField.phone));
    if (phone.isNotEmpty && _digits(phone).length < 10) {
      warnings.add('Phone has fewer than 10 digits');
    }
    final genderRaw = cell(r, ImportField.gender);
    final gender = _gender(genderRaw);
    if (genderRaw.isNotEmpty && gender.isEmpty) {
      warnings.add('Gender not recognised');
    }
    final dobRaw = cell(r, ImportField.dateOfBirth);
    final dob = parseImportDate(dobRaw, now);
    if (dobRaw.isNotEmpty && dob == null) {
      warnings.add('Date of birth not recognised');
    }
    final diagnosis = [
      for (final d in cell(r, ImportField.diagnosis).split(RegExp(r'[,;]')))
        if (d.trim().isNotEmpty) d.trim(),
    ].take(Patient.maxDiagnoses).toList();

    final notes = <String>[];
    final own = cell(r, ImportField.notes);
    if (own.isNotEmpty) notes.add(own);
    final age = cell(r, ImportField.age);
    if (age.isNotEmpty) notes.add('Age at import: $age');
    final address = cell(r, ImportField.address);
    if (address.isNotEmpty) notes.add('Address: $address');
    final oldId = cell(r, ImportField.oldId);
    if (oldId.isNotEmpty) notes.add('Old ID: $oldId');
    if (addOtherColumns) {
      for (var c = 0; c < table.headers.length; c++) {
        if (mappedCols.contains(c) || c >= r.length || r[c].isEmpty) continue;
        notes.add('${table.headers[c]}: ${r[c]}');
      }
    }

    var status = RowStatus.ready;
    String? reason;
    final tail = _tail(phone);
    if (tail != null) {
      Patient? known;
      if (existingTails.contains(tail)) {
        known = duplicateByPhone(existing, phone);
      } else if (tail.length < 10) {
        known = duplicateByPhone(existing, phone);
      }
      final earlier = seenInFile[tail];
      if (known != null) {
        status = RowStatus.duplicate;
        reason = 'Same phone as ${known.fullName.trim()}';
      } else if (earlier != null) {
        status = RowStatus.duplicate;
        reason = 'Same phone as row $earlier';
      }
      seenInFile.putIfAbsent(tail, () => number);
    }

    rows.add(
      ImportRow(
        number: number,
        raw: r,
        status: status,
        firstName: first,
        lastName: last,
        phone: phone,
        gender: gender,
        email: cell(r, ImportField.email),
        age: age,
        dateOfBirth: dob,
        diagnosis: diagnosis,
        notes: notes.join('\n'),
        warnings: warnings,
        reason: reason,
      ),
    );
  }
  return ImportPlan(rows);
}

/// The patient to create for [row]. CruDoc needs a date of birth: from the
/// file, else from the age (1 January of that year), else today, and notes
/// say so.
Patient patientForRow(
  ImportRow row, {
  required String fileName,
  required DateTime now,
}) {
  var dob = row.dateOfBirth;
  final notes = <String>[if (row.notes.isNotEmpty) row.notes];
  if (dob == null) {
    final years = _ageYears(row.age);
    if (years != null) {
      dob = DateTime(now.year - years);
    } else {
      dob = DateTime(now.year, now.month, now.day);
      notes.add('Date of birth not in the imported file');
    }
  }
  notes.add(
    'Imported from $fileName on ${DateFormat('dd/MM/yyyy').format(now)}',
  );
  return Patient(
    id: '',
    firstName: row.firstName,
    lastName: row.lastName,
    phone: row.phone,
    email: row.email,
    gender: row.gender,
    dateOfBirth: dob,
    diagnosis: row.diagnosis,
    notes: notes.join('\n'),
    packageBalance: 0,
    isArchived: false,
    createdAt: now,
    updatedAt: now,
  );
}

/// The headers a sample file carries (no patient rows).
const sampleHeaders = [
  'First name',
  'Last name',
  'Phone',
  'Gender',
  'Date of birth',
  'Age',
  'Email',
  'Address',
  'Diagnosis',
  'Notes',
  'Old patient ID',
];

/// A prompt the doctor pastes into any AI chat (Gemini, ChatGPT, Claude) with
/// their messy sheet; the reply is a CSV whose headers match [sampleHeaders],
/// so the column step matches every field automatically.
final String aiFormatPrompt = '''
You are helping me move my dental clinic's patient list into a new app called CruDoc.
Below my instructions I will paste my patient data. It may be messy: different column
names, merged cells, extra rows, mixed date formats, names in one column, phone numbers
with spaces, etc.

Convert it into ONE clean CSV table with EXACTLY these column headers, in this order:

${sampleHeaders.join(',')}

Rules:
1. One row per patient. Skip title rows, blank rows, totals, and repeated header rows.
2. Names: if the full name is in one column, put the last word in "Last name" and the rest
   in "First name". Remove titles like Dr., Mr., Mrs., Ms., Smt., Shri.
3. Phone: digits only, keep a leading + if present (e.g. 9876543210 or +919876543210).
   If a patient has two numbers, put the first in Phone and the second in Notes as
   "Other phone: ...".
4. Gender: write only Male, Female or Other. If it is not clearly given, leave it blank.
   Do NOT guess gender from the name.
5. Date of birth: format dd/mm/yyyy. My dates are in Indian day/month order unless the
   year comes first. If only age is given, put it in "Age" and leave Date of birth blank.
   Do NOT calculate a date of birth from age.
6. Diagnosis: chief complaint or diagnosis. Separate several items with a semicolon (;).
7. Notes: put any other useful information here (treatment done, balance due, remarks,
   referred by, last visit date, extra phone numbers), joined with " | ".
8. Old patient ID: my old registration / case / file number, if any.
9. NEVER invent, guess or fill in information that is not in my data. If something is
   missing or unclear, leave that cell empty.
10. If a value contains a comma, wrap the whole value in double quotes.
11. Output ONLY the CSV inside one code block, nothing else. After the code block, write
    one short line saying how many patients you converted and list any rows you skipped
    or were unsure about (by their row number in my data), with the reason.

If my data is very long and you cannot finish in one reply, stop at a complete row,
say "CONTINUE FROM ROW N", and I will reply "continue".

My data:
[PASTE YOUR EXCEL ROWS HERE]
''';

/// CSV bytes (UTF-8 with BOM, so Excel reads accents) for [rows].
Uint8List csvBytes(List<List<String>> rows) {
  final text = Csv(lineDelimiter: '\r\n').encode(rows);
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
}
