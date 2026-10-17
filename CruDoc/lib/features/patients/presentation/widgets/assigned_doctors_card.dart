import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_doctors_provider.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/features/team/presentation/team_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Which doctors treat this patient, in a clinic that scopes its doctors to
/// the patients they treat.
///
/// Hidden entirely in a clinic-wide clinic (the default), where assignment
/// means nothing: showing a control with no effect would be worse than
/// showing none. Changing it needs `patients.edit`, so the front desk can
/// assign a walk-in to whoever is about to see them.
class AssignedDoctorsCard extends ConsumerStatefulWidget {
  const AssignedDoctorsCard({
    super.key,
    required this.patientId,
    required this.assignedDoctorUids,
  });

  final String patientId;
  final List<String> assignedDoctorUids;

  @override
  ConsumerState<AssignedDoctorsCard> createState() =>
      _AssignedDoctorsCardState();
}

class _AssignedDoctorsCardState extends ConsumerState<AssignedDoctorsCard> {
  bool _saving = false;
  String? _error;

  /// Null until the first edit; then the set being saved.
  Set<String>? _pending;

  Set<String> get _current =>
      _pending ?? widget.assignedDoctorUids.toSet();

  Future<void> _toggle(String uid) async {
    if (_saving) return;
    final next = {..._current};
    if (!next.remove(uid)) next.add(uid);

    setState(() {
      _pending = next;
      _saving = true;
      _error = null;
    });

    final clinicId = ClinicSession.instance.access?.clinicId;
    if (clinicId == null) {
      setState(() {
        _saving = false;
        _pending = null;
      });
      return;
    }

    try {
      await ClinicTeamApi.instance.assignPatient(
        clinicId: clinicId,
        patientId: widget.patientId,
        doctorUids: next.toList(),
      );
    } on ClinicTeamException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          // Put the control back where it was: the server refused.
          _pending = null;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final access = ref.watch(clinicAccessProvider).value;

    // Only meaningful where the clinic scopes doctors to their own patients.
    if (access == null || access.clinicalAccessScope != 'assigned') {
      return const SizedBox.shrink();
    }

    final doctors = (ref.watch(clinicDoctorsProvider).value ?? const [])
        .where((d) => d.active)
        .toList();
    if (doctors.isEmpty) return const SizedBox.shrink();

    // A doctor confined to their own patients sees who is assigned but cannot
    // change it: the server refuses them (otherwise they could assign
    // themselves to anyone), so the controls are not offered.
    final canEdit = access.can(ClinicPermission.patientsEdit) &&
        !access.scopedToAssignedPatients;
    final assigned = _current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s4,
            0,
            CruSpace.s4,
            CruSpace.s8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Treating doctors', style: CruType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s4),
              Text(
                assigned.isEmpty
                    ? 'Not assigned. Every doctor in the clinic can open this '
                          'patient until someone is.'
                    : 'Only these doctors can open this patient.',
                style: CruType.text.tint(c.label2),
              ),
              if (access.scopedToAssignedPatients) ...[
                const SizedBox(height: CruSpace.s4),
                Text(
                  'Assigned by the front desk or the clinic owner.',
                  style: CruType.caption.tint(c.label3),
                ),
              ],
            ],
          ),
        ),
        CheckListCard(
          items: [
            for (final d in doctors)
              CheckItem(
                label: d.name.isEmpty ? 'Unnamed doctor' : d.name,
                detail: [
                  if (d.isOwner) 'Owner',
                  if (d.specialty.isNotEmpty) d.specialty,
                ].join(' · '),
                checked: assigned.contains(d.uid),
                enabled: canEdit && !_saving,
                onToggle: canEdit && !_saving ? () => _toggle(d.uid) : null,
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: CruSpace.s8),
          Text(_error!, style: CruType.caption.tint(c.redText)),
        ],
      ],
    );
  }
}
