import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Waiting · 8 min", "In consultation", "Booked", "Seen", "Missed".
class ApptStatusPill extends StatelessWidget {
  const ApptStatusPill({super.key, required this.item});

  final ApptItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (String text, Color bg, Color fg, CruIconData? icon) =
        switch (item.status) {
      ApptStatus.waiting => (
          item.waitMinutes == null
              ? 'Waiting'
              : 'Waiting · ${item.waitMinutes} min',
          c.amberTint,
          c.amberText,
          CruIcons.clock,
        ),
      ApptStatus.inConsultation => (
          'In consultation',
          c.accentTint,
          c.accentText,
          null,
        ),
      ApptStatus.booked => ('Booked', c.inset, c.label2, null),
      ApptStatus.done => ('Seen', c.greenTint, c.greenText, CruIcons.check),
      ApptStatus.missed => ('Missed', c.inset, c.label3, null),
    };
    return CruPill(text: text, background: bg, foreground: fg, icon: icon);
  }
}
