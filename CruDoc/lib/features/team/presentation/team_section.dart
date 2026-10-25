import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/team/presentation/activity_log_view.dart';
import 'package:doctor_management_app/features/team/presentation/admin_clinical_access_card.dart';
import 'package:doctor_management_app/features/team/presentation/features_checklist.dart';
import 'package:doctor_management_app/features/team/presentation/invite_sheet.dart';
import 'package:doctor_management_app/features/team/presentation/member_sheet.dart';
import 'package:doctor_management_app/features/team/presentation/roles_view.dart';
import 'package:doctor_management_app/features/team/presentation/team_analytics_view.dart';
import 'package:doctor_management_app/features/team/presentation/team_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _TeamTab { members, roles, activity, analytics }

/// Settings → Team: the clinic's doctors and staff, their roles, and what
/// they did. Only for people with the `team` permission. An existing
/// doctor's clinic is set up the first time they open it.
class TeamSection extends ConsumerStatefulWidget {
  const TeamSection({super.key});

  @override
  ConsumerState<TeamSection> createState() => _TeamSectionState();
}

class _TeamSectionState extends ConsumerState<TeamSection> {
  _TeamTab _tab = _TeamTab.members;
  bool _settingUp = false;
  String? _setupError;

  Future<void> _setUpClinic() async {
    if (_settingUp) return;
    setState(() {
      _settingUp = true;
      _setupError = null;
    });
    final user = FirebaseAuth.instance.currentUser;
    final profile = ref.read(doctorProfileProvider).value;
    // What the person said during onboarding, when the clinic could not be
    // set up there and then. Absent (an older account) means a doctor-owner,
    // which is how every clinic was set up before the question existed.
    final onboarding = profile?['onboarding'];
    final answers = onboarding is Map ? onboarding : const {};
    final ownerIsDoctor = answers['ownerIsDoctor'] != false;
    final givenName = (answers['clinicName'] as String?)?.trim() ?? '';
    try {
      await ClinicTeamApi.instance.ensureClinic(
        clinicName: givenName.isNotEmpty
            ? givenName
            : DoctorProfileHelper.tryFormatClinicName(user, profile) ?? '',
        ownerName: DoctorProfileHelper.formatDoctorName(user, profile),
        specialty: ref.read(activeDoctorSpecialtyProvider).value?.label ?? '',
        ownerIsDoctor: ownerIsDoctor,
      );
      if (!ownerIsDoctor) await user?.getIdToken(true);
      await ClinicSession.instance.reload();
    } on ClinicTeamException catch (e) {
      if (mounted) setState(() => _setupError = e.message);
    } finally {
      if (mounted) setState(() => _settingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final me = ref.watch(clinicAccessProvider).value;
    final clinicAsync = ref.watch(activeClinicProvider);
    final clinic = clinicAsync.value;

    if (clinicAsync.hasValue && clinic == null) {
      // An owner whose team hasn't been set up yet.
      if (me != null && me.isOwner && _setupError == null && !_settingUp) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _setUpClinic());
      }
      return CruCard(
        child: Row(
          children: [
            Expanded(
              child: Text(
                _setupError ?? 'Setting up your team…',
                style: CruType.text.tint(c.label2),
              ),
            ),
            if (_setupError != null)
              CruCapsuleButton(label: 'Try again', onPressed: _setUpClinic),
          ],
        ),
      );
    }
    if (clinic == null || me == null) return const SizedBox.shrink();

    // Someone who lost the admin role while on Analytics goes back to People.
    final tab = _tab == _TeamTab.analytics && !me.isAdmin
        ? _TeamTab.members
        : _tab;
    final members = ref.watch(clinicMembersProvider).value ?? const [];
    final active = members.where((m) => m.active).toList();
    final doctors = active.where((m) => m.kind == MemberKind.doctor).length;
    final staff = active.length - doctors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CruCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          clinic.name.isEmpty ? 'Your clinic' : clinic.name,
                          style: CruType.headline.tint(c.label),
                        ),
                        const SizedBox(height: CruSpace.s4),
                        Text(
                          '$doctors of ${clinic.seatsDoctor} doctors · '
                          '$staff of ${clinic.seatsStaff} staff',
                          style: CruType.text.tabular.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: CruSpace.s16),
                  CruButton(
                    label: 'Add person',
                    onPressed: () => showInviteDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              CruSegmentedControl<_TeamTab>(
                segments: [
                  const CruSegment(_TeamTab.members, 'People'),
                  const CruSegment(_TeamTab.roles, 'Roles'),
                  const CruSegment(_TeamTab.activity, 'Activity'),
                  // How each person is doing: the owner and admins only.
                  if (me.isAdmin)
                    const CruSegment(_TeamTab.analytics, 'Analytics'),
                ],
                selected: tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.cardGap),
        switch (tab) {
          _TeamTab.members => _MembersView(me: me),
          _TeamTab.roles => const RolesView(),
          _TeamTab.activity => const ActivityLogView(),
          _TeamTab.analytics => const TeamAnalyticsView(),
        },
        // Owner-only, and only once the clinic has an admin other than the
        // owner; the card hides itself otherwise.
        if (tab == _TeamTab.members) ...[
          const SizedBox(height: CruSpace.cardGap),
          AdminClinicalAccessCard(me: me, clinic: clinic, members: members),
        ],
      ],
    );
  }
}

