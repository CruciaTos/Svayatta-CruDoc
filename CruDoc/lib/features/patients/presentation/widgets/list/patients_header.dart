import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Patients" large title with "248 patients · 18 new this month", and
/// Import / Export (secondary) + Add patient (the one filled button).
class PatientsHeader extends ConsumerWidget {
  const PatientsHeader({
    super.key,
    required this.total,
    required this.newThisMonth,
  });

  /// Null while loading (the subtitle keeps its height).
  final int? total;
  final int newThisMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final subtitle = total == null
        ? null
        : PatientFormat.headerLine(total!, newThisMonth);

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: CruSpace.s24,
      runSpacing: CruSpace.s12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text('Patients', style: CruType.largeTitle.tint(c.label)),
            ),
            const SizedBox(height: CruSpace.s2),
            SizedBox(
              height: CruType.text.fontSize! * CruType.text.height!,
              child: subtitle == null
                  ? null
                  : Text(
                      subtitle,
                      style: CruType.text.tabular.tint(c.label2),
                      maxLines: 1,
                    ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CruButton(
              label: 'Import / Export',
              kind: CruButtonKind.secondary,
              icon: CruIcons.importExport,
              onPressed: () => PatientActions.importUnavailable(context),
            ),
            const SizedBox(width: CruSpace.s10),
            CruButton(
              label: 'Add patient',
              icon: CruIcons.plus,
              onPressed: () => PatientActions.addPatient(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}
