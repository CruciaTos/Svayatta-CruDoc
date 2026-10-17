import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/features/team/presentation/team_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Lets the clinic owner decide whether people holding the Admin role may
/// open patient clinical records.
///
/// Running a clinic and treating its patients are separate kinds of
/// authority: a practice manager needs staff, seats, billing and settings,
/// and none of that requires a diagnosis. Admins therefore start with no
/// clinical access and the owner grants it deliberately.
///
/// Only the owner sees this, and only the owner may change it (the server
/// refuses anyone else and records both outcomes in the activity log).
/// Shown to nobody in a clinic with no admins other than the owner, since
/// there would be nothing for it to affect.
class AdminClinicalAccessCard extends ConsumerStatefulWidget {
  const AdminClinicalAccessCard({
    super.key,
    required this.me,
    required this.clinic,
    required this.members,
  });

  final ClinicAccess me;
  final Clinic clinic;
  final List<ClinicMember> members;

  @override
  ConsumerState<AdminClinicalAccessCard> createState() =>
      _AdminClinicalAccessCardState();
}

class _AdminClinicalAccessCardState
    extends ConsumerState<AdminClinicalAccessCard> {
  bool _saving = false;
  String? _error;

  /// Admins other than the owner: the people this setting actually governs.
  List<ClinicMember> get _delegatedAdmins => widget.members
      .where((m) => m.active && !m.isOwner && m.roleId == 'admin')
      .toList();

  Future<void> _set(bool enabled) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ClinicTeamApi.instance.setAdminClinicalAccess(
        clinicId: widget.clinic.id,
        enabled: enabled,
      );
      // The clinic document drives both the rules and this card, and the
      // signed-in person's own permissions are derived from it too.
      await ClinicSession.instance.reload();
    } on ClinicTeamException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmAndGrant() async {
    final admins = _delegatedAdmins;
    final who = admins.length == 1
        ? admins.first.name.isEmpty
              ? 'one admin'
              : admins.first.name
        : '${admins.length} admins';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final c = context.cru;
        return CruFormDialog(
          title: 'Let admins open clinical records?',
          submitLabel: 'Grant access',
          onSubmit: () => Navigator.of(context).pop(true),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$who will be able to read and write every patient\'s '
                'clinical records in this clinic, including notes, diagnoses '
                'and prescriptions.',
                style: CruType.text.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s8),
              Text(
                'Only grant this to people who take part in clinical care. '
                'The change is recorded in the activity log.',
                style: CruType.caption.tint(c.label3),
              ),
            ],
          ),
        );
      },
    );
    if (ok == true) await _set(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;

    // Not the owner's to change, and nothing to change it for.
    if (!widget.me.isOwner) return const SizedBox.shrink();
    final admins = _delegatedAdmins;
    if (admins.isEmpty) return const SizedBox.shrink();

    final on = widget.clinic.adminClinicalAccess;
    final names = admins
        .map((m) => m.name.isEmpty ? 'Unnamed' : m.name)
        .join(', ');

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
              Text('Clinical records', style: CruType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s4),
              Text(
                'Admins manage your team, billing and settings. Opening '
                'patient records is separate.',
                style: CruType.text.tint(c.label2),
              ),
            ],
          ),
        ),
        CheckListCard(
          items: [
            CheckItem(
              label: 'Admins can open clinical records',
              detail: on
                  ? 'On · $names can read and write clinical records'
                  : 'Off · $names can manage the clinic but not open records',
              checked: on,
              enabled: !_saving,
              onToggle: _saving ? null : () => on ? _set(false) : _confirmAndGrant(),
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
