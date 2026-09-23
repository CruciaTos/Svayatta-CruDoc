// Test-only sample data for the Appointments Week and Month goldens,
// mirroring design/clinic-redesign/screens/appointments-3-week.png and
// appointments-4-month.png. Never imported by app code.

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';

/// Wednesday 23 September 2026, 11:48, as in the Week mock-up.
final DateTime weekNow = DateTime(2026, 9, 23, 11, 48);

const VisitStatus _done = VisitStatus.completed;
const VisitStatus _booked = VisitStatus.scheduled;
const VisitStatus _missed = VisitStatus.missed;

DateTime _t(int day, int h, int m) => DateTime(2026, 9, day, h, m);

final Map<String, Patient> _patients = {};

/// Registers (once) and returns the id of "First Last".
String _p(String first, String last) {
  final id = 'wp_${first.toLowerCase()}_${last.toLowerCase()}';
  _patients.putIfAbsent(
    id,
    () => Patient(
      id: id,
      firstName: first,
      lastName: last,
      phone: '',
      gender: 'Female',
      dateOfBirth: DateTime(1988, 4, 12),
      diagnosis: const [],
      packageBalance: 0,
      isArchived: false,
      createdAt: DateTime(2025, 6, 1),
      updatedAt: DateTime(2025, 6, 1),
    ),
  );
  return id;
}

var _seq = 0;

Visit _v(
  String first,
  String last,
  DateTime start, {
  VisitStatus status = _booked,
  String? reason,
  int minutes = 20,
}) {
  _seq++;
  return Visit(
    id: 'wv_${start.day}_${start.hour}_${start.minute}_$_seq',
    patientId: _p(first, last),
    scheduledStart: start,
    durationMinutes: minutes,
    address: '',
    status: status,
    treatmentType: reason,
    isDeleted: false,
    createdAt: DateTime(2026, 9, 1, 10, _seq % 60),
    updatedAt: DateTime(2026, 9, 1, 10, _seq % 60),
  );
}

