import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/tutorial/data/tutorial_repository.dart';
import 'package:doctor_management_app/features/tutorial/domain/tutorial_step.dart';
import 'package:doctor_management_app/features/tutorial/domain/tutorial_steps.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_target.dart';

enum TutorialPhase {
  idle,

  /// Opening the step's tab, scrolling its target into view.
  preparing,

  /// The card is up.
  showing,
}

enum TutorialEnd { completed, skipped, cancelled }

/// How the tour moves the app. The shell's [TutorialGate] supplies these.
class TutorialActions {
  const TutorialActions({required this.goToTab, required this.homeTab});

  /// Opens [tab] (a DesktopTab or MobileTab index) and completes once it
  /// has settled on screen.
  final Future<void> Function(int tab) goToTab;

  /// Dashboard on desktop, Home on the phone: where a tour ends.
  final int homeTab;
}

@immutable
class TutorialState {
  const TutorialState({
    this.phase = TutorialPhase.idle,
    this.platform,
    this.tour = TutorialTour.app,
    this.steps = const [],
    this.index = 0,
    this.spot,
    this.paused = false,
    this.replay = false,
    this.ended,
    this.endCount = 0,
  });

  final TutorialPhase phase;
  final TutorialPlatform? platform;
  final TutorialTour tour;

  /// The steps left for this person: guarded steps they can't open and
  /// steps whose target isn't on screen are taken out.
  final List<TutorialStep> steps;
  final int index;

  /// Where the current step points (null on the welcome card and while
  /// preparing).
  final TutorialSpot? spot;

  /// A dialog or another page is over the shell.
  final bool paused;

  /// Started from Settings.
  final bool replay;

  /// How the last tour ended; [endCount] goes up each time one does.
  final TutorialEnd? ended;
  final int endCount;

  bool get running => phase != TutorialPhase.idle;
  bool get visible => running && !paused;
  bool get showing => phase == TutorialPhase.showing && !paused;

  TutorialStep? get step =>
      running && index >= 0 && index < steps.length ? steps[index] : null;

  bool get isFirst => index == 0;
  bool get isLast => index == steps.length - 1;

  /// "N of M": the welcome card isn't counted.
  int get total => steps.where((s) => !s.isWelcome).length;
  int get position => steps.take(index + 1).where((s) => !s.isWelcome).length;

  String get title => spot?.title ?? step?.title ?? '';
  String get body => spot?.body ?? step?.body ?? '';

  TutorialState copyWith({
    TutorialPhase? phase,
    List<TutorialStep>? steps,
    int? index,
    TutorialSpot? Function()? spot,
    bool? paused,
  }) => TutorialState(
    phase: phase ?? this.phase,
    platform: platform,
    tour: tour,
    steps: steps ?? this.steps,
    index: index ?? this.index,
    spot: spot == null ? this.spot : spot(),
    paused: paused ?? this.paused,
    replay: replay,
    ended: ended,
    endCount: endCount,
  );
}

/// Runs the tour: which step is up, and moving between them.
class TutorialController extends Notifier<TutorialState> {
  static bool _showing = false;

  /// Whether the tour is on screen. Global key handlers (voice's Space
  /// push-to-talk) stand aside while it is.
  static bool get isShowing => _showing;

  TutorialScope _scope = const TutorialScope();
  TutorialActions? _actions;
  List<TutorialStep> _all = const [];
  int _serial = 0;

  /// The tab the tour last opened (null: it hasn't opened one).
  int? _tab;
  final Map<TutorialPlatform, void Function(TutorialTour tour)> _gates = {};

  TutorialRepository get _repo => ref.read(tutorialRepositoryProvider);
  TutorialAnchors get _anchors => ref.read(tutorialAnchorsProvider);

  @override
  TutorialState build() {
    ref.onDispose(() => _showing = false);
    return const TutorialState();
  }

  void _emit(TutorialState next) {
    _showing = next.visible;
    state = next;
  }

  bool _stale(int serial) =>
      !ref.mounted || serial != _serial || !state.running;

