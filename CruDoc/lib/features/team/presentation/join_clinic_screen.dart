import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Content column width, as onboarding.
const double _kMaxWidth = 560;

/// Shown after sign-in to someone a clinic has invited, instead of
/// onboarding. Joining opens that clinic; [onSetUpOwn] continues to the
/// normal onboarding for their own practice.
class JoinClinicScreen extends StatefulWidget {
  const JoinClinicScreen({
    super.key,
    required this.invites,
    required this.onJoined,
    required this.onSetUpOwn,
  });

  final List<ClinicInvite> invites;
  final VoidCallback onJoined;
  final VoidCallback onSetUpOwn;

  @override
  State<JoinClinicScreen> createState() => _JoinClinicScreenState();
}

class _JoinClinicScreenState extends State<JoinClinicScreen> {
  String? _joining;
  String? _error;

  Future<void> _join(ClinicInvite invite) async {
    setState(() {
      _joining = invite.id;
      _error = null;
    });
    try {
      await ClinicTeamApi.instance.acceptInvite(
        clinicId: invite.clinicId,
        inviteId: invite.id,
      );
      await ClinicSession.instance.reload();
      if (mounted) widget.onJoined();
    } on ClinicTeamException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _joining = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s16,
                CruSpace.s24,
                CruSpace.s16,
                CruSpace.s16,
              ),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    "You've been invited",
                    style: CruType.largeTitle.tint(c.label),
                  ),
                ),
                const SizedBox(height: CruSpace.s6),
                Text(
                  'Join your clinic to see its patients and schedule.',
                  style: CruType.lead.tint(c.label2),
                ),
                const SizedBox(height: CruSpace.s20),
                for (final invite in widget.invites) ...[
                  _InviteCard(
                    invite: invite,
                    joining: _joining == invite.id,
                    onJoin: _joining == null ? () => _join(invite) : null,
                  ),
                  const SizedBox(height: CruSpace.s12),
                ],
                if (_error != null) ...[
                  Text(_error!, style: CruType.text.tint(c.label)),
                  const SizedBox(height: CruSpace.s12),
                ],
                const SizedBox(height: CruSpace.s8),
                Center(
                  child: CruLink(
                    label: 'Set up my own practice instead',
                    onPressed: _joining == null ? widget.onSetUpOwn : () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.joining,
    required this.onJoin,
  });

  final ClinicInvite invite;
  final bool joining;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final clinic = invite.clinicName.isEmpty ? 'A clinic' : invite.clinicName;
    return CruCard(
      child: Row(
        children: [
          CruMonogram(name: clinic),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clinic, style: CruType.headline.tint(c.label)),
                if (invite.roleName.isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s4),
                  Text(
                    'as ${invite.roleName}',
                    style: CruType.text.tint(c.label2),
                  ),
                ],
                if (invite.invitedByName.isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s4),
                  Text(
                    'Invited by ${invite.invitedByName}',
                    style: CruType.caption.tint(c.label3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruButton(label: joining ? 'Joining…' : 'Join', onPressed: onJoin),
        ],
      ),
    );
  }
}
