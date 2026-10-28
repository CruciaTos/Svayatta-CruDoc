import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/clinic/clinic_invites.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/core/services/auth_service.dart';
import 'package:doctor_management_app/features/auth/presentation/phone_auth_sheet.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Width of the invite pop-up.
const double _kDialogWidth = 420;

/// Width of the label column in [InviteDetails].
const double _kDetailLabelWidth = 88;

/// Opens the sheet that adds a confirmed phone number to the signed-in
/// account, then looks for invites sent to that number. True once linked.
Future<bool> confirmPhoneForInvites(BuildContext context) async {
  final linked = await showPhoneAuthSheet(
    context,
    authService: AuthService(),
    linkToCurrentUser: true,
  );
  if (linked == null) return false;
  await refreshClinicInvites();
  return true;
}

/// Why this account can't simply join, or what joining changes; null when
/// nothing needs saying. [profile] is `users/{uid}`.
String? clinicInviteWarning(Map<String, dynamic>? profile) {
  final kind = profile?['memberKind'];
  // The server refuses only an owner whose clinic has other people in it
  // (clinic.ts joinBlock); this screen can't tell, so it says both.
  if (kind == 'owner') {
    return 'Your own clinic is kept, hidden while you work in this one. If '
        'others work in your clinic, this account can’t join.';
  }
  final member = kind == 'doctor' || kind == 'staff';
  final onboarding = profile?['onboarding'];
  final solo =
      onboarding is Map &&
      (onboarding['practiceType'] ?? profile?['practiceType']) == 'solo';
  if (solo && !member) {
    return 'Your own practice will be hidden while you work in this clinic. '
        'Nothing is deleted.';
  }
  return null;
}

/// Wraps the signed-in app: asks the server for invites sent to this
/// person's number (once per account, and again when a number is
/// confirmed), and pops up each new one with Join clinic, Decline and
/// Later. [onJoined] runs after a join, once the clinic has loaded.
class ClinicInviteWatcher extends ConsumerStatefulWidget {
  const ClinicInviteWatcher({
    super.key,
    required this.child,
    required this.onJoined,
  });

  final Widget child;
  final VoidCallback onJoined;

  @override
  ConsumerState<ClinicInviteWatcher> createState() =>
      _ClinicInviteWatcherState();
}

class _ClinicInviteWatcherState extends ConsumerState<ClinicInviteWatcher> {
  StreamSubscription<User?>? _userSub;

  /// "uid|phone" the inbox was last refreshed for.
  String? _refreshedFor;
  String? _uid;

  /// Put off with Later (stored), and shown already this run.
  Set<String>? _snoozed;
  final Set<String> _shown = {};
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _userSub = FirebaseAuth.instance.userChanges().listen(_onUser);
    clinicInvitePopupSuppressors.addListener(_maybeShow);
  }

  @override
  void dispose() {
    _userSub?.cancel();
    clinicInvitePopupSuppressors.removeListener(_maybeShow);
    super.dispose();
  }

  Future<void> _onUser(User? user) async {
    if (user == null) {
      _refreshedFor = null;
      _uid = null;
      _snoozed = null;
      _shown.clear();
      return;
    }
    final key = '${user.uid}|${user.phoneNumber ?? ''}';
    if (key == _refreshedFor) return;
    _refreshedFor = key;
    if (_uid != user.uid) {
      _uid = user.uid;
      _snoozed = null;
      _shown.clear();
      final snoozed = await snoozedClinicInvites(user.uid);
      if (!mounted || _uid != user.uid) return;
      _snoozed = snoozed;
      _maybeShow();
    }
    refreshClinicInvites();
  }

  void _maybeShow() {
    final uid = _uid;
    final snoozed = _snoozed;
    if (_showing || !mounted || uid == null || snoozed == null) return;
    if (clinicInvitePopupSuppressors.value > 0) return;
    final invites = ref.read(clinicInviteInboxProvider).value ?? const [];
    ClinicInvite? next;
    for (final i in invites) {
      if (!_shown.contains(i.id) && !snoozed.contains(i.id)) {
        next = i;
        break;
      }
    }
    if (next == null) return;
    final invite = next;
    _shown.add(invite.id);
    _showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final choice = await showDialog<ClinicInviteChoice>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ClinicInviteDialog(
          invite: invite,
          profile: ref.read(doctorProfileProvider).value,
        ),
      );
      _showing = false;
      if (!mounted) return;
      if (choice == ClinicInviteChoice.joined) {
        widget.onJoined();
        return;
      }
      if (choice == null || choice == ClinicInviteChoice.later) {
        snoozed.add(invite.id);
        await snoozeClinicInvite(uid, invite.id);
      }
      _maybeShow();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(clinicInviteInboxProvider, (_, _) => _maybeShow());
    return widget.child;
  }
}