/// The week of 21–27 September, as drawn in the Week mock-up. Sunday 27
/// has no visits (closed days aren't stored, so it's just empty).
/// Saturday has one unsorted overlap (Rohit and Seema at 11:50) so the
/// amber dot and split column show.
List<Visit> _week() => [
      // Mon 21: 11 seen.
      _v('Rakesh', 'Patil', _t(21, 9, 30), status: _done),
      _v('Ritu', 'Shah', _t(21, 9, 50), status: _done),
      _v('Ganesh', 'Kulkarni', _t(21, 10, 10), status: _done),
      _v('Swati', 'Desai', _t(21, 10, 30), status: _done),
      _v('Amit', 'Joshi', _t(21, 11, 10), status: _done),
      _v('Neelam', 'Vora', _t(21, 11, 30), status: _done),
      _v('Harish', 'Menon', _t(21, 12, 10), status: _done),
      _v('Shalini', 'Rao', _t(21, 12, 30), status: _done),
      _v('Vinod', 'Pillai', _t(21, 17, 0), status: _done),
      _v('Anita', 'Kamat', _t(21, 17, 40), status: _done),
      _v('Farhan', 'Khan', _t(21, 18, 20), status: _done),
      // Tue 22: 11 seen, 1 missed.
      _v('Rekha', 'Iyer', _t(22, 9, 30), status: _done),
      _v('Sagar', 'More', _t(22, 9, 50), status: _done),
      _v('Leena', 'Dsouza', _t(22, 10, 10), status: _done),
      _v('Tushar', 'Naik', _t(22, 10, 50), status: _done),
      _v('Manisha', 'Jain', _t(22, 11, 10), status: _done),
      _v('Prakash', 'Sawant', _t(22, 11, 30), status: _done),
      _v('Zoya', 'Ansari', _t(22, 11, 50), status: _missed),
      _v('Kishore', 'Pandit', _t(22, 12, 30), status: _done),
      _v('Gauri', 'Bhide', _t(22, 12, 50), status: _done),
      _v('Nitin', 'Salvi', _t(22, 17, 0), status: _done),
      _v('Asha', 'Mehta', _t(22, 17, 20), status: _done),
      _v('Rajiv', 'Kapoor', _t(22, 18, 0), status: _done),
      // Wed 23 (today, 11:48): 5 seen, Vikram in consultation, Kavya and
      // Mohammed waiting (see [weekQueue]), 5 still to come.
      _v('Priya', 'Nair', _t(23, 9, 30), status: _done, reason: 'Fever'),
      _v('Rahul', 'Verma', _t(23, 9, 50), status: _done, reason: 'Follow-up'),
      _v('Fatima', 'Shaikh', _t(23, 10, 15), status: _done, reason: 'BP review'),
      _v('Arjun', 'Pawar', _t(23, 10, 40), status: _done, reason: 'Cough'),
      _v('Sunita', 'Joshi', _t(23, 11, 5), status: _done, reason: 'Diabetes review'),
      _v('Vikram', 'Singh', _t(23, 11, 30), reason: 'Back pain'),
      _v('Kavya', 'Iyer', _t(23, 11, 50), reason: 'Migraine'),
      _v('Mohammed', 'Ali', _t(23, 12, 10), reason: 'Viral fever'),
      _v('Lakshmi', 'Reddy', _t(23, 12, 30), reason: 'Thyroid review'),
      _v('Rohan', 'Mehta', _t(23, 12, 50), reason: 'Skin rash'),
      _v('Sneha', 'Kulkarni', _t(23, 17, 0), reason: 'Follow-up'),
      _v('Anil', 'Gupta', _t(23, 17, 30), reason: 'Acidity'),
      _v('Farah', 'Khan', _t(23, 18, 10), reason: 'Cold'),
      // Thu 24: 9 booked (the Month day panel).
      _v('Deepak', 'Shetty', _t(24, 9, 30), reason: 'Gastritis · Follow-up'),
      _v('Nisha', 'Kapoor', _t(24, 9, 50), reason: 'Fever'),
      _v('Suresh', 'Iyer', _t(24, 10, 10), reason: 'BP review'),
      _v('Aarti', 'Pawar', _t(24, 10, 30), reason: 'Thyroid review'),
      _v('Karan', 'Malhotra', _t(24, 10, 50), reason: 'Cough'),
      _v('Sunil', 'Rao', _t(24, 11, 30), reason: 'Diabetes review'),
      _v('Meenal', 'Gokhale', _t(24, 12, 10), reason: 'Back pain'),
      _v('Imran', 'Sheikh', _t(24, 17, 0), reason: 'Viral fever · Follow-up'),
      _v('Pooja', 'Nair', _t(24, 17, 40), reason: 'Migraine'),
      // Fri 25: 6 booked.
      _v('Sonal', 'Mhatre', _t(25, 9, 30)),
      _v('Yusuf', 'Qureshi', _t(25, 10, 10)),
      _v('Bhavna', 'Shah', _t(25, 11, 0)),
      _v('Omkar', 'Jadhav', _t(25, 12, 0)),
      _v('Pallavi', 'Rane', _t(25, 17, 20)),
      _v('Sameer', 'Kadam', _t(25, 18, 0)),
      // Sat 26: 18 booked, one unsorted overlap at 11:50.
      _v('Tanvi', 'Gore', _t(26, 9, 30)),
      _v('Hemant', 'Rane', _t(26, 9, 50)),
      _v('Shreya', 'Bapat', _t(26, 10, 10)),
      _v('Arvind', 'Nair', _t(26, 10, 30)),
      _v('Kiran', 'Bhosale', _t(26, 10, 50)),
      _v('Mahesh', 'Kulkarni', _t(26, 11, 10)),
      _v('Divya', 'Patil', _t(26, 11, 30)),
      _v('Rohit', 'Sharma', _t(26, 11, 50)),
      _v('Seema', 'Deshmukh', _t(26, 11, 50)),
      _v('Vikas', 'Thakur', _t(26, 12, 30)),
      _v('Nandini', 'Rao', _t(26, 12, 50)),
      _v('Sanjay', 'Mane', _t(26, 13, 10)),
      _v('Heena', 'Shaikh', _t(26, 17, 0)),
      _v('Kunal', 'Dixit', _t(26, 17, 20)),
      _v('Rupali', 'Gawde', _t(26, 17, 40)),
      _v('Ajay', 'Chavan', _t(26, 18, 0)),
      _v('Mitali', 'Sen', _t(26, 18, 20)),
      _v('Parag', 'Joshi', _t(26, 18, 40)),
    ];

