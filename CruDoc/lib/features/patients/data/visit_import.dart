import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/patient_import.dart';

/// Importing a clinic's past visits from the software they used before
/// CruDoc.
///
/// The patient list comes in first (see `patient_import.dart`); this maps
/// each row of a visit-history file onto a patient who is already here. A row
/// that cannot be matched to exactly one patient is never guessed at — it is
/// reported so the clinic can fix the file and run it again.
///
/// File reading, the column step and date parsing are shared with the patient
/// import: [parseTableFile], [ParsedTable] and [parseImportDate].

/// The visit fields a file column can feed.
enum VisitImportField {
  patientOldId('Patient ID in old software', [
    'patientid', 'regno', 'uhid', 'caseno', 'opdno', 'registrationno',
    'patientno', 'mrn', 'fileno', 'regnumber', 'id', //
  ]),
  patientPhone('Patient phone', [
    'phone', 'mobile', 'contact', 'mobileno', 'phoneno', 'contactno',
    'mobilenumber', 'phonenumber', 'patientphone', 'patientmobile', //
  ]),
  patientName('Patient name', [
    'name', 'patientname', 'fullname', 'patient', 'nameofpatient', //
  ]),
  date('Visit date', [
    'date', 'visitdate', 'appointmentdate', 'dateofvisit', 'visiton',
    'treatmentdate', 'consultationdate', //
  ]),
  time('Visit time', [
    'time', 'visittime', 'appointmenttime', 'slot', 'timeofvisit', //
  ]),
  status('Status', [
    'status', 'visitstatus', 'attendance', 'attended', 'outcome', //
  ]),
  treatment('Treatment / procedure', [
    'treatment', 'procedure', 'service', 'work', 'treatmentdone',
    'workdone', 'procedures', 'treatmenttype', //
  ]),
  notes('Notes', [
    'notes', 'remarks', 'remark', 'comments', 'note', 'findings',
    'observation', //
  ]),
  amount('Amount charged', [
    'amount', 'fees', 'fee', 'charges', 'charge', 'total', 'paid',
    'amountpaid', 'bill', 'billamount', 'cost', //
  ]),
  paid('Paid?', [
    'ispaid', 'paidstatus', 'payment', 'paymentstatus', 'settled', //
  ]);

  const VisitImportField(this.label, this.synonyms);
  final String label;
  final List<String> synonyms;

  /// A row needs a date, and some way to say whose visit it is.
  static const List<VisitImportField> patientKeys = [
    patientOldId,
    patientPhone,
    patientName,
  ];
}

/// Field → file column index (null: not matched).
typedef VisitImportMapping = Map<VisitImportField, int?>;

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// The last 10 digits of a phone number, or null when there are too few to
/// identify anyone. Matches the patient import's own rule.
String? _tail(String phone) {
  final d = _digits(phone);
  if (d.length < 7) return null;
  return d.length > 10 ? d.substring(d.length - 10) : d;
}

/// Guesses the columns from their headers; each column is used once.
VisitImportMapping guessVisitMapping(List<String> headers) {
  final normal = [for (final h in headers) _norm(h)];
  final used = <int>{};
  final out = <VisitImportField, int?>{};
  for (final f in VisitImportField.values) {
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
  return 'visit_import_mapping_${h.toRadixString(16)}';
}

/// The mapping used last time for these same headers, else a guess.
Future<VisitImportMapping> loadVisitMapping(List<String> headers) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_mappingKey(headers));
    if (s != null) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      final out = <VisitImportField, int?>{};
      for (final f in VisitImportField.values) {
        final v = m[f.name];
        out[f] = v is int && v >= 0 && v < headers.length ? v : null;
      }
      return out;
    }
  } catch (_) {}
  return guessVisitMapping(headers);
}

Future<void> saveVisitMapping(
  List<String> headers,
  VisitImportMapping mapping,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _mappingKey(headers),
      jsonEncode({for (final e in mapping.entries) e.key.name: e.value}),
    );
  } catch (_) {}
}

// ------------------------------------------------------------- patient match

/// The old-software id to match a patient on.
///
/// Patients imported before `oldId` became a field of its own carry it as a
/// line inside their notes ("Old ID: 1234"), which is where the import used
/// to put it. Reading both means a clinic that already imported its patients
/// does not have to import them again to bring its visit history in.
String oldIdForMatching(Patient patient) {
  final own = patient.oldId.trim();
  if (own.isNotEmpty) return own;
  final m = RegExp(
    r'^\s*Old ID:\s*(.+)$',
    multiLine: true,
  ).firstMatch(patient.notes);
  return m == null ? '' : m.group(1)!.trim();
}