  /// The shell on screen registers how to start its tours from Settings.
  void bindGate(
    TutorialPlatform platform,
    void Function(TutorialTour tour) startReplay,
  ) => _gates[platform] = startReplay;

  void unbindGate(
    TutorialPlatform platform,
    void Function(TutorialTour tour) startReplay,
  ) {
    if (_gates[platform] == startReplay) _gates.remove(platform);
  }

  /// "Take the tour again" (or "Voice tour"): the shell for [platform]
  /// starts [tour] from the first step. False when that shell isn't on
  /// screen.
  bool requestReplay(
    TutorialPlatform platform, {
    TutorialTour tour = TutorialTour.app,
  }) {
    final start = _gates[platform];
    if (start == null || state.running) return false;
    start(tour);
    return true;
  }

  String _event(String name) =>
      state.tour == TutorialTour.voice ? 'voice_$name' : name;

  /// Starts [platform]'s [tour] from the welcome card. [steps] replaces
  /// the list (tests).
  Future<void> start(
    TutorialPlatform platform, {
    required TutorialScope scope,
    required TutorialActions actions,
    TutorialTour tour = TutorialTour.app,
    bool replay = false,
    List<TutorialStep>? steps,
  }) async {
    if (state.running) return;
    _scope = scope;
    _actions = actions;
    _tab = null;
    _all = steps ?? tutorialStepsFor(platform, tour);
    final eligible = [
      for (final s in _all)
        if (s.allows(scope)) s,
    ];
    if (eligible.where((s) => !s.isWelcome).isEmpty) return;
    _emit(
      TutorialState(
        phase: TutorialPhase.preparing,
        platform: platform,
        tour: tour,
        steps: eligible,
        replay: replay,
        ended: state.ended,
        endCount: state.endCount,
      ),
    );
    _repo.logEvent(_event('tutorial_started'));
    await _arrive(forward: true, prune: true);
  }

  void next() {
    if (!state.showing) return;
    if (state.isLast) {
      finish();
      return;
    }
    _emit(
      state.copyWith(
        index: state.index + 1,
        phase: TutorialPhase.preparing,
        spot: () => null,
      ),
    );
    unawaited(_arrive(forward: true));
  }

  void back() {
    if (!state.showing || state.isFirst) return;
    _emit(
      state.copyWith(
        index: state.index - 1,
        phase: TutorialPhase.preparing,
        spot: () => null,
      ),
    );
    unawaited(_arrive(forward: false));
  }

  /// Ends at once, no confirmation. Recorded as skipped (unless it is a
  /// replay, which keeps the earlier record).
  void skip() {
    if (!state.running) return;
    _end(TutorialEnd.skipped);
  }

  /// Done on the last card.
  void finish() {
    if (!state.running) return;
    _end(TutorialEnd.completed);
  }

  /// Ends [platform]'s tour without recording it (the window crossed the
  /// breakpoint, or the shell went away). It will show again next time.
  void cancel(TutorialPlatform platform) {
    if (!state.running || state.platform != platform) return;
    _serial++;
    _emit(
      TutorialState(
        tour: state.tour,
        ended: TutorialEnd.cancelled,
        endCount: state.endCount + 1,
      ),
    );
  }

  /// A dialog or page opened over the shell: hide, keeping the step.
  void pause() {
    if (!state.running || state.paused) return;
    _emit(state.copyWith(paused: true));
  }

  void resume() {
    if (!state.running || !state.paused) return;
    _emit(state.copyWith(paused: false));
  }

  /// The step's number in the platform's full list (welcome is 1).
  int _numberOf(TutorialStep? step) =>
      step == null ? 0 : _all.indexWhere((s) => s.id == step.id) + 1;

