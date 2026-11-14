import 'package:doctor_management_app/features/patients/data/models/patient.dart';

const dobMissingNote = 'Date of birth not in the imported file';

/// True when [p]'s date of birth is a placeholder (the registration day, or
/// flagged by the importer).
bool dobIsPlaceholder(Patient p) {
  final d = p.dateOfBirth;
  final c = p.createdAt;
  return (d.year == c.year && d.month == c.month && d.day == c.day) ||
      p.notes.contains(dobMissingNote);
}

/// Human labels for the details a patient still lacks (empty when complete).
List<String> missingDetails(Patient p) {
  final digits = p.phone.replaceAll(RegExp(r'\D'), '');
  final g = p.gender.trim().toLowerCase();
  return [
    if (digits.length < 10) 'phone',
    if (g.isEmpty || g == 'unknown') 'gender',
    if (dobIsPlaceholder(p)) 'date of birth',
  ];
}
