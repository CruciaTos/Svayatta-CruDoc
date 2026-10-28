import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_invites.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/core/people/crudoc_id.dart';
import 'package:doctor_management_app/features/team/presentation/clinic_invite_watcher.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Content column width, as onboarding.
const double _kMaxWidth = 560;

/// The invites someone has been sent, each with Join and Decline. Joining
/// opens that clinic; [onSetUpOwn] is the way back (by default to setting
/// up their own practice). Shows only what it is given: the live inbox is
/// [LiveJoinClinicScreen].
class JoinClinicScreen extends StatefulWidget {
  const JoinClinicScreen({
    super.key,
    required this.invites,
    required this.onJoined,
    required this.onSetUpOwn,
    this.backLabel = 'Set up my own practice instead',
    this.phoneNumber,
    this.onConfirmPhone,
    this.loading = false,
  });

  final List<ClinicInvite> invites;
  final VoidCallback onJoined;
  final VoidCallback onSetUpOwn;
  final String backLabel;

  /// The account's confirmed number, which clinics invite. Null asks the
  /// person to confirm one when there are no invites.
  final String? phoneNumber;

  /// Confirm your phone number; defaults to [confirmPhoneForInvites].
  final VoidCallback? onConfirmPhone;

  /// The inbox hasn't loaded yet.
  final bool loading;

  @override
  State<JoinClinicScreen> createState() => _JoinClinicScreenState();
}

class _JoinClinicScreenState extends State<JoinClinicScreen> {
  String? _joining;
  String? _declining;
  String? _error;

  /// Declined here; hidden before the inbox catches up.
  final Set<String> _declined = {};

  bool get _busy => _joining != null || _declining != null;

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

  Future<void> _decline(ClinicInvite invite) async {
    setState(() {
      _declining = invite.id;
      _error = null;
    });
    try {
      await ClinicTeamApi.instance.declineInvite(
        clinicId: invite.clinicId,
        inviteId: invite.id,
      );
      if (mounted) setState(() => _declined.add(invite.id));
    } on ClinicTeamException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _declining = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final invites = [
      for (final i in widget.invites)
        if (!_declined.contains(i.id)) i,
    ];
    final empty = invites.isEmpty;
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
                    empty ? 'Join a clinic' : "You've been invited",
                    style: CruType.largeTitle.tint(c.label),
                  ),
                ),
                const SizedBox(height: CruSpace.s6),
                Text(
                  empty
                      ? 'Your clinic admin invites you, and the invite shows '
                            'up here.'
                      : 'Join your clinic to see its patients and schedule.',
                  style: CruType.lead.tint(c.label2),
                ),
                const SizedBox(height: CruSpace.s20),
                if (empty) ...[
                  const CrudocIdCard(
                    description:
                        'Give your clinic admin your phone number or CruDoc '
                        'ID.',
                  ),
                  const SizedBox(height: CruSpace.s12),
                ],
                if (widget.loading && empty)
                  const Padding(
                    padding: EdgeInsets.all(CruSpace.s24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (empty)
                  _NoInvites(
                    phoneNumber: widget.phoneNumber,
                    onConfirmPhone:
                        widget.onConfirmPhone ??
                        () => confirmPhoneForInvites(context),
                  ),
                for (final invite in invites) ...[
                  _InviteCard(
                    invite: invite,
                    joining: _joining == invite.id,
                    declining: _declining == invite.id,
                    onJoin: _busy ? null : () => _join(invite),
                    onDecline: _busy ? null : () => _decline(invite),
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
                    label: widget.backLabel,
                    onPressed: _busy ? () {} : widget.onSetUpOwn,
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

class _NoInvites extends StatelessWidget {
  const _NoInvites({required this.phoneNumber, required this.onConfirmPhone});

  final String? phoneNumber;
  final VoidCallback onConfirmPhone;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final number = phoneNumber;
    return CruCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No invites yet', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s4),
          if (number != null && number.isNotEmpty)
            Text(
              'Ask your clinic admin to invite $number or your CruDoc ID.',
              style: CruType.text.tabular.tint(c.label2),
            )
          else ...[
            Text(
              'Give your clinic admin your CruDoc ID, or confirm your phone '
              'number so an invite to it finds you.',
              style: CruType.text.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s12),
            CruButton(
              label: 'Confirm your phone number',
              kind: CruButtonKind.inset,
              onPressed: onConfirmPhone,
            ),
          ],
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.joining,
    required this.declining,
    required this.onJoin,
    required this.onDecline,
  });

  final ClinicInvite invite;
  final bool joining;
  final bool declining;
  final VoidCallback? onJoin;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final clinic = invite.clinicName.isEmpty ? 'A clinic' : invite.clinicName;
    return CruCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
            ],
          ),
          const SizedBox(height: CruSpace.s16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              CruButton(
                label: declining ? 'Declining…' : 'Decline',
                kind: CruButtonKind.inset,
                onPressed: onDecline,
              ),
              const SizedBox(width: CruSpace.s8),
              CruButton(
                label: joining ? 'Joining…' : 'Join',
                onPressed: onJoin,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// [JoinClinicScreen] on the signed-in person's live invite inbox. While
/// it is up, invites don't also pop up over it.
class LiveJoinClinicScreen extends ConsumerStatefulWidget {
  const LiveJoinClinicScreen({
    super.key,
    required this.onJoined,
    required this.onBack,
    this.backLabel = 'Back',
  });

  final VoidCallback onJoined;
  final VoidCallback onBack;
  final String backLabel;

  @override
  ConsumerState<LiveJoinClinicScreen> createState() =>
      _LiveJoinClinicScreenState();
}

class _LiveJoinClinicScreenState extends ConsumerState<LiveJoinClinicScreen> {
  @override
  void initState() {
    super.initState();
    clinicInvitePopupSuppressors.value++;
    refreshClinicInvites();
  }

  @override
  void dispose() {
    clinicInvitePopupSuppressors.value--;
    super.dispose();
  }

  Future<void> _confirmPhone() async {
    await confirmPhoneForInvites(context);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(clinicInviteInboxProvider);
    return JoinClinicScreen(
      invites: inbox.value ?? const [],
      loading: inbox.isLoading,
      phoneNumber: FirebaseAuth.instance.currentUser?.phoneNumber,
      onConfirmPhone: _confirmPhone,
      onJoined: widget.onJoined,
      onSetUpOwn: widget.onBack,
      backLabel: widget.backLabel,
    );
  }
}
