import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/features/dental/dental_features.dart';
import 'package:doctor_management_app/features/dental/presentation/dental_features_picker.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/team/presentation/features_checklist.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _Contact { phone, email }

Future<void> showInviteDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const InviteDialog());

/// Invites a doctor or staff member by phone or email. They join by
/// signing in to CruDoc with that number or address within 7 days.
class InviteDialog extends ConsumerStatefulWidget {
  const InviteDialog({super.key});

  @override
  ConsumerState<InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<InviteDialog> {
  final _name = TextEditingController();
  final _contactValue = TextEditingController();
  _Contact _contact = _Contact.phone;
  MemberKind _kind = MemberKind.staff;
  String? _roleId;
  DoctorSpecialty? _specialty;
  Set<DentalFeature> _dental = DentalFeature.defaults;
  Set<String>? _modules;
  bool _busy = false;
  String? _notice;

  /// Set once the invite is sent: the dialog then says what happens next.
  String? _sentTo;

  @override
  void dispose() {
    _name.dispose();
    _contactValue.dispose();
    super.dispose();
  }

  Future<void> _send(ClinicRole? role) async {
    final clinicId = ref.read(clinicAccessProvider).value?.clinicId;
    final name = _name.text.trim();
    final contact = _contactValue.text.trim();
    if (clinicId == null || role == null) return;
    if (name.isEmpty || contact.isEmpty) {
      setState(() => _notice = 'Add a name and a phone number or email.');
      return;
    }
    if (_kind == MemberKind.doctor && _specialty == null) {
      setState(() => _notice = 'Pick the doctor\'s specialty.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final dentist =
          _kind == MemberKind.doctor &&
          _specialty?.type == DoctorSpecialtyType.dentist;
      await ClinicTeamApi.instance.invite(
        clinicId: clinicId,
        name: name,
        phone: _contact == _Contact.phone ? contact : null,
        email: _contact == _Contact.email ? contact : null,
        kind: _kind,
        roleId: role.id,
        specialty: _kind == MemberKind.doctor ? _specialty?.label : null,
        modules: _modules?.toList(),
        dentalFeatures: dentist ? [for (final f in _dental) f.key] : null,
      );
      if (mounted) setState(() => _sentTo = contact);
    } on ClinicTeamException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (_sentTo != null) {
      final name = _name.text.trim();
      return CruFormDialog(
        title: 'Invite sent',
        submitLabel: 'Done',
        cancelLabel: 'Close',
        onSubmit: () => Navigator.of(context).pop(),
        body: Text(
          'Ask $name to sign in to CruDoc with $_sentTo. '
          'The invite lasts 7 days.',
          style: CruType.text.tint(c.label2),
        ),
      );
    }

    final me = ref.watch(clinicAccessProvider).value;
    final clinic = ref.watch(activeClinicProvider).value;
    final roles = [
      for (final r
          in ref.watch(clinicRolesProvider).value ?? const <ClinicRole>[])
        if (me != null && canGiveRole(me, r)) r,
    ];
    final role = _roleFor(roles);
    final dentist =
        _kind == MemberKind.doctor &&
        _specialty?.type == DoctorSpecialtyType.dentist;
    final available = role == null
        ? const <String>[]
        : choosableModules(clinic, role);

    return CruFormDialog(
      title: 'Invite to your clinic',
      subtitle: 'They join by signing in with this phone number or email.',
      submitLabel: _busy ? 'Sending…' : 'Send invite',
      busy: _busy,
      notice: _notice,
      onSubmit: () => _send(role),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruTextField(
            label: 'Name',
            controller: _name,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: CruSpace.s16),
          CruSegmentedControl<_Contact>(
            segments: const [
              CruSegment(_Contact.phone, 'Phone'),
              CruSegment(_Contact.email, 'Email'),
            ],
            selected: _contact,
            onChanged: (v) => setState(() {
              _contact = v;
              _contactValue.clear();
            }),
          ),
          const SizedBox(height: CruSpace.s12),
          CruTextField(
            label: _contact == _Contact.phone ? 'Phone number' : 'Email',
            controller: _contactValue,
            prefix: _contact == _Contact.phone ? '+91' : null,
            keyboardType: _contact == _Contact.phone
                ? TextInputType.phone
                : TextInputType.emailAddress,
            tabular: _contact == _Contact.phone,
          ),
          const SizedBox(height: CruSpace.s16),
          CruSegmentedControl<MemberKind>(
            segments: const [
              CruSegment(MemberKind.doctor, 'Doctor'),
              CruSegment(MemberKind.staff, 'Staff'),
            ],
            selected: _kind,
            onChanged: (v) => setState(() {
              _kind = v;
              _roleId = null;
              _modules = null;
            }),
          ),
          const SizedBox(height: CruSpace.s16),
          CruDropdownField<ClinicRole>(
            label: 'Role',
            value: role,
            items: roles,
            itemLabel: (r) => r.name,
            onChanged: (r) => setState(() {
              _roleId = r.id;
              _modules = _modules
                  ?.where(choosableModules(clinic, r).contains)
                  .toSet();
            }),
          ),
          if (_kind == MemberKind.doctor) ...[
            const SizedBox(height: CruSpace.s16),
            CruDropdownField<DoctorSpecialty>(
              label: 'Specialty',
              value: _specialty,
              items: DoctorSpecialty.all,
              itemLabel: (s) => s.label,
              onChanged: (s) => setState(() => _specialty = s),
            ),
          ],
          if (dentist) ...[
            const SizedBox(height: CruSpace.s20),
            Text('Dental work', style: CruType.headline.tint(c.label)),
            const SizedBox(height: CruSpace.s8),
            DentalFeaturesPicker(
              selected: _dental,
              onChanged: (f) => setState(() => _dental = f),
            ),
          ],
          if (available.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s20),
            Text('Features', style: CruType.headline.tint(c.label)),
            const SizedBox(height: CruSpace.s8),
            FeaturesChecklist(
              available: available,
              selected: _modules,
              onChanged: (m) => setState(() => _modules = m),
            ),
          ],
        ],
      ),
    );
  }

  /// The chosen role, else the usual one for the kind: Doctor for doctors,
  /// Receptionist for staff, else the first the person may give.
  ClinicRole? _roleFor(List<ClinicRole> roles) {
    if (roles.isEmpty) return null;
    final wanted =
        _roleId ?? (_kind == MemberKind.doctor ? 'doctor' : 'receptionist');
    for (final r in roles) {
      if (r.id == wanted) return r;
    }
    return roles.first;
  }
}
