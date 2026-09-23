import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/cru_colors.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';

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

  static ApptStatusStyle of(ApptStatus status, CruColors c) {
    return switch (status) {
      ApptStatus.done => ApptStatusStyle(
          fill: c.inset,
          text: c.label2,
          subText: c.label2,
          check: true,
        ),
      ApptStatus.missed => ApptStatusStyle(
          fill: c.inset,
          text: c.label3,
          subText: c.label3,
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
          fill: c.surface,
          border: c.hairline,
          text: c.label,
          subText: c.label2,
        ),
    };
  }
}
