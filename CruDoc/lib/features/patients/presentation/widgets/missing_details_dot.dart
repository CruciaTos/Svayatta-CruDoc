import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/domain/patient_completeness.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Small amber dot that says which details a patient still lacks.
class MissingDetailsDot extends StatelessWidget {
  const MissingDetailsDot({super.key, required this.patient});
  final Patient? patient;

  @override
  Widget build(BuildContext context) {
    final p = patient;
    if (p == null) return const SizedBox.shrink();
    final missing = missingDetails(p);
    if (missing.isEmpty) return const SizedBox.shrink();
    final text = 'Details missing: ${missing.join(', ')}';
    return Padding(
      padding: const EdgeInsets.only(left: CruSpace.s8),
      child: Semantics(
        label: text,
        child: Tooltip(
          message: text,
          triggerMode: TooltipTriggerMode.longPress,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.cru.amber,
              shape: BoxShape.circle,
            ),
            child: const SizedBox(width: 8, height: 8),
          ),
        ),
      ),
    );
  }
}
