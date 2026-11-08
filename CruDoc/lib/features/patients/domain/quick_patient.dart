import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// A patient made from just a name (and maybe a phone), to hold a booking or
/// a token now and fill in the rest later.
Patient quickPatient(String name, {String phone = ''}) {
  final parts = name.trim().split(RegExp(r'\s+'));
  final now = DateTime.now();
  return Patient(
    id: '',
    firstName: parts.first,
    lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
    phone: phone.trim(),
    gender: '',
    dateOfBirth: DateTime(now.year - 30, 1, 1),
    diagnosis: const [],
    notes: 'Added quickly. Details to be completed.',
    packageBalance: 0,
    isArchived: false,
    createdAt: now,
    updatedAt: now,
  );
}

/// Phone missing: the record still needs filling in.
bool patientDetailsPending(Patient p) => p.phone.trim().isEmpty;

