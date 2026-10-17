import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// `assignedDoctorUids` crosses three representations: a Firestore array, a
/// JSON string in the SQLite column, and a Dart list. A patient that loses
/// its assignment in transit would silently widen who can reach them, so the
/// conversions are pinned here.
void main() {
  Patient build({List<String> assigned = const []}) => Patient(
    id: 'p1',
    doctorId: 'clinic-1',
    firstName: 'Alice',
    lastName: 'Smith',
    phone: '+919876543210',
    gender: 'female',
    dateOfBirth: DateTime(1990, 5, 20),
    diagnosis: const [],
    packageBalance: 0,
    isArchived: false,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 2),
    assignedDoctorUids: assigned,
  );

  group('assignedToStored', () {
    test('an empty list becomes an empty string, not "[]"', () {
      // The column is NOT NULL with a '' default, so empty has to be ''.
      expect(Patient.assignedToStored(const []), equals(''));
    });

    test('encodes a list as JSON', () {
      expect(Patient.assignedToStored(['a', 'b']), equals(jsonEncode(['a', 'b'])));
    });

    test('trims, drops blanks and de-duplicates', () {
      expect(
        Patient.assignedFromStored(
          Patient.assignedToStored([' a ', 'a', '', '  ', 'b']),
        ),
        equals(['a', 'b']),
      );
    });
  });

  group('assignedFromStored', () {
    test('reads a Firestore array', () {
      expect(Patient.assignedFromStored(['a', 'b']), equals(['a', 'b']));
    });

    test('reads the JSON string SQLite holds', () {
      expect(Patient.assignedFromStored('["a","b"]'), equals(['a', 'b']));
    });

    test('treats empty, null and whitespace as nobody assigned', () {
      for (final v in [null, '', '   ', <String>[]]) {
        expect(Patient.assignedFromStored(v), isEmpty,
            reason: 'input: ${jsonEncode(v)}');
      }
    });

    test('a bare uid that is not JSON is read as a single assignment', () {
      // Defensive: never silently drop an assignment we cannot parse.
      expect(Patient.assignedFromStored('doctor-7'), equals(['doctor-7']));
    });

    test('ignores blanks inside a stored array', () {
      expect(Patient.assignedFromStored(['a', '', ' b ']), equals(['a', 'b']));
    });
  });

  group('the model round trip', () {
    test('toMap carries the assignment to Firestore', () {
      expect(
        build(assigned: ['doc-1', 'doc-2']).toMap()['assignedDoctorUids'],
        equals(['doc-1', 'doc-2']),
      );
    });

    test('toMap always writes the field, so an unassignment is persisted', () {
      // Omitting it on an empty list would leave a stale assignment behind in
      // Firestore and keep a patient scoped to a doctor who was removed.
      final map = build().toMap();
      expect(map.containsKey('assignedDoctorUids'), isTrue);
      expect(map['assignedDoctorUids'], isEmpty);
    });

    test('fromMap reads it back', () {
      final p = Patient.fromMap({
        'doctorId': 'clinic-1',
        'firstName': 'Alice',
        'lastName': 'Smith',
        'phone': '+919876543210',
        'gender': 'female',
        'dateOfBirth': Timestamp.fromDate(DateTime(1990, 5, 20)),
        'assignedDoctorUids': ['doc-1'],
      }, id: 'p1');
      expect(p.assignedDoctorUids, equals(['doc-1']));
    });

    test('a patient document predating the field reads as unassigned', () {
      final p = Patient.fromMap({
        'doctorId': 'clinic-1',
        'firstName': 'Bob',
        'lastName': 'Jones',
        'phone': '+919876543211',
        'gender': 'male',
        'dateOfBirth': Timestamp.fromDate(DateTime(1980, 1, 1)),
      }, id: 'p2');
      expect(p.assignedDoctorUids, isEmpty,
          reason: 'unassigned keeps the patient readable by every doctor');
    });

    test('copyWith can set and clear the assignment', () {
      final assigned = build().copyWith(assignedDoctorUids: ['doc-1']);
      expect(assigned.assignedDoctorUids, equals(['doc-1']));
      expect(
        assigned.copyWith(assignedDoctorUids: const []).assignedDoctorUids,
        isEmpty,
      );
    });

    test('copyWith keeps the assignment when it is not named', () {
      final p = build(assigned: ['doc-1']).copyWith(firstName: 'Alicia');
      expect(p.assignedDoctorUids, equals(['doc-1']));
    });
  });
}