class _MembersView extends ConsumerWidget {
  const _MembersView({required this.me});

  final ClinicAccess me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final members = (ref.watch(clinicMembersProvider).value ?? const [])
        .where((m) => m.active)
        .toList();
    final invites = ref.watch(clinicInvitesProvider).value ?? const [];
    final declined =
        ref.watch(clinicDeclinedInvitesProvider).value ?? const [];

    Widget memberRow(ClinicMember m) {
      final self = m.uid == me.uid;
      final detail = m.kind == MemberKind.doctor
          ? [
              if (m.specialty.isNotEmpty) m.specialty,
              if (m.roleId != 'doctor') m.roleName,
            ].join(' · ')
          : m.roleName;
      return TeamRow(
        monogram: m.name.isEmpty ? '?' : m.name,
        title: self ? '${m.name} (you)' : m.name,
        detail: detail,
        trailing: m.isOwner
            ? Text('Owner', style: CruType.caption.tint(c.label3))
            : null,
        onTap: m.isOwner || self ? null : () => showMemberDialog(context, m),
      );
    }

    Widget inviteRow(ClinicInvite i) => TeamRow(
      monogram: i.name.isEmpty ? '?' : i.name,
      title: i.name.isEmpty ? (i.phone.isEmpty ? i.email : i.phone) : i.name,
      detail: [
        if (i.phone.isNotEmpty) i.phone else if (i.email.isNotEmpty) i.email,
        if (i.roleName.isNotEmpty) i.roleName,
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const WaitingPill('Invited'),
          const SizedBox(width: CruSpace.s8),
          CruCapsuleButton(
            label: 'Cancel',
            onPressed: () => _cancelInvite(context, ref, i),
          ),
        ],
      ),
    );

    Widget declinedRow(ClinicInvite i) => TeamRow(
      monogram: i.name.isEmpty ? '?' : i.name,
      title: i.name.isEmpty ? (i.phone.isEmpty ? i.email : i.phone) : i.name,
      detail: [
        if (i.phone.isNotEmpty) i.phone else if (i.email.isNotEmpty) i.email,
        if (i.roleName.isNotEmpty) i.roleName,
      ].join(' · '),
      trailing: Text('Declined', style: CruType.caption.tint(c.label3)),
    );

    List<Widget> group(MemberKind kind) => [
      for (final m in members)
        if (m.kind == kind) memberRow(m),
      for (final i in invites)
        if (i.kind == kind) inviteRow(i),
      for (final i in declined)
        if (i.kind == kind) declinedRow(i),
    ];

    final doctorRows = group(MemberKind.doctor);
    final staffRows = group(MemberKind.staff);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (doctorRows.isNotEmpty)
          TeamGroupCard(title: 'Doctors', rows: doctorRows),
        if (doctorRows.isNotEmpty && staffRows.isNotEmpty)
          const SizedBox(height: CruSpace.cardGap),
        if (staffRows.isNotEmpty)
          TeamGroupCard(title: 'Staff', rows: staffRows),
      ],
    );
  }

  Future<void> _cancelInvite(
    BuildContext context,
    WidgetRef ref,
    ClinicInvite invite,
  ) async {
    final clinicId = ref.read(clinicAccessProvider).value?.clinicId;
    if (clinicId == null) return;
    try {
      await ClinicTeamApi.instance.cancelInvite(
        clinicId: clinicId,
        inviteId: invite.id,
      );
    } on ClinicTeamException catch (e) {
      if (context.mounted) showTeamToast(context, e.message);
    }
  }
}

/// Settings → My features, for someone working in another person's
/// clinic: which of the features their role allows they want to see.
class MyFeaturesSection extends ConsumerWidget {
  const MyFeaturesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final me = ref.watch(clinicAccessProvider).value;
    final clinic = ref.watch(activeClinicProvider).value;
    if (me == null || me.isOwner) return const SizedBox.shrink();
    final plan = (clinic?.enabledModules ?? DoctorFeatureGuard.defaultModules)
        .map((m) => m.toLowerCase())
        .toSet();
    final role = ClinicAccess(
      clinicId: me.clinicId,
      uid: me.uid,
      roleId: me.roleId,
      roleName: me.roleName,
      kind: me.kind,
      perms: me.perms,
    );
    final available = [
      for (final key in kTeamModuleLabels.keys)
        if (plan.contains(key) && role.allowsModule(key)) key,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Turn off what you don\'t use. Your role decides what you can '
          'turn on.',
          style: CruType.text.tint(c.label2),
        ),
        const SizedBox(height: CruSpace.s12),
        FeaturesChecklist(
          available: available,
          selected: me.modules,
          onChanged: (modules) async {
            try {
              await FirebaseFirestore.instance
                  .collection('clinics')
                  .doc(me.clinicId)
                  .collection('members')
                  .doc(me.uid)
                  .update({
                    'modules': modules == null
                        ? FieldValue.delete()
                        : modules.toList(),
                  });
            } catch (_) {
              if (context.mounted) {
                showTeamToast(context, "Couldn't save. Try again.");
              }
            }
          },
        ),
      ],
    );
  }
}
