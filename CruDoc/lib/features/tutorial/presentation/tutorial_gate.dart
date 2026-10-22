import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/tutorial/data/tutorial_repository.dart';
import 'package:doctor_management_app/features/tutorial/domain/tutorial_step.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_controller.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The plan's modules, as the shells read them.
final tutorialModulesProvider = StreamProvider.autoDispose<List<String>>((ref) {
  ref.watch(authStateProvider);
  return DoctorFeatureGuard.watchEnabledModules();
});

/// Decides when the tour opens, in one place. Wraps the desktop or phone
/// shell; it opens [platform]'s tour once, after the shell has settled,
/// for someone who hasn't seen it and while nothing covers the shell, and
/// offers the voice tour right after that tour is finished. A dialog or
/// page over the shell pauses the tour on its step; system Back goes a
/// step back (and skips from the first card).
class TutorialGate extends ConsumerStatefulWidget {
  const TutorialGate({super.key, required this.platform, required this.child});

  final TutorialPlatform platform;
  final Widget child;

  /// Wait after the shell's first frame before the tour opens.
  static const Duration settle = Duration(milliseconds: 400);

  @override
  ConsumerState<TutorialGate> createState() => _TutorialGateState();
}

class _TutorialGateState extends ConsumerState<TutorialGate> {
  late final TutorialController _tour;
  late final TutorialRepository _repo;
  Timer? _timer;

  /// The automatic tour has been started or ruled out for this shell.
  bool _decided = false;
  bool _checking = false;

  /// The local mirror's answer (null until read).
  bool? _seenHere;

  /// Nothing (dialog, page) covers the shell.
  bool _onTop = true;

  @override
  void initState() {
    super.initState();
    _tour = ref.read(tutorialControllerProvider.notifier);
    _repo = ref.read(tutorialRepositoryProvider);
    _tour.bindGate(widget.platform, _startReplay);
    _readLocal();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tour.unbindGate(widget.platform, _startReplay);
    // Crossing the breakpoint (or leaving the shell) ends this tour without
    // recording it. Providers can't change while the tree is torn down.
    final tour = _tour;
    final platform = widget.platform;
    scheduleMicrotask(() {
      try {
        tour.cancel(platform);
      } catch (_) {
        // The app is closing.
      }
    });
    super.dispose();
  }

  Future<void> _readLocal() async {
    final seen = await _repo.seenLocally(widget.platform);
    if (!mounted) return;
    _seenHere = seen;
    if (seen) {
      _decided = true;
    } else {
      _schedule();
    }
  }

  bool get _ready {
    if (!mounted || _decided || _seenHere != false || !_onTop) return false;
    if (ref.read(tutorialControllerProvider).running) return false;
    if (DemoSessionService.isDemoMode) return true;
    return ref.read(doctorProfileProvider).hasValue &&
        ref.read(tutorialModulesProvider).hasValue;
  }

  void _schedule() {
    if (_timer != null || _checking || !_ready) return;
    _timer = Timer(TutorialGate.settle, () {
      _timer = null;
      unawaited(_autoStart());
    });
  }

  Future<void> _autoStart() async {
    // Something opened meanwhile: the next sync schedules it again.
    if (!_ready) return;
    _checking = true;
    final seen = await _repo.hasSeen(
      widget.platform,
      profile: ref.read(doctorProfileProvider).value,
    );
    _checking = false;
    if (!mounted) return;
    if (seen) {
      _decided = true;
      return;
    }
    if (!_ready) return;
    _decided = true;
    await _tour.start(widget.platform, scope: _scope(), actions: _actions());
  }

  void _sync() {
    if (!mounted) return;
    final s = ref.read(tutorialControllerProvider);
    if (s.running) {
      if (s.platform != widget.platform) return;
      _onTop ? _tour.resume() : _tour.pause();
      return;
    }
    _schedule();
  }

  /// From Settings: back to Dashboard / Home, then [tour] from its first
  /// card.
  void _startReplay(TutorialTour tour) => unawaited(_replay(tour));

  Future<void> _replay(TutorialTour tour) async {
    _timer?.cancel();
    _timer = null;
    _decided = true;
    final actions = _actions();
    await actions.goToTab(actions.homeTab);
    await Future<void>.delayed(TutorialGate.settle);
    if (!mounted) return;
    await _tour.start(
      widget.platform,
      scope: _scope(),
      actions: actions,
      tour: tour,
      replay: true,
    );
  }

  /// The app tour was just finished with Done: the voice tour follows,
  /// once, for someone who hasn't seen it.
  Future<void> _offerVoice() async {
    final seen = await _repo.hasSeen(
      widget.platform,
      profile: ref.read(doctorProfileProvider).value,
      tour: TutorialTour.voice,
    );
    if (seen || !mounted) return;
    // Let the app tour's ending settle (it goes back to Dashboard / Home).
    await Future<void>.delayed(TutorialGate.settle);
    if (!mounted || !_onTop || ref.read(tutorialControllerProvider).running) {
      return;
    }
    await _tour.start(
      widget.platform,
      scope: _scope(),
      actions: _actions(),
      tour: TutorialTour.voice,
    );
  }

  Future<bool> _onBack() async {
    final s = ref.read(tutorialControllerProvider);
    if (!s.visible || s.platform != widget.platform) return false;
    s.isFirst ? _tour.skip() : _tour.back();
    return true;
  }

  TutorialScope _scope() => TutorialScope(
    access: ref.read(clinicAccessProvider).value,
    modules:
        ref.read(tutorialModulesProvider).value ??
        DoctorFeatureGuard.defaultModules,
    demo: DemoSessionService.isDemoMode,
  );

  TutorialActions _actions() => switch (widget.platform) {
    TutorialPlatform.desktop => TutorialActions(
      homeTab: DesktopTab.dashboard,
      goToTab: _openDesktopTab,
    ),
    TutorialPlatform.mobile => TutorialActions(
      homeTab: MobileTab.home,
      goToTab: _openPhoneTab,
    ),
  };

  /// Desktop screens fade in over about 220 ms.
  Future<void> _openDesktopTab(int tab) async {
    if (!mounted) return;
    final moving = ref.read(shellCurrentTabProvider) != tab;
    ref.read(shellNavigatorProvider)?.call(tab);
    if (moving) await Future<void>.delayed(CruMotion.standard);
  }

  /// The phone's pages slide over 340 ms.
  Future<void> _openPhoneTab(int tab) async {
    if (!mounted) return;
    final moving = ref.read(mobileCurrentTabProvider) != tab;
    ref.read(mobileTabSwitcherProvider)?.call(tab);
    if (moving) await Future<void>.delayed(const Duration(milliseconds: 380));
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt when a dialog or page covers the shell and when it closes,
    // when the profile, role or plan loads, and when a tour starts or ends.
    _onTop = ModalRoute.isCurrentOf(context) ?? true;
    ref.watch(doctorProfileProvider);
    ref.watch(clinicAccessProvider);
    ref.watch(tutorialModulesProvider);
    ref.watch(tutorialControllerProvider.select((s) => s.running));
    ref.listen(tutorialControllerProvider, (prev, next) {
      if (prev != null &&
          next.endCount != prev.endCount &&
          next.ended == TutorialEnd.completed &&
          next.tour == TutorialTour.app &&
          next.platform == widget.platform) {
        unawaited(_offerVoice());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());

    if (Router.maybeOf(context) == null) return widget.child;
    return BackButtonListener(
      onBackButtonPressed: _onBack,
      child: widget.child,
    );
  }
}
