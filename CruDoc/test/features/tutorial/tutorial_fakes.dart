import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/tutorial/data/tutorial_repository.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_gate.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_target.dart';

/// Records what would be written to `users/{uid}.tutorial`.
class FakeTutorialRemote implements TutorialRemote {
  final saves = <({String uid, String key, TutorialRecord r})>[];

  @override
  Future<void> save(String uid, String key, TutorialRecord r) async =>
      saves.add((uid: uid, key: key, r: r));
}

/// A repository for one signed-in person, with nothing touching Firebase.
TutorialRepository fakeRepository({
  required FakeTutorialRemote remote,
  List<String>? events,
  bool demo = false,
  int demoSession = 1,
  DateTime? createdAt,
}) => TutorialRepository(
  remote: remote,
  currentUid: () => demo ? null : 'u1',
  // A new account by default (after the release cutoff).
  accountCreatedAt: () => createdAt ?? DateTime.utc(2027, 1, 1),
  isDemo: () => demo,
  demoSession: () => demoSession,
  log: (e) => events?.add(e),
);

/// The providers the gate reads, without Firebase.
List<Override> tutorialOverrides({
  required TutorialRepository repository,
  Map<String, dynamic>? profile = const {},
  ClinicAccess? access,
  List<String> modules = DoctorFeatureGuard.defaultModules,
}) => [
  tutorialRepositoryProvider.overrideWithValue(repository),
  doctorProfileProvider.overrideWith((ref) => Stream.value(profile)),
  clinicAccessProvider.overrideWith((ref) => Stream.value(access)),
  tutorialModulesProvider.overrideWith((ref) => Stream.value(modules)),
];

/// A stand-in for one tour target: a fixed box at a fixed place.
Widget fakeTarget(
  TutorialTarget target, {
  required double left,
  required double top,
  double width = 120,
  double height = 40,
}) => Positioned(
  left: left,
  top: top,
  child: TutorialAnchor(
    target: target,
    child: SizedBox(width: width, height: height, child: Text(target.name)),
  ),
);

/// The desktop shell's targets, laid out roughly where the real ones sit.
/// It switches tabs like DesktopShell (through shellNavigatorProvider), and
/// [tabs] records every tab it was sent to.
class FakeDesktopShell extends ConsumerStatefulWidget {
  const FakeDesktopShell({
    super.key,
    this.upNext = true,
    this.schedule = true,
    this.scheduleViews = true,
    this.tabs,
  });

  final bool upNext;
  final bool schedule;

  /// Schedule's view switcher (hidden when only one view is left).
  final bool scheduleViews;
  final List<int>? tabs;

  @override
  ConsumerState<FakeDesktopShell> createState() => _FakeDesktopShellState();
}

class _FakeDesktopShellState extends ConsumerState<FakeDesktopShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(shellNavigatorProvider.notifier).state = (tab) {
        widget.tabs?.add(tab);
        ref.read(shellCurrentTabProvider.notifier).state = tab;
        return true;
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(shellCurrentTabProvider);
    return Scaffold(
      body: Stack(
        children: [
          fakeTarget(
            TutorialTarget.sidebar,
            left: 0,
            top: 0,
            width: 240,
            height: 700,
          ),
          if (widget.schedule)
            fakeTarget(TutorialTarget.sidebarSchedule, left: 12, top: 120),
          fakeTarget(TutorialTarget.sidebarScribe, left: 12, top: 220),
          fakeTarget(TutorialTarget.account, left: 12, top: 640),
          fakeTarget(TutorialTarget.voicePill, left: 560, top: 4, height: 30),
          if (tab == DesktopTab.dashboard) ...[
            fakeTarget(TutorialTarget.search, left: 400, top: 48, width: 300),
            fakeTarget(TutorialTarget.addPatient, left: 720, top: 48),
            fakeTarget(TutorialTarget.newAppointment, left: 860, top: 48),
            if (widget.upNext)
              fakeTarget(
                TutorialTarget.upNext,
                left: 400,
                top: 160,
                width: 380,
                height: 200,
              ),
          ],
          if (tab == DesktopTab.appointments &&
              widget.schedule &&
              widget.scheduleViews)
            fakeTarget(TutorialTarget.scheduleViews, left: 400, top: 48),
          if (tab == DesktopTab.scribe)
            fakeTarget(
              TutorialTarget.scribePanel,
              left: 800,
              top: 100,
              width: 420,
              height: 500,
            ),
          if (tab == DesktopTab.settings)
            fakeTarget(
              TutorialTarget.settingsSections,
              left: 280,
              top: 100,
              width: 240,
              height: 400,
            ),
        ],
      ),
    );
  }
}

/// The phone shell's targets.
class FakeMobileShell extends StatelessWidget {
  const FakeMobileShell({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        fakeTarget(
          TutorialTarget.island,
          left: 140,
          top: 8,
          width: 100,
          height: 30,
        ),
        fakeTarget(
          TutorialTarget.voiceBubble,
          left: 296,
          top: 420,
          width: 54,
          height: 54,
        ),
        fakeTarget(
          TutorialTarget.mobileUpNext,
          left: 16,
          top: 200,
          width: 328,
          height: 160,
        ),
        for (final (i, t) in const [
          TutorialTarget.navHome,
          TutorialTarget.navSchedule,
          TutorialTarget.navPatients,
          TutorialTarget.navTasks,
          TutorialTarget.navMore,
        ].indexed)
          fakeTarget(t, left: 16.0 + i * 66, top: 580, width: 66, height: 53),
      ],
    ),
  );
}
