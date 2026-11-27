import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../domain/abha_profile.dart';

/// Shows the VRFY_ABHA_308 side-by-side comparison when an ABHA profile is
/// already linked to a CruDoc patient. Returns `true` if the user chose
/// "Open patient".
Future<bool?> showAbhaLinkedDialog(
  BuildContext context, {
  required AbhaProfile profile,
  required String patientId,
  Patient? existing,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AbhaLinkedDialog(
      profile: profile,
      patientId: patientId,
      existing: existing,
    ),
  );
}

class _AbhaLinkedDialog extends StatefulWidget {
  const _AbhaLinkedDialog({
    required this.profile,
    required this.patientId,
    this.existing,
  });

  final AbhaProfile profile;
  final String patientId;
  final Patient? existing;

  @override
  State<_AbhaLinkedDialog> createState() => _AbhaLinkedDialogState();
}

class _AbhaLinkedDialogState extends State<_AbhaLinkedDialog> {
  late final Future<Patient?> _patientFuture = widget.existing != null
      ? Future.value(widget.existing)
      : PatientRepository().getPatient(widget.patientId);

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fmt = DateFormat('d MMM yyyy');
    final abhaDob = widget.profile.dateOfBirth != null
        ? fmt.format(widget.profile.dateOfBirth!)
        : '—';

    return PatientDialog(
      title: 'This ABHA profile is already linked to HMIS Beneficiary ID.',
      cancelLabel: 'Close',
      confirmLabel: 'Open patient',
      onConfirm: () => Navigator.of(context).pop(true),
      body: FutureBuilder<Patient?>(
        future: _patientFuture,
        builder: (context, snap) {
          final existing = snap.data;
          final cruDob = existing != null ? fmt.format(existing.dateOfBirth) : '—';
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ABHA', style: CruType.subhead.tint(c.label2)),
                    const SizedBox(height: CruSpace.s4),
                    Text(widget.profile.name, style: CruType.text),
                    Text(abhaDob, style: CruType.caption.tint(c.label2)),
                    Text(
                      widget.profile.gender,
                      style: CruType.caption.tint(c.label2),
                    ),
                    Text(
                      widget.profile.abhaNumber,
                      style: CruType.caption.tabular.tint(c.label2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('CruDoc', style: CruType.subhead.tint(c.label2)),
                    const SizedBox(height: CruSpace.s4),
                    if (snap.connectionState == ConnectionState.waiting &&
                        existing == null)
                      Text('Loading…', style: CruType.caption.tint(c.label2))
                    else if (existing != null) ...[
                      Text(existing.fullName.trim(), style: CruType.text),
                      Text(cruDob, style: CruType.caption.tint(c.label2)),
                      Text(
                        existing.gender,
                        style: CruType.caption.tint(c.label2),
                      ),
                      Text(
                        existing.phone,
                        style: CruType.caption.tabular.tint(c.label2),
                      ),
                    ] else
                      Text(
                        'Patient record unavailable',
                        style: CruType.caption.tint(c.label2),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
