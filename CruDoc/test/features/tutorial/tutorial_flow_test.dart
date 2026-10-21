import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/tutorial/data/tutorial_repository.dart';
import 'package:doctor_management_app/features/tutorial/domain/tutorial_step.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_controller.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_gate.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_overlay.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_target.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'tutorial_fakes.dart';

const _welcome = 'Welcome to CruDoc';

Widget _app(List<Override> overrides, Widget home) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: CruTheme.day(),
    builder: (context, child) => TutorialHost(child: child!),
    home: home,
  ),
);

const _desktop = TutorialGate(
  platform: TutorialPlatform.desktop,
  child: FakeDesktopShell(),
);

/// Past the shell's settle delay, through every tab switch and morph.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(TutorialGate.settle);
  await tester.pumpAndSettle();
}

/// Taps a card button and waits for the next card (a tab switch on the
/// phone waits a little longer).
Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  // A step can open more than one tab (each waits for its screen).
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  await tester.pumpAndSettle();
}

TutorialState _state(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(TutorialHost)),
).read(tutorialControllerProvider);

void _desktopWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  late FakeTutorialRemote remote;
  late List<String> events;
  late TutorialRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    remote = FakeTutorialRemote();
    events = [];
    repo = fakeRepository(remote: remote, events: events);
  });

  group('when it shows', () {
    testWidgets('after onboarding hands over to the shell', (tester) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(tutorialOverrides(repository: repo), const _FakeOnboarding()),
      );
      await _settle(tester);
      expect(find.text(_welcome), findsNothing);

      await tester.tap(find.text('Open CruDoc'));
      await _settle(tester);
      expect(find.text(_welcome), findsOneWidget);
      expect(events, ['tutorial_started']);
    });

    testWidgets('not when the profile has a record at this version', (
      tester,
    ) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(
          tutorialOverrides(
            repository: repo,
            profile: {
              'tutorial': {
                'desktop': {'version': kTutorialVersion},
              },
            },
          ),
          _desktop,
        ),
      );
      await _settle(tester);
      expect(find.text(_welcome), findsNothing);
      expect(_state(tester).running, isFalse);
    });

    testWidgets('again after the version is bumped', (tester) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(
          tutorialOverrides(
            repository: repo,
            profile: {
              'tutorial': {
                'desktop': {'version': kTutorialVersion - 1},
              },
            },
          ),
          _desktop,
        ),
      );
      await _settle(tester);
      expect(find.text(_welcome), findsOneWidget);
    });

    testWidgets('not for an account from before the release', (tester) async {
      _desktopWindow(tester);
      final old = fakeRepository(
        remote: remote,
        createdAt: DateTime.utc(2025, 1, 1),
      );
      await tester.pumpWidget(
        _app(tutorialOverrides(repository: old), _desktop),
      );
      await _settle(tester);
      expect(find.text(_welcome), findsNothing);
    });

    testWidgets('pauses under a dialog and resumes on the same step', (
      tester,
    ) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(tutorialOverrides(repository: repo), _desktop),
      );
      await _settle(tester);
      await _tap(tester, 'Start tour');
      await _tap(tester, 'Next');
      expect(find.text('Find anyone fast'), findsOneWidget);

      final context = tester.element(find.byType(FakeDesktopShell));
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Clinic invite')),
      );
      await tester.pumpAndSettle();
      expect(_state(tester).paused, isTrue);
      expect(find.text('Find anyone fast'), findsNothing);

      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      expect(_state(tester).paused, isFalse);
      expect(find.text('Find anyone fast'), findsOneWidget);
    });
  });

  group('moving through it', () {
    testWidgets('Next, Back and Done, then completedAt is saved', (
      tester,
    ) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(tutorialOverrides(repository: repo), _desktop),
      );
      await _settle(tester);

      await _tap(tester, 'Start tour');
      expect(find.text('Everything lives here'), findsOneWidget);
      expect(find.text('1 of 7'), findsOneWidget);

      await _tap(tester, 'Next');
      expect(find.text('Find anyone fast'), findsOneWidget);
      expect(find.text('2 of 7'), findsOneWidget);

      await _tap(tester, 'Back');
      expect(find.text('Everything lives here'), findsOneWidget);

      for (var i = 0; i < 6; i++) {
        await _tap(tester, 'Next');
      }
      expect(find.text("You're set"), findsOneWidget);
      expect(find.text('7 of 7'), findsOneWidget);
      expect(find.text('Next'), findsNothing);

      await _tap(tester, 'Done');
      expect(find.text("You're set"), findsNothing);

      final save = remote.saves.single;
      expect(save.key, 'desktop');
      expect(save.r.outcome, TutorialOutcome.completed);
      expect(save.r.lastStep, 8);
      // The voice tour follows.
      expect(events, [
        'tutorial_started',
        'tutorial_completed',
        'voice_tutorial_started',
      ]);
      expect(_state(tester).tour, TutorialTour.voice);
    });

    testWidgets('opens Schedule, Scribe and Settings, then back to Dashboard', (
      tester,
    ) async {
      _desktopWindow(tester);
      final tabs = <int>[];
      await tester.pumpWidget(
        _app(
          tutorialOverrides(repository: repo),
          TutorialGate(
            platform: TutorialPlatform.desktop,
            child: FakeDesktopShell(upNext: false, tabs: tabs),
          ),
        ),
      );
      await _settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TutorialHost)),
      );
      int tab() => container.read(shellCurrentTabProvider);

      await _tap(tester, 'Start tour');
      for (var i = 0; i < 4; i++) {
        await _tap(tester, 'Next');
      }
      // No one waiting: Schedule opens, pointing at its views.
      expect(tab(), DesktopTab.appointments);
      expect(_state(tester).spot?.target, TutorialTarget.scheduleViews);
      expect(find.text('Your schedule'), findsOneWidget);

      await _tap(tester, 'Next');
      expect(tab(), DesktopTab.scribe);
      expect(_state(tester).spot?.target, TutorialTarget.scribePanel);
      expect(find.text('AI scribe'), findsOneWidget);

      // Back returns to the Schedule tab.
      await _tap(tester, 'Back');
      expect(tab(), DesktopTab.appointments);
      await _tap(tester, 'Next');

      await _tap(tester, 'Next');
      expect(tab(), DesktopTab.settings);
      expect(_state(tester).spot?.target, TutorialTarget.settingsSections);

      await _tap(tester, 'Done');
      expect(tab(), DesktopTab.dashboard);
      expect(
        tabs,
        containsAllInOrder([
          DesktopTab.appointments,
          DesktopTab.scribe,
          DesktopTab.settings,
          DesktopTab.dashboard,
        ]),
      );
    });

    testWidgets('Skip ends at once, saves the step and shows the toast', (
      tester,
    ) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(tutorialOverrides(repository: repo), _desktop),
      );
      await _settle(tester);
      await _tap(tester, 'Start tour');
      await _tap(tester, 'Next');

      await _tap(tester, 'Skip');
      expect(find.text('Find anyone fast'), findsNothing);
      expect(
        find.text('You can take the tour again from Settings.'),
        findsOneWidget,
      );
      final save = remote.saves.single;
      expect(save.r.outcome, TutorialOutcome.skipped);
      expect(save.r.lastStep, 3);
      expect(events.last, 'tutorial_skipped_step_3');

      // It never opens on its own again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(tutorialOverrides(repository: repo), _desktop),
      );
      await _settle(tester);
      expect(find.text(_welcome), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('taps on the dim do nothing', (tester) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(tutorialOverrides(repository: repo), _desktop),
      );
      await _settle(tester);
      await _tap(tester, 'Start tour');

      await tester.tapAt(const Offset(1200, 700));
      await tester.pumpAndSettle();
      expect(find.text('Everything lives here'), findsOneWidget);
      expect(_state(tester).running, isTrue);
    });

    testWidgets('replay from Settings starts from the welcome card', (
      tester,
    ) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(
          tutorialOverrides(
            repository: repo,
            profile: {
              'tutorial': {
                'desktop': {'version': kTutorialVersion},
              },
            },
          ),
          _desktop,
        ),
      );
      await _settle(tester);
      expect(find.text(_welcome), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TutorialHost)),
      );
      expect(
        container
            .read(tutorialControllerProvider.notifier)
            .requestReplay(TutorialPlatform.desktop),
        isTrue,
      );
      await _settle(tester);
      expect(find.text(_welcome), findsOneWidget);
      expect(_state(tester).replay, isTrue);

      // Skipping a replay leaves the earlier record alone.
      await _tap(tester, 'Skip');
      expect(remote.saves, isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('which steps', () {
    testWidgets('a target that is not on screen is left out of the count', (
      tester,
    ) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(
          tutorialOverrides(repository: repo),
          const TutorialGate(
            platform: TutorialPlatform.desktop,
            child: FakeDesktopShell(upNext: false, schedule: false),
          ),
        ),
      );
      await _settle(tester);
      await _tap(tester, 'Start tour');
      // Up next may still be on the Schedule tab: counted until then.
      expect(find.text('1 of 7'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await _tap(tester, 'Next');
      }
      // Nothing there either: the step goes, and the count with it.
      expect(find.text('AI scribe'), findsOneWidget);
      expect(find.text('5 of 6'), findsOneWidget);
      expect(_state(tester).steps.map((s) => s.id), isNot(contains('up_next')));
    });

    testWidgets('no Schedule views: Schedule in the sidebar instead', (
      tester,
    ) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(
          tutorialOverrides(repository: repo),
          const TutorialGate(
            platform: TutorialPlatform.desktop,
            child: FakeDesktopShell(upNext: false, scheduleViews: false),
          ),
        ),
      );
      await _settle(tester);
      await _tap(tester, 'Start tour');
      expect(find.text('1 of 7'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await _tap(tester, 'Next');
      }
      expect(_state(tester).spot?.target, TutorialTarget.sidebarSchedule);
      expect(find.text('Your schedule'), findsOneWidget);
      expect(
        find.text("Today's appointments and walk-ins, in order."),
        findsOneWidget,
      );
    });

    testWidgets('a step whose module is off is dropped', (tester) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(
          tutorialOverrides(
            repository: repo,
            modules: [
              for (final m in DoctorFeatureGuard.defaultModules)
                if (m != 'ai_assistant') m,
            ],
          ),
          _desktop,
        ),
      );
      await _settle(tester);
      await _tap(tester, 'Start tour');
      expect(find.text('1 of 6'), findsOneWidget);
      expect(_state(tester).steps.map((s) => s.id), isNot(contains('scribe')));
    });

    testWidgets('front desk staff see only what they can open', (tester) async {
      _desktopWindow(tester);
      const frontDesk = ClinicAccess(
        clinicId: 'clinic',
        uid: 'u1',
        roleId: 'reception',
        roleName: 'Reception',
        kind: MemberKind.staff,
        perms: {ClinicPermission.schedule},
      );
      await tester.pumpWidget(
        _app(tutorialOverrides(repository: repo, access: frontDesk), _desktop),
      );
      await _settle(tester);
      await _tap(tester, 'Start tour');
      expect(_state(tester).steps.map((s) => s.id), [
        'welcome',
        'sidebar',
        'new_appointment',
        'up_next',
        'account',
      ]);
      expect(find.text('1 of 4'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await _tap(tester, 'Next');
      }
      // Their plan is the owner's.
      expect(
        find.text(
          'Profile and this tour again. Open Settings from your name, '
          'bottom left.',
        ),
        findsOneWidget,
      );
    });
  });

  group('voice tour', () {
    Future<void> finishAppTour(WidgetTester tester) async {
      await _tap(tester, 'Start tour');
      for (var i = 0; i < 6; i++) {
        await _tap(tester, 'Next');
      }
      await _tap(tester, 'Done');
    }

    TutorialController tour(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byType(TutorialHost)),
    ).read(tutorialControllerProvider.notifier);

    testWidgets('follows a finished app tour', (tester) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(tutorialOverrides(repository: repo), _desktop),
      );
      await _settle(tester);
      await finishAppTour(tester);

      expect(find.text('Meet your voice assistant'), findsOneWidget);
      await _tap(tester, 'Start tour');
      expect(find.text('Hold Space to talk'), findsOneWidget);
      expect(_state(tester).spot?.target, TutorialTarget.voicePill);
      expect(find.text('1 of 4'), findsOneWidget);
      await _tap(tester, 'Next');
      expect(find.text('Hands-free'), findsOneWidget);
      await _tap(tester, 'Next');
      expect(find.text('Fill forms by voice'), findsOneWidget);
      expect(_state(tester).spot?.target, TutorialTarget.addPatient);
      await _tap(tester, 'Next');
      expect(find.text('Check, then confirm'), findsOneWidget);
      await _tap(tester, 'Done');

      expect(_state(tester).running, isFalse);
      expect(
        [for (final s in remote.saves) s.key],
        ['desktop', 'voiceDesktop'],
      );
      expect(remote.saves.last.r.outcome, TutorialOutcome.completed);
      expect(events.last, 'voice_tutorial_completed');
      // Nothing else follows.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(_state(tester).running, isFalse);
    });

    testWidgets('does not follow a skipped app tour', (tester) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(tutorialOverrides(repository: repo), _desktop),
      );
      await _settle(tester);
      await _tap(tester, 'Skip');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Meet your voice assistant'), findsNothing);
      expect(_state(tester).running, isFalse);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('starts from Settings', (tester) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(
          tutorialOverrides(
            repository: repo,
            profile: {
              'tutorial': {
                'desktop': {'version': kTutorialVersion},
              },
            },
          ),
          _desktop,
        ),
      );
      await _settle(tester);
      expect(
        tour(
          tester,
        ).requestReplay(TutorialPlatform.desktop, tour: TutorialTour.voice),
        isTrue,
      );
      await _settle(tester);
      expect(find.text('Meet your voice assistant'), findsOneWidget);
      await _tap(tester, 'Skip');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('on the phone: the floating mic, then the black pill', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          tutorialOverrides(
            repository: repo,
            profile: {
              'tutorial': {
                'mobile': {'version': kTutorialVersion},
              },
            },
          ),
          const TutorialGate(
            platform: TutorialPlatform.mobile,
            child: FakeMobileShell(),
          ),
        ),
      );
      await _settle(tester);
      tour(
        tester,
      ).requestReplay(TutorialPlatform.mobile, tour: TutorialTour.voice);
      await _settle(tester);
      await _tap(tester, 'Start tour');
      expect(find.text('Hold to talk'), findsOneWidget);
      expect(_state(tester).spot?.target, TutorialTarget.voiceBubble);
      await _tap(tester, 'Next');
      expect(_state(tester).spot?.target, TutorialTarget.island);
      await _tap(tester, 'Skip');
      await tester.pump(const Duration(seconds: 4));
    });
  });

  testWidgets('demo mode writes nothing to Firestore', (tester) async {
    _desktopWindow(tester);
    DemoSessionService.startDemoSession();
    addTearDown(DemoSessionService.endDemoSession);
    final demo = fakeRepository(remote: remote, events: events, demo: true);
    await tester.pumpWidget(
      _app(tutorialOverrides(repository: demo, profile: null), _desktop),
    );
    await _settle(tester);
    expect(find.text(_welcome), findsOneWidget);
    await _tap(tester, 'Start tour');
    for (var i = 0; i < 6; i++) {
      await _tap(tester, 'Next');
    }
    await _tap(tester, 'Done');
    expect(remote.saves, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  group('keys', () {
    testWidgets('Enter, Space and arrows move; Esc skips', (tester) async {
      _desktopWindow(tester);
      await tester.pumpWidget(
        _app(tutorialOverrides(repository: repo), _desktop),
      );
      await _settle(tester);

      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
      }

      await press(LogicalKeyboardKey.enter);
      expect(find.text('Everything lives here'), findsOneWidget);
      await press(LogicalKeyboardKey.arrowRight);
      expect(find.text('Find anyone fast'), findsOneWidget);
      await press(LogicalKeyboardKey.arrowLeft);
      expect(find.text('Everything lives here'), findsOneWidget);
      await press(LogicalKeyboardKey.space);
      expect(find.text('Find anyone fast'), findsOneWidget);
      // Voice push-to-talk stands aside while the card is up.
      expect(TutorialController.isShowing, isTrue);

      await press(LogicalKeyboardKey.escape);
      expect(_state(tester).running, isFalse);
      expect(TutorialController.isShowing, isFalse);
      expect(remote.saves.single.r.outcome, TutorialOutcome.skipped);
      expect(remote.saves.single.r.lastStep, 3);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('system Back goes back a step, and skips from the first', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const TutorialGate(
              platform: TutorialPlatform.mobile,
              child: FakeMobileShell(),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: tutorialOverrides(repository: repo),
          child: MaterialApp.router(
            theme: CruTheme.day(),
            routerConfig: router,
            builder: (context, child) => TutorialHost(child: child!),
          ),
        ),
      );
      await _settle(tester);
      await _tap(tester, 'Start tour');
      expect(find.text('Your day at a glance'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text(_welcome), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_state(tester).running, isFalse);
      final save = remote.saves.single;
      expect(save.key, 'mobile');
      expect(save.r.outcome, TutorialOutcome.skipped);
      expect(save.r.lastStep, 1);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  testWidgets('crossing the breakpoint ends the tour without saving it', (
    tester,
  ) async {
    _desktopWindow(tester);
    await tester.pumpWidget(
      _app(tutorialOverrides(repository: repo), const _FakeResponsive()),
    );
    await _settle(tester);
    await _tap(tester, 'Start tour');
    expect(_state(tester).platform, TutorialPlatform.desktop);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pump();
    await tester.pump();
    expect(_state(tester).ended, TutorialEnd.cancelled);
    expect(remote.saves, isEmpty);
    expect(await repo.seenLocally(TutorialPlatform.desktop), isFalse);

    // The phone's own tour decides for itself.
    await _settle(tester);
    expect(_state(tester).platform, TutorialPlatform.mobile);
    expect(
      find.text('A quick look at the essentials. Skip any time.'),
      findsOneWidget,
    );
    await _tap(tester, 'Skip');
    expect(remote.saves.single.key, 'mobile');
    await tester.pump(const Duration(seconds: 4));
  });
}

/// Onboarding, then the shell (as ResponsiveShell does after onDone).
class _FakeOnboarding extends StatefulWidget {
  const _FakeOnboarding();

  @override
  State<_FakeOnboarding> createState() => _FakeOnboardingState();
}

class _FakeOnboardingState extends State<_FakeOnboarding> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => _done
      ? _desktop
      : Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => setState(() => _done = true),
              child: const Text('Open CruDoc'),
            ),
          ),
        );
}

/// The desktop or phone shell by width, as ResponsiveShell picks them.
class _FakeResponsive extends StatelessWidget {
  const _FakeResponsive();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= 900
        ? const TutorialGate(
            key: ValueKey(TutorialPlatform.desktop),
            platform: TutorialPlatform.desktop,
            child: FakeDesktopShell(),
          )
        : const TutorialGate(
            key: ValueKey(TutorialPlatform.mobile),
            platform: TutorialPlatform.mobile,
            child: FakeMobileShell(),
          ),
  );
}
