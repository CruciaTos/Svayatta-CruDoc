import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';

/// Text formats used across the Appointments screens.
abstract final class ApptFormat {
  /// "9:30" (block times, now pill).
  static String clock(DateTime t) => DateFormat('h:mm').format(t);

  /// "9:30 AM".
  static String time(DateTime t) => DashFormat.time(t);

  /// "5:30 to 6:00" inside a block.
  static String blockRange(DateTime a, DateTime b) => '${clock(a)} to ${clock(b)}';

  /// "11:50 AM to 12:10 PM", "12:30 to 12:50 PM".
  static String range(DateTime a, DateTime b) => DashFormat.timeRange(a, b);

  /// "Wednesday, 23 September".
  static String dateLine(DateTime t) => DashFormat.dateLine(t);

  /// "9 AM", "12 PM" for hour labels.
  static String hour(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12 ${h < 12 || h == 24 ? 'AM' : 'PM'}';
  }

  /// "Booked 20 Sep" / "Booked today 10:52 AM", as two lines.
  static (String, String) booked(DateTime createdAt, DateTime now) {
    if (ApptsBuilder.sameDay(createdAt, now)) {
      return ('Booked today', time(createdAt));
    }
    return ('Booked', DashFormat.shortDate(createdAt));
  }

  /// Age in whole years at [now] (the screen's clock, so tests are stable).
  static int ageAt(DateTime dob, DateTime now) {
    var years = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years < 0 ? 0 : years;
  }

  /// "23 y · Female · Returning · Token 7". Parts with no data are left out.
  static String identityLine(ApptItem item, DateTime now) {
    final p = item.patient;
    final parts = <String>[
      if (p != null) '${ageAt(p.dateOfBirth, now)} y',
      if (p != null && p.gender.trim().isNotEmpty) _sentence(p.gender.trim()),
      item.isNewPatient ? 'New' : 'Returning',
      if (item.tokenNumber != null) 'Token ${item.tokenNumber}',
    ];
    return parts.join(' · ');
  }

  /// "She" / "He" / "They" from the patient's recorded gender.
  static String pronoun(ApptItem item) {
    final g = item.patient?.gender.trim().toLowerCase() ?? '';
    if (g == 'female' || g == 'f') return 'She';
    if (g == 'male' || g == 'm') return 'He';
    return 'They';
  }

  static String _sentence(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';

  /// "1 overlap" / "2 overlaps".
  static String overlaps(int n) => DashFormat.plural(n, 'overlap');
}
