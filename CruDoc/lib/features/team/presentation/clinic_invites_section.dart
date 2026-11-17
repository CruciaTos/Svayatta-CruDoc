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
  const ClinicInvitesSection({super.key, this.between});

  /// Shown between the waiting invites and the personal cards.
  final Widget? between;

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

    final personal = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CrudocIdCard(description: null),
        const SizedBox(height: CruSpace.cardGap),
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
        const SizedBox(height: CruSpace.cardGap),
        CheckListCard(
          items: [
            CheckItem(
              label: 'Let clinics find me by my phone number',
              checked: findable,
              enabled: !_savingFindable,
              onToggle: _savingFindable ? null : () => _setFindable(!findable),
            ),
          ],
        ),
      ],
    );

    final waiting = invites.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
          );

    final blocks = <Widget>[?waiting, ?widget.between, personal];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: CruSpace.cardGap),
          blocks[i],
        ],
      ],
    );
  }
}
