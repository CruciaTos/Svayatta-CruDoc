import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/cru_colors.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/appt_doctor_tint.dart';

/// The one mapping from [ApptStatus] to block colours, used by the Day
/// grid, the Week grid and overlap blocks.
class ApptStatusStyle {
  const ApptStatusStyle({
    required this.fill,
    required this.text,
    required this.subText,
    this.border,
    this.strike = false,
    this.check = false,
  });

  final Color fill;

  /// Hairline around booked blocks; null otherwise.
  final Color? border;

  /// Name and time colour.
  final Color text;

  /// Reason colour.
  final Color subText;

  /// Missed: strikethrough name.
  final bool strike;

  /// Done: green check before the name.
  final bool check;

  /// [tint] is the doctor's colour: a pastel fill with a deeper shade of
  /// the same hue for the text. It replaces the neutral look of booked,
  /// done and missed blocks (waiting and in-consultation keep their own
  /// colours, which mean something).
  static ApptStatusStyle of(
    ApptStatus status,
    CruColors c, {
    DoctorTint? tint,
  }) {
    return switch (status) {
      ApptStatus.done => ApptStatusStyle(
        fill: tint?.fill ?? c.inset,
        text: tint?.text ?? c.label2,
        subText: tint?.text.withValues(alpha: 0.75) ?? c.label2,
        check: true,
      ),
      ApptStatus.missed => ApptStatusStyle(
        fill: tint?.fill ?? c.inset,
        text: tint?.text.withValues(alpha: 0.6) ?? c.label3,
        subText: tint?.text.withValues(alpha: 0.5) ?? c.label3,
        strike: true,
      ),
      ApptStatus.inConsultation => ApptStatusStyle(
        fill: c.accentTint,
        text: c.accentText,
        subText: c.accentText,
      ),
      ApptStatus.waiting => ApptStatusStyle(
        fill: c.amberTint,
        text: c.amberText,
        subText: c.amberText,
      ),
      ApptStatus.booked => ApptStatusStyle(
        fill: tint?.fill ?? c.surface,
        border: tint == null ? c.hairline : null,
        text: tint?.text ?? c.label,
        subText: tint?.text.withValues(alpha: 0.75) ?? c.label2,
      ),
    };
  }
}
