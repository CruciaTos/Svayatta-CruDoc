import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_network_watcher.dart';
import 'package:doctor_management_app/features/mobile/mobile_shell.dart';
import 'package:doctor_management_app/features/onboarding/data/loyalty_card.dart';
import 'package:doctor_management_app/features/onboarding/presentation/onboarding_flow.dart';
import 'package:doctor_management_app/features/shell/presentation/desktop_shell.dart';
import 'package:doctor_management_app/features/team/presentation/clinic_invite_watcher.dart';
import 'package:doctor_management_app/features/tutorial/domain/tutorial_step.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_gate.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Width (logical pixels) above which [DesktopShell] is shown instead of
/// the phone [MobileShell]. Tweak this single number to change where the
/// layout switches over.
const double kDesktopBreakpoint = 900;

/// Picks between the phone [MobileShell] and [DesktopShell] based on the
/// available width. A new doctor (no specialty, never onboarded) sees
/// [OnboardingFlow] first. Clinic invites pop up over all of it
/// ([ClinicInviteWatcher]), and referrals from other doctors are announced
/// ([ReferralNetworkWatcher]).
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
  Widget build(BuildContext context) => ClinicInviteWatcher(
    // Joining from the pop-up (or the Join step) leaves onboarding.
    onJoined: () => setState(() {
      OnboardingAnswers.pending = null;
      _onboarded = true;
      _stampChecked = true;
    }),
    // Referrals other doctors send arrive (and are announced) anywhere.
    child: ReferralNetworkWatcher(child: _content(context)),
  );

  Widget _content(BuildContext context) {
    final profileAsync = ref.watch(doctorProfileProvider);
    // Loading or offline: open the app rather than block on the profile.
    if (profileAsync.hasValue) {
      final profile = profileAsync.value;
      if (_needsOnboarding(profile)) {
        return _onboardingFlow(profile);
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
          // The first-run tour, separately per layout. Crossing the
          // breakpoint swaps the gate too, which ends the other tour.
          if (constraints.maxWidth >= kDesktopBreakpoint) {
            return const TutorialGate(
              key: ValueKey(TutorialPlatform.desktop),
              platform: TutorialPlatform.desktop,
              child: DesktopShell(),
            );
          }
          return const TutorialGate(
            key: ValueKey(TutorialPlatform.mobile),
            platform: TutorialPlatform.mobile,
            child: MobileShell(),
          );
        },
      ),
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
