import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_doctors_provider.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';

/// A doctor's block colours: a soft pastel fill with a deeper shade of the
/// same hue for the text, so the block reads as one colour.
class DoctorTint {
  const DoctorTint({required this.fill, required this.text});

  final Color fill;
  final Color text;
}

/// One colour per doctor for the Day and Week blocks, so a glance at the
/// schedule shows whose patient is whose. Hues stay clear of the ones that
/// already mean something (red safety, amber waiting, green done, violet AI,
/// blue now).
abstract final class ApptDoctorTints {
  /// ((light fill, light text), (dark fill, dark text)), in the order
  /// doctors get them.
  static const List<((Color, Color), (Color, Color))> _palette = [
    (
      (Color(0xFFF8BFD0), Color(0xFF8A1E45)),
      (Color(0xFF5A2638), Color(0xFFF6B9CC)),
    ), // rose
    (
      (Color(0xFFB8E4DC), Color(0xFF14574F)),
      (Color(0xFF1F4A45), Color(0xFFA9E3D9)),
    ), // teal
    (
      (Color(0xFFF7CDB5), Color(0xFF7A3A17)),
      (Color(0xFF553623), Color(0xFFF2C3A6)),
    ), // clay
    (
      (Color(0xFFBFE3EE), Color(0xFF195468)),
      (Color(0xFF1F4655), Color(0xFFAEDDEB)),
    ), // mist
    (
      (Color(0xFFD3E3B3), Color(0xFF3F5A14)),
      (Color(0xFF3A4A22), Color(0xFFCBE0A6)),
    ), // moss
    (
      (Color(0xFFD9D6D0), Color(0xFF4A4741)),
      (Color(0xFF3D3B38), Color(0xFFD6D3CD)),
    ), // stone
  ];

  static DoctorTint at(int index, Brightness brightness) {
    final pair = _palette[index % _palette.length];
    final (fill, text) = brightness == Brightness.dark ? pair.$2 : pair.$1;
    return DoctorTint(fill: fill, text: text);
  }
}

/// Each doctor's place in the colour order, empty when the clinic has one
/// doctor (nothing to tell apart).
final apptDoctorIndexProvider = Provider<Map<String, int>>((ref) {
  final doctors = ref.watch(clinicDoctorsProvider).value ?? const [];
  if (doctors.length < 2) return const {};
  return {for (var i = 0; i < doctors.length; i++) doctors[i].uid: i};
});

/// The colours for [item]'s doctor, or null (one doctor, or not recorded).
DoctorTint? apptDoctorTint(BuildContext context, WidgetRef ref, ApptItem item) {
  final uid = item.visit.attendingDoctorUid;
  if (uid.isEmpty) return null;
  final i = ref.watch(apptDoctorIndexProvider)[uid];
  if (i == null) return null;
  return ApptDoctorTints.at(i, Theme.of(context).brightness);
}
