import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/mobile/mobile_shell.dart';
import 'package:doctor_management_app/features/onboarding/data/loyalty_card.dart';
import 'package:doctor_management_app/features/onboarding/presentation/onboarding_flow.dart';
import 'package:doctor_management_app/features/shell/presentation/desktop_shell.dart';

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

  bool _needsOnboarding(Map<String, dynamic>? profile) {
    if (_onboarded || DemoSessionService.isDemoMode) return false;
    if (_onboarding) return true;
    // No profile yet (still being created, or unreachable): don't guess.
    if (profile == null || profile['onboarding'] != null) return false;
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
      // An existing account never takes answers given before sign-in.
      if (profile != null) OnboardingAnswers.pending = null;
      // Doctors who joined before the loyalty card get their first stamp
      // on entering.
      if (!_stampChecked && !DemoSessionService.isDemoMode) {
        _stampChecked = true;
        if (profile != null && profile['loyalty'] == null) {
          LoyaltyService.stampThisMonth().catchError((_) => null);
        }
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kDesktopBreakpoint) {
          return const DesktopShell();
        }
        return const MobileShell();
      },
    );
  }
}
