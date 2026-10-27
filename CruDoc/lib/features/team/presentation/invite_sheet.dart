import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/clinic/clinic_invites.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/dental_features.dart';
import 'package:doctor_management_app/features/dental/presentation/dental_features_picker.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/team/presentation/contact_invite_picker.dart';
import 'package:doctor_management_app/features/team/presentation/features_checklist.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_network.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Adds a doctor or staff member to the clinic by inviting their phone
/// number. Someone already on CruDoc sees the invite in the app straight
/// away; anyone else is sent the invite message (WhatsApp, SMS or email)
/// and finds it waiting when they sign up with that number. On a phone the
/// admin can pick the person from their contacts.
Future<void> showInviteDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const InviteDialog());

class InviteDialog extends ConsumerStatefulWidget {
  const InviteDialog({super.key});

  @override
  ConsumerState<InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<InviteDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _crudocId = TextEditingController();

  /// Invite by CruDoc ID instead of a phone number.
  bool _byId = false;
  MemberKind _kind = MemberKind.staff;
  String? _roleId;
  DoctorSpecialty? _specialty;
  Set<DentalFeature> _dental = DentalFeature.defaults;
  Set<String>? _modules;
  bool _busy = false;
  String? _notice;

  /// Set once the invite is saved: the dialog then says what happens next.
  InviteResult? _result;

  /// The invited number in E.164.
  String? _sentTo;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _crudocId.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    final clinicId = ref.read(clinicAccessProvider).value?.clinicId;
    if (clinicId == null) return;
    final picked = await pickContactToInvite(context, clinicId: clinicId);
    if (picked == null || !mounted) return;
    setState(() {
      _name.text = picked.name;
      _phone.text = invitePhoneForForm(picked.phone);
      _notice = null;
    });
  }

  Future<void> _send(ClinicRole? role) async {
    final clinicId = ref.read(clinicAccessProvider).value?.clinicId;
    final name = _name.text.trim();
    if (clinicId == null || role == null) return;
    final crudocId = _crudocId.text.trim();
    if (_byId) {
      if (name.isEmpty || !looksLikeCrudocId(crudocId)) {
        setState(
          () => _notice = 'Add a name and their CruDoc ID, like K7Q9-2XMB.',
        );
        return;
      }
    } else if (name.isEmpty || _phone.text.trim().isEmpty) {
      setState(() => _notice = 'Add a name and a phone number.');
      return;
    }
    final phone = _byId ? null : invitePhoneE164(_phone.text);
    if (!_byId && phone == null) {
      setState(
        () => _notice = 'Enter a 10-digit mobile number, or the full number '
            'starting with +.',
      );
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
      final result = await ClinicTeamApi.instance.invite(
        clinicId: clinicId,
        name: name,
        phone: phone,
        crudocId: _byId ? crudocId : null,
        kind: _kind,
        roleId: role.id,
        specialty: _kind == MemberKind.doctor ? _specialty?.label : null,
        modules: _modules?.toList(),
        dentalFeatures: dentist ? [for (final f in _dental) f.key] : null,
      );
      if (mounted) {
        setState(() {
          _sentTo = phone ?? '';
          _result = result;
        });
      }
    } on ClinicTeamException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _clinicName() => ref.read(activeClinicProvider).value?.name ?? '';

  String _message() {
    final profile = ref.read(doctorProfileProvider).value;
    final inviter = switch (profile?['displayName']) {
      final String n when n.trim().isNotEmpty && n != 'Doctor' => n,
      _ => FirebaseAuth.instance.currentUser?.displayName ?? '',
    };
    return buildInviteMessage(
      inviteeName: _name.text.trim(),
      inviterName: inviter,
      clinicName: _clinicName(),
      phone: _sentTo ?? '',
    );
  }

  Future<void> _open(String url) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      setState(() => _notice = "Couldn't open that app on this device.");
    }
  }

  Widget _doneView(BuildContext context) {
    final c = context.cru;
    final name = _name.text.trim();
    final to = _sentTo ?? '';
    if (_result!.onCruDoc) {
      return CruFormDialog(
        title: 'Invite sent',
        submitLabel: 'Done',
        cancelLabel: 'Close',
        onSubmit: () => Navigator.of(context).pop(),
        body: Text(
          "Invite sent to $name. They'll see it in CruDoc.",
          style: CruType.text.tint(c.label2),
        ),
      );
    }
    final text = _message();
    final body = Uri.encodeComponent(text);
    final clinic = _clinicName();
    final subject = Uri.encodeComponent(
      clinic.isEmpty ? 'Join us on CruDoc' : 'Join $clinic on CruDoc',
    );
    return CruFormDialog(
      title: 'Send the invite',
      submitLabel: 'Done',
      cancelLabel: 'Close',
      notice: _notice,
      onSubmit: () => Navigator.of(context).pop(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "$name isn't on CruDoc yet. Send them this message. When they "
            'sign up with $to, the invite will be waiting.',
            style: CruType.text.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s12),
          Container(
            padding: const EdgeInsets.all(CruSpace.s12),
            decoration: ShapeDecoration(
              color: c.inset,
              shape: cruShape(CruRadius.control),
            ),
            child: SelectableText(text, style: CruType.text.tint(c.label)),
          ),
          const SizedBox(height: CruSpace.s16),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              CruButton(
                label: 'WhatsApp',
                icon: CruIcons.whatsapp,
                kind: CruButtonKind.inset,
                onPressed: () => _open(
                  'https://wa.me/${to.replaceAll(RegExp(r'\D'), '')}?text=$body',
                ),
              ),
              CruButton(
                label: 'SMS',
                icon: CruIcons.phone,
                kind: CruButtonKind.inset,
                onPressed: () => _open('sms:$to?body=$body'),
              ),
              CruButton(
                label: 'Email',
                icon: CruIcons.arrowUpRight,
                kind: CruButtonKind.inset,
                onPressed: () => _open('mailto:?subject=$subject&body=$body'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (_result != null) return _doneView(context);

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
      title: 'Add a person',
      subtitle: 'Invite them by phone number or CruDoc ID. They join from '
          'CruDoc on their phone.',
      submitLabel: _busy ? 'Sending…' : 'Send invite',
      busy: _busy,
      notice: _notice,
      onSubmit: () => _send(role),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (contactMatchingSupported) ...[
            CruButton(
              label: 'Choose from contacts',
              icon: CruIcons.userPlus,
              kind: CruButtonKind.inset,
              expand: true,
              onPressed: _busy ? null : _pickContact,
            ),
            const SizedBox(height: CruSpace.s16),
          ],
          CruTextField(
            label: 'Name',
            controller: _name,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: CruSpace.s12),
          CruSegmentedControl<bool>(
            semanticLabel: 'Invite by',
            segments: const [
              CruSegment(false, 'Phone number'),
              CruSegment(true, 'CruDoc ID'),
            ],
            selected: _byId,
            onChanged: (v) => setState(() {
              _byId = v;
              _notice = null;
            }),
          ),
          const SizedBox(height: CruSpace.s12),
          if (_byId)
            CruTextField(
              label: 'CruDoc ID',
              controller: _crudocId,
              hint: 'K7Q9-2XMB',
              textCapitalization: TextCapitalization.characters,
              tabular: true,
            )
          else
            CruTextField(
              label: 'Phone number',
              controller: _phone,
              prefix: _phone.text.trimLeft().startsWith('+') ? null : '+91',
              keyboardType: TextInputType.phone,
              tabular: true,
              onChanged: (_) => setState(() {}),
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
