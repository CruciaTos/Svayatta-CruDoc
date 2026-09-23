import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_actions.dart';

/// Long-press (touch and stylus, with a haptic tick) or right-click
/// (mouse) on an appointment opens its actions where the finger or
/// pointer is: open, reschedule, directions, open patient, cancel. Taps
/// still go to [child].
class ApptContextRegion extends ConsumerWidget {
  const ApptContextRegion({super.key, required this.item, required this.child});

  final ApptItem item;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (d) {
        HapticFeedback.mediumImpact();
        ApptActions.showActionsMenu(context, ref, item, d.globalPosition);
      },
      onSecondaryTapUp: (d) =>
          ApptActions.showActionsMenu(context, ref, item, d.globalPosition),
      child: child,
    );
  }
}