const List<(String, String)> _pool = [
  ('Aditi', 'Kale'), ('Bharat', 'Lele'), ('Chitra', 'Mane'),
  ('Dinesh', 'Parab'), ('Esha', 'Rege'), ('Gopal', 'Sathe'),
  ('Hema', 'Tambe'), ('Ishaan', 'Udeshi'), ('Jyoti', 'Vaidya'),
  ('Kedar', 'Wagh'), ('Lata', 'Apte'), ('Manoj', 'Bendre'),
  ('Nalini', 'Chitale'), ('Om', 'Dalvi'), ('Pradnya', 'Ekbote'),
  ('Rashmi', 'Phadke'), ('Sachin', 'Gadgil'), ('Tejas', 'Hegde'),
  ('Uma', 'Inamdar'), ('Varsha', 'Jog'),
];

/// Morning 9:30 onwards every 20 minutes (11 slots to 12:50), then the
/// evening from 5:00 PM.
DateTime _slot(int day, int i) => i < 11
    ? _t(day, 9, 30).add(Duration(minutes: 20 * i))
    : _t(day, 17, 0).add(Duration(minutes: 20 * (i - 11)));

List<Visit> _fill(int day, int count, VisitStatus status) => [
      for (var i = 0; i < count; i++)
        _v(
          _pool[(day * 7 + i) % _pool.length].$1,
          _pool[(day * 7 + i) % _pool.length].$2,
          _slot(day, i),
          status: status,
        ),
    ];

/// The rest of September from the Month mock-up (Sundays empty).
List<Visit> _restOfMonth() => [
      for (final (day, n) in const [
        (1, 12), (2, 13), (3, 11), (4, 10), (5, 15),
        (7, 12), (8, 11), (9, 12), (10, 10), (11, 11), (12, 16),
        (14, 13), (15, 12), (16, 11), (17, 11), (18, 10), (19, 15),
      ])
        ..._fill(day, n, _done),
      for (final (day, n) in const [(28, 5), (29, 3), (30, 2)])
        ..._fill(day, n, _booked),
    ];

/// Every visit for the Week and Month goldens.
final List<Visit> weekVisits = [..._week(), ..._restOfMonth()];

/// Every patient those visits reference (built while making them).
List<Patient> get weekPatients {
  // Reading the visits first makes sure every patient has been built.
  if (weekVisits.isEmpty) return const [];
  return _patients.values.toList();
}

String _visitId(String first, String last, int day) => weekVisits
    .firstWhere((v) =>
        v.patientId == _p(first, last) && v.scheduledStart.day == day)
    .id;

QueueEntry _q(
  String first,
  String last,
  int token,
  QueueStatus status,
  DateTime checkedIn,
) =>
    QueueEntry(
      id: 'wq_$token',
      patientId: _p(first, last),
      tokenNumber: token,
      queueDate: '2026-09-23',
      status: status,
      checkedInAt: checkedIn,
      linkedVisitId: _visitId(first, last, 23),
      createdAt: checkedIn,
      updatedAt: checkedIn,
    );

/// Today's queue: Vikram in consultation, Kavya and Mohammed waiting.
List<QueueEntry> get weekQueue => [
      _q('Vikram', 'Singh', 6, QueueStatus.inConsultation, _t(23, 11, 22)),
      _q('Kavya', 'Iyer', 7, QueueStatus.waiting, _t(23, 11, 40)),
      _q('Mohammed', 'Ali', 8, QueueStatus.waiting, _t(23, 11, 45)),
    ];
