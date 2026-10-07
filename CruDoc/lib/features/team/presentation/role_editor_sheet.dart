import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/team/presentation/team_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens a role to edit, or a new one when [role] is null.
Future<void> showRoleEditor(BuildContext context, {ClinicRole? role}) =>
    showDialog<void>(
      context: context,
      builder: (_) => RoleEditorDialog(role: role),
    );

/// The groups permissions are listed under, in this order.
const List<String> _kGroups = [
  'Patients',
  'Clinical',
  'Front desk',
  'Money',
  'Stock',
  'Admin',
];

/// Names a staff category and ticks what it may do. The Admin role can do
/// everything and can't be changed.
class RoleEditorDialog extends ConsumerStatefulWidget {
  const RoleEditorDialog({super.key, this.role});

  final ClinicRole? role;

  @override
  ConsumerState<RoleEditorDialog> createState() => _RoleEditorDialogState();
}

class _RoleEditorDialogState extends ConsumerState<RoleEditorDialog> {
  late final _name = TextEditingController(text: widget.role?.name ?? '');
  late MemberKind _kind = widget.role?.kind ?? MemberKind.staff;
  late Set<ClinicPermission> _picked = {...?widget.role?.perms};
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _isAdminRole => widget.role?.id == 'admin';

  Future<void> _save() async {
    final clinicId = ref.read(clinicAccessProvider).value?.clinicId;
    final name = _name.text.trim();
    if (clinicId == null) return;
    if (name.isEmpty) {
      setState(() => _notice = 'Give the role a name.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await ClinicTeamApi.instance.saveRole(
        clinicId: clinicId,
        roleId: widget.role?.id,
        name: name,
        kind: _kind,
        perms: normalizePermissions(_picked.map((p) => p.key)),
      );
      if (mounted) Navigator.of(context).pop();
    } on ClinicTeamException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final clinicId = ref.read(clinicAccessProvider).value?.clinicId;
    final role = widget.role;
    if (clinicId == null || role == null) return;
    setState(() => _busy = true);
    try {
      await ClinicTeamApi.instance.deleteRole(
        clinicId: clinicId,
        roleId: role.id,
      );
      if (!mounted) return;
      showTeamToast(context, '${role.name} was deleted.');
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
    final me = ref.watch(clinicAccessProvider).value;
    final role = widget.role;

    if (_isAdminRole) {
      return CruFormDialog(
        title: 'Admin',
        submitLabel: 'Done',
        cancelLabel: 'Close',
        onSubmit: () => Navigator.of(context).pop(),
        body: Text(
          'Can do everything, including managing the team and clinic '
          'settings. Only the owner or another admin can give this role.',
          style: CruType.text.tint(c.label2),
        ),
      );
    }

    // Someone without admin rights can't edit a role that holds more than
    // they do (the server refuses it), so it opens read-only.
    final readOnly =
        role != null && me != null && !canGiveRole(me, role) && !me.isAdmin;
    bool canGive(ClinicPermission p) =>
        me != null &&
        (me.isAdmin || (p != ClinicPermission.team && me.perms.contains(p)));

    final effective = normalizePermissions(_picked.map((p) => p.key));
    bool impliedByOthers(ClinicPermission p) => normalizePermissions(
      _picked.where((q) => q != p).map((q) => q.key),
    ).contains(p);

    final members = ref.watch(clinicMembersProvider).value ?? const [];
    final invites = ref.watch(clinicInvitesProvider).value ?? const [];
    final inUse =
        role != null &&
        (members.any((m) => m.active && m.roleId == role.id) ||
            invites.any((i) => i.roleId == role.id));

    return CruFormDialog(
      title: role == null ? 'New role' : role.name,
      subtitle: readOnly
          ? 'This role can do things you can\'t, so only an admin can change it.'
          : 'Tick what people in this role may do.',
      submitLabel: readOnly ? 'Done' : (_busy ? 'Saving…' : 'Save'),
      cancelLabel: readOnly ? 'Close' : 'Cancel',
      busy: _busy,
      notice: _notice,
      onSubmit: readOnly ? () => Navigator.of(context).pop() : _save,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruTextField(
            label: 'Name',
            controller: _name,
            hint: 'Lab technician',
            enabled: !readOnly,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: CruSpace.s16),
          CruSegmentedControl<MemberKind>(
            segments: const [
              CruSegment(MemberKind.doctor, 'For doctors'),
              CruSegment(MemberKind.staff, 'For staff'),
            ],
            selected: _kind,
            onChanged: readOnly ? (_) {} : (v) => setState(() => _kind = v),
          ),
          for (final group in _kGroups) ...[
            const SizedBox(height: CruSpace.s20),
            Text(group, style: CruType.headline.tint(c.label)),
            const SizedBox(height: CruSpace.s8),
            CheckListCard(
              items: [
                for (final p in ClinicPermission.values)
                  if (p.group == group)
                    CheckItem(
                      label: p.label,
                      checked: effective.contains(p),
                      enabled: !readOnly && canGive(p) && !impliedByOthers(p),
                      onToggle: () => setState(() {
                        if (!_picked.remove(p)) _picked.add(p);
                      }),
                    ),
              ],
            ),
          ],
          if (role != null && !readOnly) ...[
            const SizedBox(height: CruSpace.s20),
            Row(
              children: [
                CruCapsuleButton(
                  label: 'Delete role',
                  onPressed: inUse || _busy ? null : _delete,
                ),
                if (inUse) ...[
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Text(
                      'Someone has this role or an invite for it. '
                      'Give them another role first.',
                      style: CruType.caption.tint(c.label3),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
