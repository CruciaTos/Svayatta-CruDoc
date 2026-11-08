import 'package:doctor_management_app/features/patients/data/models/patient.dart';

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// An existing patient with the same phone (last 10 digits), or null.
Patient? duplicateByPhone(List<Patient> existing, String phone) {
  final d = _digits(phone);
  if (d.length < 7) return null;
  final tail = d.length > 10 ? d.substring(d.length - 10) : d;
  for (final p in existing) {
    final e = _digits(p.phone);
    if (e.length >= 7 && e.endsWith(tail)) return p;
  }
  return null;
}