/// Patients indexed the three ways a visit row can name one. Built once for
/// a whole file rather than per row.
class PatientIndex {
  PatientIndex._(this._byOldId, this._byPhone, this._byName, this.ambiguous);

  factory PatientIndex(List<Patient> patients) {
    final byOldId = <String, Patient>{};
    final byPhone = <String, Patient>{};
    final byName = <String, Patient>{};
    // A key more than one patient answers to identifies nobody, so it is
    // dropped and remembered: the row it would have matched is reported as
    // ambiguous rather than attached to whichever patient came first.
    final ambiguous = <String>{};
    void put(Map<String, Patient> into, String key, Patient p) {
      if (key.isEmpty) return;
      final had = into[key];
      if (had != null && had.id != p.id) {
        into.remove(key);
        ambiguous.add(key);
        return;
      }
      if (!ambiguous.contains(key)) into[key] = p;
    }

    for (final p in patients) {
      if (p.isArchived) continue;
      put(byOldId, _norm(oldIdForMatching(p)), p);
      final tail = _tail(p.phone);
      if (tail != null) put(byPhone, tail, p);
      put(byName, _norm(p.fullName), p);
    }
    return PatientIndex._(byOldId, byPhone, byName, ambiguous);
  }

  final Map<String, Patient> _byOldId;
  final Map<String, Patient> _byPhone;
  final Map<String, Patient> _byName;

  /// Keys that more than one patient answered to.
  final Set<String> ambiguous;

  /// The one patient a row names, or null with the reason why not.
  ///
  /// Tried in order of how reliably each identifies somebody: the clinic's
  /// own id from their old software, then the phone number, then the name.
  ({Patient? patient, String? reason}) match({
    required String oldId,
    required String phone,
    required String name,
  }) {
    final byOld = _norm(oldId);
    if (byOld.isNotEmpty) {
      final hit = _byOldId[byOld];
      if (hit != null) return (patient: hit, reason: null);
      if (ambiguous.contains(byOld)) {
        return (patient: null, reason: 'More than one patient has ID $oldId');
      }
    }
    final tail = _tail(phone);
    if (tail != null) {
      final hit = _byPhone[tail];
      if (hit != null) return (patient: hit, reason: null);
      if (ambiguous.contains(tail)) {
        return (
          patient: null,
          reason: 'More than one patient has the phone $phone',
        );
      }
    }
    final byName = _norm(name);
    if (byName.isNotEmpty) {
      final hit = _byName[byName];
      if (hit != null) return (patient: hit, reason: null);
      if (ambiguous.contains(byName)) {
        return (patient: null, reason: 'More than one patient named $name');
      }
    }
    final said = [
      if (oldId.trim().isNotEmpty) 'ID $oldId',
      if (phone.trim().isNotEmpty) phone,
      if (name.trim().isNotEmpty) name,
    ];
    return (
      patient: null,
      reason: said.isEmpty
          ? 'The row does not say whose visit it is'
          : 'No patient here matches ${said.join(' / ')}',
    );
  }
}

// ------------------------------------------------------------------- parsing

/// Time of day for a visit whose file gives no time. Imported history is a
/// record of what happened rather than a diary to work from, so the hour
/// only has to be plausible and consistent.
const int kVisitImportDefaultHour = 9;

/// Length saved for an imported visit, in minutes.
const int kVisitImportDurationMinutes = 30;

/// Hours and minutes from a free-text time cell, else null. Accepts
/// "9", "9:30", "09:30", "9.30", "9:30 am", "9 PM" and "21:30".
({int hour, int minute})? parseImportTime(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{1,2})(?:[:.](\d{1,2}))?\s*(am|pm)?').firstMatch(s);
  if (m == null) return null;
  var hour = int.parse(m.group(1)!);
  final minute = int.tryParse(m.group(2) ?? '0') ?? 0;
  final suffix = m.group(3);
  if (suffix == 'pm' && hour < 12) hour += 12;
  if (suffix == 'am' && hour == 12) hour = 0;
  if (hour > 23 || minute > 59) return null;
  return (hour: hour, minute: minute);
}