enum ClinicInviteChoice { joined, declined, later }

/// One invite, asked about in a pop-up: Join clinic, Decline or Later.
/// Pops with the [ClinicInviteChoice] made.
class ClinicInviteDialog extends StatefulWidget {
  const ClinicInviteDialog({super.key, required this.invite, this.profile});

  final ClinicInvite invite;

  /// `users/{uid}`, for [clinicInviteWarning].
  final Map<String, dynamic>? profile;

  @override
  State<ClinicInviteDialog> createState() => _ClinicInviteDialogState();
}

class _ClinicInviteDialogState extends State<ClinicInviteDialog> {
  ClinicInviteChoice? _busy;
  String? _error;

  Future<void> _act(ClinicInviteChoice choice) async {
    final invite = widget.invite;
    setState(() {
      _busy = choice;
      _error = null;
    });
    try {
      if (choice == ClinicInviteChoice.joined) {
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
      if (mounted) Navigator.of(context).pop(choice);
    } on ClinicTeamException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final invite = widget.invite;
    final clinic = invite.clinicName.isEmpty ? 'A clinic' : invite.clinicName;
    final warning = clinicInviteWarning(widget.profile);
    final idle = _busy == null;
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: c.surface.withValues(alpha: 0),
      shape: cruShape(CruRadius.card, side: BorderSide(color: c.cardBorder)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kDialogWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CruSpace.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CruMonogram(name: clinic),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        clinic,
                        style: CruType.title.tint(c.label),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s12),
              Text(
                invite.invitedByName.isEmpty
                    ? 'You’ve been invited to join'
                    : '${invite.invitedByName} invited you to join',
                style: CruType.text.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s16),
              InviteDetails(invite: invite),
              if (warning != null) ...[
                const SizedBox(height: CruSpace.s16),
                Container(
                  padding: const EdgeInsets.all(CruSpace.s12),
                  decoration: ShapeDecoration(
                    color: c.inset,
                    shape: cruShape(CruRadius.control),
                  ),
                  child: Text(warning, style: CruType.text.tint(c.label2)),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: CruSpace.s12),
                Text(_error!, style: CruType.text.tint(c.label)),
              ],
              const SizedBox(height: CruSpace.s20),
              CruButton(
                label: _busy == ClinicInviteChoice.joined
                    ? 'Joining…'
                    : 'Join clinic',
                large: true,
                expand: true,
                onPressed: idle ? () => _act(ClinicInviteChoice.joined) : null,
              ),
              const SizedBox(height: CruSpace.s10),
              Row(
                children: [
                  Expanded(
                    child: CruButton(
                      label: _busy == ClinicInviteChoice.declined
                          ? 'Declining…'
                          : 'Decline',
                      kind: CruButtonKind.inset,
                      large: true,
                      expand: true,
                      onPressed: idle
                          ? () => _act(ClinicInviteChoice.declined)
                          : null,
                    ),
                  ),
                  const SizedBox(width: CruSpace.s10),
                  Expanded(
                    child: CruButton(
                      label: 'Later',
                      kind: CruButtonKind.inset,
                      large: true,
                      expand: true,
                      onPressed: idle
                          ? () => Navigator.of(context)
                                .pop(ClinicInviteChoice.later)
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Role, specialty and expiry of an invite, one line each; missing ones
/// are left out.
class InviteDetails extends StatelessWidget {
  const InviteDetails({super.key, required this.invite});

  final ClinicInvite invite;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final expires = invite.expiresAt;
    final rows = [
      if (invite.roleName.isNotEmpty) ('Role', invite.roleName),
      if (invite.specialty.isNotEmpty) ('Specialty', invite.specialty),
      if (expires != null)
        ('Expires', DateFormat('d MMM, h:mm a').format(expires.toLocal())),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
            child: Row(
              children: [
                SizedBox(
                  width: _kDetailLabelWidth,
                  child: Text(label, style: CruType.text.tint(c.label3)),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: CruType.text.tabular.tint(c.label),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
