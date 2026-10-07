import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/mobile/mobile_shell.dart';
import 'package:doctor_management_app/features/onboarding/data/loyalty_card.dart';
import 'package:doctor_management_app/features/onboarding/presentation/onboarding_flow.dart';
import 'package:doctor_management_app/features/shell/presentation/desktop_shell.dart';
import 'package:doctor_management_app/features/team/presentation/join_clinic_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Width (logical pixels) above which [DesktopShell] is shown instead of
/// the phone [MobileShell]. Tweak this single number to change where the
/// layout switches over.
const double kDesktopBreakpoint = 900;

/// Picks between the phone [MobileShell] and [DesktopShell] based on the
/// available width. A new doctor (no specialty, never onboarded) sees
/// [OnboardingFlow] first.
class ResponsiveShell extends ConsumerStatefulWidget {
  const ResponsiveShell({super.key});

  @override
  ConsumerState<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends ConsumerState<ResponsiveShell> {
  bool _onboarded = false;

  /// Set once the flow is shown, so it stays up while its own save
  /// updates the profile (until the doctor taps Open CruDoc).
  bool _onboarding = false;
  bool _stampChecked = false;

  /// Clinic invites waiting for a new account, asked once per sign-in.
  Future<List<ClinicInvite>>? _invites;
  String? _invitesFor;

  /// The person chose their own practice over the invites.
  bool _ownPractice = false;

  /// Joined a clinic, or someone a clinic added (they skip onboarding).
  static bool _isClinicMember(Map<String, dynamic>? profile) =>
      profile?['memberKind'] == 'doctor' || profile?['memberKind'] == 'staff';

  bool _needsOnboarding(Map<String, dynamic>? profile) {
    if (_onboarded || DemoSessionService.isDemoMode) return false;
    if (_onboarding) return true;
    // No profile yet (still being created, or unreachable): don't guess.
    if (profile == null || profile['onboarding'] != null) return false;
    if (_isClinicMember(profile)) return false;
    final specialty = (profile['specialty'] as String?)?.trim() ?? '';
    return specialty.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(doctorProfileProvider);
    // Loading or offline: open the app rather than block on the profile.
    if (profileAsync.hasValue) {
      final profile = profileAsync.value;
      if (_needsOnboarding(profile)) {
        return _onboardingOrInvites(profile);
      }
      // An existing account never takes answers given before sign-in.
      if (profile != null) OnboardingAnswers.pending = null;
      // Doctors who joined before the loyalty card get their first stamp
      // on entering. The card is the clinic owner's, not their team's.
      if (!_stampChecked && !DemoSessionService.isDemoMode) {
        _stampChecked = true;
        if (profile != null &&
            profile['loyalty'] == null &&
            !_isClinicMember(profile)) {
          LoyaltyService.stampThisMonth().catchError((_) => null);
        }
      }
    }
    // Open the app once it knows which clinic this person works in, and
    // rebuild every screen when that changes (joining a clinic).
    final access = ref.watch(clinicAccessProvider).value;
    if (access == null &&
        !DemoSessionService.isDemoMode &&
        FirebaseAuth.instance.currentUser != null) {
      return _loading(context);
    }
    return KeyedSubtree(
      key: ValueKey(access?.clinicId),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= kDesktopBreakpoint) {
            return const DesktopShell();
          }
          return const MobileShell();
        },
      ),
    );
  }

  /// A new account: clinic invites waiting for its phone or email come
  /// first; otherwise (or if they choose their own practice) onboarding.
  Widget _onboardingOrInvites(Map<String, dynamic>? profile) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_onboarding || _ownPractice || uid == null) {
      return _onboardingFlow(profile);
    }
    if (_invitesFor != uid) {
      _invitesFor = uid;
      _invites = ClinicTeamApi.instance.myInvites().catchError(
        (_) => const <ClinicInvite>[],
      );
    }
    return FutureBuilder<List<ClinicInvite>>(
      future: _invites,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _loading(context);
        }
        final invites = snapshot.data ?? const <ClinicInvite>[];
        if (invites.isEmpty) return _onboardingFlow(profile);
        return JoinClinicScreen(
          invites: invites,
          onJoined: () => setState(() {
            _onboarded = true;
            _stampChecked = true;
          }),
          onSetUpOwn: () => setState(() => _ownPractice = true),
        );
      },
    );
  }

  Widget _onboardingFlow(Map<String, dynamic>? profile) {
    _onboarding = true;
    return OnboardingFlow(
      answers: OnboardingAnswers.pending,
      initialName: switch (profile?['displayName']) {
        final String n when n != 'Doctor' => n,
        _ => null,
      },
      onDone: () => setState(() {
        OnboardingAnswers.pending = null;
        _onboarded = true;
        _stampChecked = true;
      }),
    );
  }

  Widget _loading(BuildContext context) => Scaffold(
    backgroundColor: context.cru.canvas,
    body: const Center(child: CircularProgressIndicator()),
  );
}
