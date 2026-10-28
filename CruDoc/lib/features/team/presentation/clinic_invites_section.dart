import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_invites.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/core/people/crudoc_id.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/team/presentation/clinic_invite_watcher.dart';
import 'package:doctor_management_app/features/team/presentation/team_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Settings → Clinic invites: the CruDoc ID and number clinics invite,
/// whether they can find this person by the number, and the invites waiting
/// (Later ones included).
class ClinicInvitesSection extends ConsumerStatefulWidget {
  const ClinicInvitesSection({super.key});

  @override
  ConsumerState<ClinicInvitesSection> createState() =>
      _ClinicInvitesSectionState();
}

class _ClinicInvitesSectionState extends ConsumerState<ClinicInvitesSection> {
  /// Invite being joined or declined.
  String? _busy;
  bool _savingFindable = false;

  @override
  void initState() {
    super.initState();
    refreshClinicInvites();
  }

  Future<void> _confirmPhone() async {
    await confirmPhoneForInvites(context);
    if (mounted) setState(() {});
  }

  Future<void> _setFindable(bool value) async {
    setState(() => _savingFindable = true);
    try {
      await setDiscoverable(value);
    } catch (_) {
      if (mounted) showTeamToast(context, "Couldn't save. Try again.");
    } finally {
      if (mounted) setState(() => _savingFindable = false);
    }
  }

  Future<void> _act(ClinicInvite invite, {required bool join}) async {
    setState(() => _busy = invite.id);
    try {
      if (join) {
        await ClinicTeamApi.instance.acceptInvite(
          clinicId: invite.clinicId,
          inviteId: invite.id,
        );
        await ClinicSession.instance.reload();
      } else {
        await ClinicTeamApi.instance.declineInvite(
          clinicId: invite.clinicId,
          inviteId: invite.id,
        );
      }
    } on ClinicTeamException catch (e) {
      if (mounted) showTeamToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    final profile = ref.watch(doctorProfileProvider).value;
    final findable = isDiscoverable(profile);
    final invites = ref.watch(clinicInviteInboxProvider).value ?? const [];
    final warning = clinicInviteWarning(profile);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CrudocIdCard(
          description: 'Give your clinic admin your phone number or CruDoc ID.',
        ),
        const SizedBox(height: CruSpace.s12),
        CruCard(
          child: Row(
            children: [
              const CruIconTile(
                icon: CruIcons.phone,
                tone: CruTileTone.neutral,
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Phone number', style: CruType.row.tint(c.label)),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      phone ?? 'Not confirmed',
                      style: CruType.text.tabular.tint(c.label2),
                    ),
                  ],
                ),
              ),
              if (phone == null)
                CruButton(
                  label: 'Confirm',
                  kind: CruButtonKind.inset,
                  onPressed: _confirmPhone,
                ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.s12),
        CheckListCard(
          items: [
            CheckItem(
              label: 'Let clinics find me by my phone number',
              detail: findable
                  ? 'Clinics that have your number see you’re on CruDoc and '
                        'can invite you in the app. This covers your number '
                        'only: your exact CruDoc ID always finds you.'
                  : 'Clinics can still invite your number; you’ll see it '
                        'when you sign in. This covers your number only: '
                        'your exact CruDoc ID always finds you.',
              checked: findable,
              enabled: !_savingFindable,
              onToggle: _savingFindable ? null : () => _setFindable(!findable),
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s20),
        Text('Invites', style: CruType.headline.tint(c.label)),
        const SizedBox(height: CruSpace.s8),
        if (invites.isEmpty)
          Text(
            phone == null
                ? 'No invites. Give your clinic admin your CruDoc ID, or '
                      'confirm your phone number above.'
                : 'No invites. Ask your clinic admin to invite $phone or '
                      'your CruDoc ID.',
            style: CruType.text.tint(c.label2),
          )
        else ...[
          if (warning != null) ...[
            Text(warning, style: CruType.text.tint(c.label2)),
            const SizedBox(height: CruSpace.s8),
          ],
          TeamGroupCard(
            title: 'Waiting for you',
            rows: [
              for (final i in invites)
                TeamRow(
                  monogram: i.clinicName.isEmpty ? '?' : i.clinicName,
                  title: i.clinicName.isEmpty ? 'A clinic' : i.clinicName,
                  detail: [
                    if (i.roleName.isNotEmpty) i.roleName,
                    if (i.invitedByName.isNotEmpty)
                      'Invited by ${i.invitedByName}',
                  ].join(' · '),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CruCapsuleButton(
                        label: 'Decline',
                        onPressed: _busy == null
                            ? () => _act(i, join: false)
                            : null,
                      ),
                      const SizedBox(width: CruSpace.s8),
                      CruCapsuleButton(
                        label: _busy == i.id ? 'Joining…' : 'Join',
                        onPressed: _busy == null
                            ? () => _act(i, join: true)
                            : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