  void _end(TutorialEnd how) {
    final s = state;
    final platform = s.platform!;
    final lastStep = _numberOf(s.step);
    _serial++;
    final completed = how == TutorialEnd.completed;
    _repo.logEvent(
      _event(
        completed ? 'tutorial_completed' : 'tutorial_skipped_step_$lastStep',
      ),
    );
    // Kept on the ended state so the shell knows which tour finished.
    _emit(
      TutorialState(
        platform: platform,
        tour: s.tour,
        ended: how,
        endCount: s.endCount + 1,
      ),
    );
    unawaited(
      _repo.record(
        platform,
        completed ? TutorialOutcome.completed : TutorialOutcome.skipped,
        lastStep: lastStep,
        replay: s.replay,
        tour: s.tour,
      ),
    );
    final actions = _actions;
    if (actions != null) unawaited(actions.goToTab(actions.homeTab));
  }

  /// The tab [spot] is on (its own, else its step's).
  static int? _tabOf(TutorialStep step, TutorialSpot spot) =>
      spot.tab ?? step.tab;

  /// Whether [step] may have something to show: a spot this person can
  /// open that is on the tree, or one on a tab that isn't open yet.
  bool _mayShow(TutorialStep step) => step.spots.any(
    (spot) =>
        spot.allows(_scope) &&
        (_anchors.isPresent(spot.target) ||
            (_tabOf(step, spot) != null && _tabOf(step, spot) != _tab)),
  );

  Future<void> _open(int tab) async {
    if (tab == _tab) return;
    _tab = tab;
    await _actions!.goToTab(tab);
  }

  /// The first spot of [step] this person can open that is on screen,
  /// opening each spot's tab before looking for it.
  Future<TutorialSpot?> _resolve(TutorialStep step, int serial) async {
    for (final spot in step.spots) {
      if (!spot.allows(_scope)) continue;
      final tab = _tabOf(step, spot);
      if (tab != null && tab != _tab) {
        await _open(tab);
        if (_stale(serial)) return null;
        await SchedulerBinding.instance.endOfFrame;
        if (_stale(serial)) return null;
      }
      if (_anchors.isPresent(spot.target)) return spot;
    }
    return null;
  }

  /// Opens the current step's tab, finds its target and scrolls it into
  /// view. A step with nothing on screen is taken out (so "N of M" stays
  /// true) and the tour moves on in the same direction.
  Future<void> _arrive({required bool forward, bool prune = false}) async {
    final serial = ++_serial;
    final step = state.step;
    if (step == null) return;
    final tab = step.tab;
    if (tab != null) await _open(tab);
    if (_stale(serial)) return;
    await SchedulerBinding.instance.endOfFrame;
    if (_stale(serial)) return;

    if (prune) {
      // Everything on this screen can be checked now; spots on other tabs
      // are checked when the tour gets there.
      final kept = [
        for (final s in state.steps)
          if (s.isWelcome || _mayShow(s)) s,
      ];
      if (kept.where((s) => !s.isWelcome).isEmpty) {
        cancel(state.platform!);
        return;
      }
      _emit(state.copyWith(steps: kept, index: kept.indexOf(step)));
    }

    if (step.isWelcome) {
      _emit(state.copyWith(phase: TutorialPhase.showing, spot: () => null));
      return;
    }
    final spot = await _resolve(step, serial);
    if (_stale(serial)) return;
    if (spot == null) {
      await _drop(forward: forward);
      return;
    }
    await _anchors.ensureVisible(spot.target);
    if (_stale(serial)) return;
    _emit(state.copyWith(phase: TutorialPhase.showing, spot: () => spot));
  }

  Future<void> _drop({required bool forward}) async {
    final steps = [...state.steps]..removeAt(state.index);
    if (steps.where((s) => !s.isWelcome).isEmpty) {
      cancel(state.platform!);
      return;
    }
    var index = forward ? state.index : state.index - 1;
    if (index >= steps.length) {
      // The last step had nothing to show: the tour is done.
      _emit(state.copyWith(steps: steps, index: steps.length - 1));
      finish();
      return;
    }
    if (index < 0) index = 0;
    _emit(state.copyWith(steps: steps, index: index));
    await _arrive(forward: forward);
  }
}

final tutorialControllerProvider =
    NotifierProvider<TutorialController, TutorialState>(TutorialController.new);