/// The status a cell names, else null. Unrecognised text is not forced into
/// a status: [statusForRow] decides from the date instead.
VisitStatus? parseImportStatus(String raw) {
  final s = _norm(raw);
  if (s.isEmpty) return null;
  const completed = <String>{
    'completed', 'complete', 'done', 'attended', 'seen', 'finished',
    'closed', 'yes', 'y', 'visited', 'present', 'treated', //
  };
  const cancelled = <String>{
    'cancelled', 'canceled', 'cancel', 'calledoff', //
  };
  const missed = <String>{
    'missed', 'noshow', 'absent', 'didnotattend', 'dna', 'no', 'n',
    'skipped', 'failed', //
  };
  const scheduled = <String>{
    'scheduled', 'booked', 'upcoming', 'pending', 'confirmed', //
  };
  if (completed.contains(s)) return VisitStatus.completed;
  if (cancelled.contains(s)) return VisitStatus.cancelled;
  if (missed.contains(s)) return VisitStatus.missed;
  if (scheduled.contains(s)) return VisitStatus.scheduled;
  return null;
}

/// The status to save: what the file says, else completed for a visit in the
/// past and scheduled for one still to come.
VisitStatus statusForRow(String raw, DateTime start, DateTime now) =>
    parseImportStatus(raw) ??
    (start.isBefore(now) ? VisitStatus.completed : VisitStatus.scheduled);

/// An amount from a free-text money cell, else null. Strips currency
/// symbols, thousands separators and a trailing "/-".
double? parseImportAmount(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  s = s
      .replaceAll(RegExp(r'[₹$£€]'), '')
      .replaceAll(RegExp(r'\b(rs|inr)\b\.?', caseSensitive: false), '')
      .replaceAll(RegExp(r'/-\s*$'), '')
      .replaceAll(',', '')
      .trim();
  final m = RegExp(r'-?\d+(\.\d+)?').stringMatch(s);
  if (m == null) return null;
  final value = double.tryParse(m);
  if (value == null || value < 0) return null;
  return value;
}

/// Whether a "paid?" cell says yes. Null when it says nothing either way, so
/// an amount on its own does not claim the money was collected.
bool? parseImportPaid(String raw) {
  final s = _norm(raw);
  if (s.isEmpty) return null;
  const yes = <String>{
    'yes', 'y', 'paid', 'true', '1', 'settled', 'done', 'cash', 'card',
    'upi', 'online', 'cleared', //
  };
  const no = <String>{
    'no', 'n', 'unpaid', 'false', '0', 'pending', 'due', 'outstanding',
    'credit', //
  };
  if (yes.contains(s)) return true;
  if (no.contains(s)) return false;
  return null;
}

class VisitImportRow {
  VisitImportRow({
    required this.number,
    required this.raw,
    required this.status,
    this.patient,
    this.start,
    this.visitStatus = VisitStatus.completed,
    this.treatment = '',
    this.notes = '',
    this.amount,
    this.paid,
    this.hadTime = false,
    this.warnings = const [],
    this.reason,
  });

  /// Row number in the file (the header is row 1 of the data's sheet).
  final int number;
  final List<String> raw;
  RowStatus status;

  /// The patient this visit belongs to, once matched.
  final Patient? patient;

  /// Date and time of the visit. Null only on an error row.
  final DateTime? start;
  final VisitStatus visitStatus;
  final String treatment;
  final String notes;
  final double? amount;
  final bool? paid;

  /// False when the file gave no time and [kVisitImportDefaultHour] was used.
  final bool hadTime;
  final List<String> warnings;

  /// Why the row is a duplicate or an error.
  String? reason;

  String get displayName => patient?.fullName.trim() ?? '';
}

class VisitImportPlan {
  const VisitImportPlan(this.rows);
  final List<VisitImportRow> rows;

  int get ready => rows.where((r) => r.status == RowStatus.ready).length;
  int get duplicates =>
      rows.where((r) => r.status == RowStatus.duplicate).length;
  int get errors => rows.where((r) => r.status == RowStatus.error).length;

  /// Rows placed at [kVisitImportDefaultHour] because the file gave no time.
  int get noTime =>
      rows.where((r) => r.status != RowStatus.error && !r.hadTime).length;

  /// How many distinct patients the readable rows belong to.
  int get patients => {
    for (final r in rows)
      if (r.status != RowStatus.error && r.patient != null) r.patient!.id,
  }.length;
}

/// One visit per patient per day: the key both the file and what CruDoc
/// already holds are checked against.
String visitDayKey(String patientId, DateTime start) =>
    '$patientId@${start.year}-${start.month}-${start.day}';

