import 'package:firebase_auth/firebase_auth.dart';
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

/// What the dialog shows once the person has been added.
enum _Outcome {
  /// Email account created and its set-your-password link sent.
  emailed,

  /// Email account created, but the link could not be sent (offline?).
  emailFailed,

  /// Phone account created: they sign in with a one-time code.
  phoneReady,

  /// They already had a CruDoc account, so they were invited instead.
  invited,
}

Future<void> showInviteDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const InviteDialog());

/// Adds a doctor or staff member to the clinic: the admin enters their
/// details, role and features, and CruDoc creates their login. The admin
/// never sets or sees a password — an email account is sent a link to set
/// its own, a phone account signs in with a one-time code. Someone who
/// already has a CruDoc account is invited instead, and joins on next
/// sign-in.
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

  /// Set once the person is added: the dialog then says what happens next.
  _Outcome? _outcome;
  String? _sentTo;
  bool _resending = false;

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
      final phone = _contact == _Contact.phone ? contact : null;
      final email = _contact == _Contact.email ? contact : null;
      final specialty = _kind == MemberKind.doctor ? _specialty?.label : null;
      final modules = _modules?.toList();
      final dental = dentist ? [for (final f in _dental) f.key] : null;

      final result = await ClinicTeamApi.instance.createMember(
        clinicId: clinicId,
        name: name,
        phone: phone,
        email: email,
        kind: _kind,
        roleId: role.id,
        specialty: specialty,
        modules: modules,
        dentalFeatures: dental,
      );

      final _Outcome outcome;
      if (result == CreateMemberResult.alreadyHasAccount) {
        // Their account is theirs; invite them to join rather than touch it.
        await ClinicTeamApi.instance.invite(
          clinicId: clinicId,
          name: name,
          phone: phone,
          email: email,
          kind: _kind,
          roleId: role.id,
          specialty: specialty,
          modules: modules,
          dentalFeatures: dental,
        );
        outcome = _Outcome.invited;
      } else if (email != null) {
        outcome = await _sendPasswordLink(email)
            ? _Outcome.emailed
            : _Outcome.emailFailed;
      } else {
        outcome = _Outcome.phoneReady;
      }
      if (mounted) {
        setState(() {
          _sentTo = contact;
          _outcome = outcome;
        });
      }
    } on ClinicTeamException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sends the new account's set-your-password email. Firebase sends it to
  /// the person's own inbox, so the admin never holds a working link.
  Future<bool> _sendPasswordLink(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email.trim().toLowerCase(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _resend() async {
    final email = _sentTo;
    if (email == null || _resending) return;
    setState(() => _resending = true);
    final ok = await _sendPasswordLink(email);
    if (mounted) {
      setState(() {
        _resending = false;
        _outcome = ok ? _Outcome.emailed : _Outcome.emailFailed;
      });
    }
  }

  Widget _doneView(BuildContext context) {
    final c = context.cru;
    final name = _name.text.trim();
    final to = _sentTo ?? '';
    final (title, message) = switch (_outcome!) {
      _Outcome.emailed => (
        'Account created',
        "We've emailed $name at $to a link to set their password. "
            'Once they have, they sign in to CruDoc with that email.',
      ),
      _Outcome.emailFailed => (
        'Account created',
        'The account for $name is ready, but the set-your-password email '
            'could not be sent. Check the connection and send it again.',
      ),
      _Outcome.phoneReady => (
        'Account created',
        '$name signs in to CruDoc with $to, using the one-time code '
            'sent to that phone. No password is needed.',
      ),
      _Outcome.invited => (
        'Invite sent',
        "$name already has a CruDoc account, so we've invited them "
            'instead. They join your clinic the next time they sign in with '
            '$to. The invite lasts 7 days.',
      ),
    };
    final canResend = _outcome == _Outcome.emailFailed;
    return CruFormDialog(
      title: title,
      submitLabel: canResend ? (_resending ? 'Sending…' : 'Send email again') : 'Done',
      cancelLabel: 'Close',
      busy: _resending,
      onSubmit: canResend ? _resend : () => Navigator.of(context).pop(),
      body: Text(message, style: CruType.text.tint(c.label2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (_outcome != null) return _doneView(context);

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
      subtitle: 'CruDoc creates their login. They sign in with this phone '
          'number or email.',
      submitLabel: _busy ? 'Creating…' : 'Create account',
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
