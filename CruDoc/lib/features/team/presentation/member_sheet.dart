import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/team/presentation/features_checklist.dart';
import 'package:doctor_management_app/features/team/presentation/team_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

Future<void> showMemberDialog(BuildContext context, ClinicMember member) =>
    showDialog<void>(
      context: context,
      builder: (_) => MemberDialog(member: member),
    );

/// Someone else in the clinic: their role, doctor or staff, specialty and
/// features, or remove them.
class MemberDialog extends ConsumerStatefulWidget {
  const MemberDialog({super.key, required this.member});

  final ClinicMember member;

  @override
  ConsumerState<MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends ConsumerState<MemberDialog> {
  late String _roleId = widget.member.roleId;
  late MemberKind _kind = widget.member.kind;
  late DoctorSpecialty? _specialty = widget.member.specialty.isEmpty
      ? null
      : DoctorSpecialty.fromString(widget.member.specialty);
  late Set<String>? _modules = widget.member.modules?.toSet();
  bool _busy = false;
  String? _notice;

  bool get _dirty =>
      _roleId != widget.member.roleId ||
      _kind != widget.member.kind ||
      (_specialty?.label ?? '') != widget.member.specialty ||
      !_sameModules(_modules, widget.member.modules?.toSet());

  static bool _sameModules(Set<String>? a, Set<String>? b) =>
      a == null || b == null
      ? a == b
      : a.length == b.length && a.containsAll(b);

  Future<void> _save() async {
    final clinicId = ref.read(clinicAccessProvider).value?.clinicId;
    if (clinicId == null) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    final m = widget.member;
    try {
      await ClinicTeamApi.instance.updateMember(
        clinicId: clinicId,
        uid: m.uid,
        roleId: _roleId != m.roleId ? _roleId : null,
        kind: _kind != m.kind ? _kind : null,
        specialty: (_specialty?.label ?? '') != m.specialty
            ? (_specialty?.label ?? '')
            : null,
        modules: _modules?.toList(),
        clearModules: _modules == null && m.modules != null,
      );
      if (mounted) Navigator.of(context).pop();
    } on ClinicTeamException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final clinicId = ref.read(clinicAccessProvider).value?.clinicId;
    final m = widget.member;
    if (clinicId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => PatientDialog(
        title: 'Remove ${m.name} from the clinic?',
        cancelLabel: 'Keep',
        confirmLabel: 'Remove',
        onConfirm: () => Navigator.of(ctx).pop(true),
        body: Text(
          '${m.name} will be signed out on every device.',
          style: CruType.text.tint(ctx.cru.label2),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ClinicTeamApi.instance.removeMember(clinicId: clinicId, uid: m.uid);
      if (!mounted) return;
      showTeamToast(context, '${m.name} was removed.');
      Navigator.of(context).pop();
    } on ClinicTeamException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final m = widget.member;
    final me = ref.watch(clinicAccessProvider).value;
    final clinic = ref.watch(activeClinicProvider).value;
    final allRoles =
        ref.watch(clinicRolesProvider).value ?? const <ClinicRole>[];
    ClinicRole? current;
    for (final r in allRoles) {
      if (r.id == _roleId) current = r;
    }
    final roles = [
      for (final r in allRoles)
        if (r.id == _roleId || (me != null && canGiveRole(me, r))) r,
    ];
    final available = current == null
        ? const <String>[]
        : choosableModules(clinic, current);

    return CruFormDialog(
      title: m.name.isEmpty ? 'Team member' : m.name,
      subtitle: [
        if (m.phone.isNotEmpty) m.phone,
        if (m.email.isNotEmpty) m.email,
      ].join(' · '),
      leading: CruMonogram(
        name: m.name.isEmpty ? '?' : m.name,
        background: c.inset,
        foreground: c.label2,
      ),
      submitLabel: _busy ? 'Saving…' : 'Save',
      busy: _busy,
      dirty: _dirty,
      notice: _notice,
      onSubmit: _save,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruSegmentedControl<MemberKind>(
            segments: const [
              CruSegment(MemberKind.doctor, 'Doctor'),
              CruSegment(MemberKind.staff, 'Staff'),
            ],
            selected: _kind,
            onChanged: (v) => setState(() => _kind = v),
          ),
          const SizedBox(height: CruSpace.s16),
          CruDropdownField<ClinicRole>(
            label: 'Role',
            value: current,
            items: roles,
            itemLabel: (r) => r.name,
            onChanged: (r) => setState(() {
              _roleId = r.id;
              final allowed = choosableModules(clinic, r);
              _modules = _modules?.where(allowed.contains).toSet();
            }),
          ),
          if (_kind == MemberKind.doctor) ...[
            const SizedBox(height: CruSpace.s16),
            CruDropdownField<DoctorSpecialty>(
              label: 'Specialty',
              value: _specialty == null
                  ? null
                  : DoctorSpecialty.all.firstWhere(
                      (s) => s.type == _specialty!.type,
                      orElse: () => _specialty!,
                    ),
              items: DoctorSpecialty.all,
              itemLabel: (s) => s.label,
              onChanged: (s) => setState(() => _specialty = s),
            ),
          ],
          if (available.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s20),
            Text('Features', style: CruType.headline.tint(c.label)),
            const SizedBox(height: CruSpace.s8),
            FeaturesChecklist(
              available: available,
              selected: _modules,
              onChanged: (v) => setState(() => _modules = v),
            ),
          ],
          const SizedBox(height: CruSpace.s20),
          Align(
            alignment: Alignment.centerLeft,
            child: CruCapsuleButton(
              label: 'Remove from clinic',
              onPressed: _busy ? null : _remove,
            ),
          ),
        ],
      ),
    );
  }
}