/// Reads [table] into a plan: which rows are ready, which are duplicates of
/// a visit already here (or of an earlier row), and which cannot be read.
///
/// [existingPatients] is every patient CruDoc holds, and [existingVisitDays]
/// the [visitDayKey] of every visit it already has, so importing the same
/// file twice does not double the history.
VisitImportPlan buildVisitPlan({
  required ParsedTable table,
  required VisitImportMapping mapping,
  required List<Patient> existingPatients,
  required Set<String> existingVisitDays,
  required DateTime now,
}) {
  final index = PatientIndex(existingPatients);
  final rows = <VisitImportRow>[];
  final seenInFile = <String, int>{};

  String cell(List<String> r, VisitImportField f) {
    final i = mapping[f];
    if (i == null || i < 0 || i >= r.length) return '';
    return r[i].trim();
  }

  for (var i = 0; i < table.rows.length; i++) {
    final r = table.rows[i];
    final number = i + 2; // the header is row 1
    if (r.every((c) => c.trim().isEmpty)) continue;

    final match = index.match(
      oldId: cell(r, VisitImportField.patientOldId),
      phone: cell(r, VisitImportField.patientPhone),
      name: cell(r, VisitImportField.patientName),
    );
    final patient = match.patient;
    if (patient == null) {
      rows.add(
        VisitImportRow(
          number: number,
          raw: r,
          status: RowStatus.error,
          reason: match.reason,
        ),
      );
      continue;
    }

    final dateRaw = cell(r, VisitImportField.date);
    final day = parseImportDate(dateRaw, now);
    if (day == null) {
      rows.add(
        VisitImportRow(
          number: number,
          raw: r,
          status: RowStatus.error,
          reason: dateRaw.isEmpty
              ? 'No visit date'
              : 'Visit date not recognised: $dateRaw',
        ),
      );
      continue;
    }

    final warnings = <String>[];
    final timeRaw = cell(r, VisitImportField.time);
    final time = parseImportTime(timeRaw);
    if (timeRaw.isNotEmpty && time == null) {
      warnings.add('Time not recognised');
    }
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      time?.hour ?? kVisitImportDefaultHour,
      time?.minute ?? 0,
    );
    if (start.isAfter(now)) warnings.add('Date is in the future');

    final amountRaw = cell(r, VisitImportField.amount);
    final amount = parseImportAmount(amountRaw);
    if (amountRaw.isNotEmpty && amount == null) {
      warnings.add('Amount not recognised');
    }
    final statusRaw = cell(r, VisitImportField.status);
    if (statusRaw.isNotEmpty && parseImportStatus(statusRaw) == null) {
      warnings.add('Status not recognised: taken from the date instead');
    }

    var status = RowStatus.ready;
    String? reason;
    final key = visitDayKey(patient.id, start);
    final earlier = seenInFile[key];
    if (existingVisitDays.contains(key)) {
      status = RowStatus.duplicate;
      reason = '${patient.fullName.trim()} already has a visit that day';
    } else if (earlier != null) {
      status = RowStatus.duplicate;
      reason = 'Same patient and day as row $earlier';
    }
    seenInFile.putIfAbsent(key, () => number);

    rows.add(
      VisitImportRow(
        number: number,
        raw: r,
        status: status,
        patient: patient,
        start: start,
        visitStatus: statusForRow(statusRaw, start, now),
        treatment: cell(r, VisitImportField.treatment),
        notes: cell(r, VisitImportField.notes),
        amount: amount,
        paid: parseImportPaid(cell(r, VisitImportField.paid)),
        hadTime: time != null,
        warnings: warnings,
        reason: reason,
      ),
    );
  }
  return VisitImportPlan(rows);
}

/// The visit to save for [row].
///
/// Imported history is saved as a plain clinic visit with no address, so
/// nothing is geocoded. The note says where it came from, since an imported
/// visit was never seen in CruDoc and should not read as though it was.
Visit visitForRow(
  VisitImportRow row, {
  required String fileName,
  required DateTime now,
}) {
  final notes = <String>[
    if (row.notes.trim().isNotEmpty) row.notes.trim(),
    'Imported from $fileName',
  ];
  final treatment = row.treatment.trim();
  return Visit(
    id: '',
    patientId: row.patient!.id,
    scheduledStart: row.start!,
    durationMinutes: kVisitImportDurationMinutes,
    address: '',
    status: row.visitStatus,
    visitType: VisitType.clinic,
    treatmentType: treatment.isEmpty ? null : treatment,
    therapistNotes: notes.join('\n'),
    amountCharged: row.amount,
    // An amount on its own says what was billed, not that it was collected.
    isPaid: row.paid ?? false,
    createdAt: now,
    updatedAt: now,
  );
}

/// The headers a sample visit-history file carries (no rows).
const visitSampleHeaders = [
  'Patient ID in old software',
  'Patient name',
  'Patient phone',
  'Visit date',
  'Visit time',
  'Status',
  'Treatment',
  'Notes',
  'Amount',
  'Paid?',
];
