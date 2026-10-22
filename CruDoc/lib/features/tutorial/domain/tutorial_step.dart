import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_tabs.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_target.dart';

/// The desktop sidebar layout and the phone's tabs differ, so each has
/// its own tours.
enum TutorialPlatform { desktop, mobile }

/// Which tour: the app's essentials, or how to use voice.
enum TutorialTour {
  app,

  /// Hold Space to talk, hands-free, filling forms. Offered right after
  /// the app tour is finished, and from Settings.
  voice,
}

/// What a step's guard can see: the same inputs the shells gate their
/// tabs on (the person's clinic role and the plan's modules).
@immutable
class TutorialScope {
  const TutorialScope({
    this.access,
    this.modules = DoctorFeatureGuard.defaultModules,
    this.demo = false,
  });

  /// Null for a solo doctor before their clinic access loads: every tab.
  final ClinicAccess? access;

  /// The plan's modules (DoctorFeatureGuard keys).
  final List<String> modules;
  final bool demo;

  /// The plan includes [module].
  bool planHas(String module) => DoctorFeatureGuard.isEnabled(modules, module);

  /// This person's role opens [module].
  bool roleAllows(String module) => access?.allowsModule(module) ?? true;

  bool desktopTab(int tab) => clinicAllowsDesktopTab(access, tab);
  bool mobileTab(int tab) => clinicAllowsMobileTab(access, tab);

  /// As `clinicCanProvider`.
  bool can(ClinicPermission permission) => access?.can(permission) ?? demo;

  /// Owns the clinic (and so its plan).
  bool get isOwner => access == null || access!.isOwner;
}

/// Whether the person in [scope] can open what a step shows.
typedef TutorialGuard = bool Function(TutorialScope scope);

/// One element a step can point at. A step uses the first of its spots the
/// person can open that is on screen.
@immutable
class TutorialSpot {
  const TutorialSpot(this.target, {this.title, this.body, this.tab, this.when});

  final TutorialTarget target;

  /// Replace the step's title and body when this spot is the one shown.
  final String? title;
  final String? body;

  /// The tab to open for this spot, when it differs from the step's.
  final int? tab;

  /// Null: everyone.
  final TutorialGuard? when;

  bool allows(TutorialScope scope) => when?.call(scope) ?? true;
}

/// One card of the tour. Data only: the copy lives in tutorial_steps.dart.
@immutable
class TutorialStep {
  const TutorialStep({
    required this.id,
    required this.title,
    required this.body,
    this.spots = const [],
    this.tab,
    this.when,
    this.ai = false,
  });

  final String id;
  final String title;

  /// One sentence, ideally under 15 words.
  final String body;

  /// Where to point, best first. Empty: the centred welcome card.
  final List<TutorialSpot> spots;

  /// The tab to open before pointing (a DesktopTab or MobileTab index).
  /// Null: stay on the current one.
  final int? tab;

  /// Null: everyone.
  final TutorialGuard? when;

  /// The scribe step: the card carries the violet AI badge.
  final bool ai;

  bool get isWelcome => spots.isEmpty;

  /// Whether this step is for the person in [scope]: they can open its
  /// feature, through at least one of its spots.
  bool allows(TutorialScope scope) =>
      (when?.call(scope) ?? true) &&
      (isWelcome || spots.any((s) => s.allows(scope)));
}
