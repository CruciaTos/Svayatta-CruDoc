import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/errors/queue_exceptions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/core/utils/app_notice.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/mobile/display_corners.dart';
import 'package:doctor_management_app/features/mobile/island_geometry.dart';
import 'package:doctor_management_app/features/mobile/island_surface.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/tutorial/presentation/tutorial_target.dart';
import 'package:doctor_management_app/features/voice/voice_controller.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What the voice engine is doing, handed to the island by the overlay.
class IslandVoice {
  const IslandVoice({
    required this.available,
    required this.listening,
    required this.heard,
    required this.understood,
    required this.ready,
    required this.need,
    required this.error,
    required this.ask,
    required this.level,
    required this.onTalkStart,
    required this.onTalkEnd,
    required this.onPick,
  });

  /// Voice works on this device (the phone's own speech recognizer).
  final bool available;
  final bool listening;
  final String heard;
  final String? understood;
  final bool ready;
  final String? need;
  final String? error;
  final VoiceAsk? ask;
  final ValueListenable<double> level;
  final VoidCallback onTalkStart;
  final VoidCallback onTalkEnd;
  final void Function(int index) onPick;
}

// ---------------------------------------------------------------------------
// What the island reads from the app. Records compare by value, so the island
// rebuilds only when one of these fields really changes, not on every
// dashboard refresh.

typedef IslandGlance = ({int seen, int total, int waiting});
typedef IslandServing = ({
  String? entryId,
  String name,
  String firstName,
  String detail,
});
typedef IslandUp = ({
  String name,
  String details,
  int waitMinutes,
  bool isNextInCallOrder,
});
typedef IslandQueue = ({
  IslandGlance? glance,
  IslandServing? serving,
  IslandUp? up,
  DateTime? nextBooking,
  String? nextBookingName,
});
typedef IslandPatient = ({
  String id,
  String name,
  String firstName,
  String ageSex,
  DateTime? lastVisit,
  double balance,
});
typedef IslandContext = ({int tab, IslandQueue queue, IslandPatient? patient});

IslandQueue _queueSlice(DashboardData d) {
  final items = d.schedule ?? const <ScheduleItem>[];
  ScheduleItem? serving;
  for (final s in items) {
    if (s.status == ScheduleStatus.inConsultation) {
      serving = s;
      break;
    }
  }
  final g = d.glance;
  final up = d.upNext;
  final nb = d.nextBooking;
  // The booking's name only when exactly one visit is at that time.
  String? nbName;
  if (nb != null) {
    final at = items.where((s) => s.time == nb).toList();
    if (at.length == 1) nbName = at.first.name;
  }
  return (
    glance: g == null
        ? null
        : (seen: g.seen, total: g.total, waiting: g.waiting),
    serving: serving == null
        ? null
        : (
            entryId: serving.queueEntryId,
            name: serving.name,
            firstName: serving.firstName,
            detail: [?serving.ageSex, ?serving.reason].join(' · '),
          ),
    up: up == null
        ? null
        : (
            name: up.name,
            details: up.details,
            waitMinutes: up.waitMinutes,
            isNextInCallOrder: up.isNextInCallOrder,
          ),
    nextBooking: nb,
    nextBookingName: nbName,
  );
}

IslandPatient? _patientSlice(AsyncValue<PatientSummary?> v) {
  final s = v.value;
  if (s == null) return null;
  final p = s.patient;
  return (
    id: s.id,
    name: p.fullName.trim(),
    firstName: p.firstName.trim(),
    ageSex: PatientFormat.ageSex(p),
    lastVisit: s.lastVisit?.scheduledStart,
    balance: s.balance,
  );
}

final islandContextProvider = Provider<IslandContext>((ref) {
  final queue = ref.watch(dashboardDataProvider.select(_queueSlice));
  final tab = ref.watch(mobileCurrentTabProvider);
  final id = ref.watch(
    patientsListControllerProvider.select((s) => s.detailsId),
  );
  final patient = tab == MobileTab.patients && id != null
      ? ref.watch(patientSummaryProvider(id).select(_patientSlice))
      : null;
  return (tab: tab, queue: queue, patient: patient);
});

// The island is always black, so it uses the dark ("eve") tone pairs from
// mobileTone() in mobile_kit.dart: amber text 0xFFFFB340, violet 0xFFCDB0F2.
const _white = Colors.white;
const _white60 = Color(0x99FFFFFF);
const _white10 = Color(0x1AFFFFFF);
const _black = Color(0xFF000000);
const _amber = Color(0xFFFFB340);
const _violet = Color(0xFFCDB0F2);

enum _K {
  ask,
  listening,
  thinking,
  reply,
  notice,
  peekPatient,
  peekSchedule,
  peekQueue,
  rest,
}

/// The phone's island: a black capsule in the status bar, like the iPhone's.
/// At rest it carries the live queue. Tap it for what's happening on the
/// current screen; hold it to talk. It grows into whatever it is showing and
/// shrinks back after.
class MobileIsland extends ConsumerStatefulWidget {
  const MobileIsland({
    super.key,
    required this.voice,
    required this.navContext,
  });

  final IslandVoice voice;

  /// A context under the app's navigator, for dialogs.
  final BuildContext Function() navContext;

  @override
  ConsumerState<MobileIsland> createState() => _MobileIslandState();
}

class _MobileIslandState extends ConsumerState<MobileIsland> {
  bool _peek = false;
  String? _notice;
  AppNotice? _appNotice;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    AppNotices.current.addListener(_onAppNotice);
    DisplayCorners.android.addListener(_onCorners);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) DisplayCorners.load(MediaQuery.devicePixelRatioOf(context));
    });
  }

  void _onCorners() {
    if (mounted) setState(() {});
  }

  /// A message from the app (a SnackBar's old job): grow to show it.
  void _onAppNotice() {
    final n = AppNotices.current.value;
    _noticeTimer?.cancel();
    setState(() {
      _appNotice = n;
      _notice = n?.text;
      if (n != null) _peek = false;
    });
  }

  /// Android gives taps in the status bar strip to the system (they pull
  /// the notification shade), so an island over the camera could never be
  /// tapped or held. While the island shows, the status bar is hidden and
  /// the island owns the top strip. A swipe from the top still reveals the
  /// bar; it hides again a few seconds later. iOS keeps its status bar:
  /// taps there reach the app.
  bool _barHidden = false;
  AppLifecycleListener? _life;

  static bool get _ownsStatusBar =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _syncStatusBar(bool hide) {
    if (!_ownsStatusBar || hide == _barHidden) return;
    _barHidden = hide;
    if (hide) {
      DisplayCorners.hideStatusBar();
      // Flutter re-applies its own system UI on resume; hide again.
      _life ??= AppLifecycleListener(
        onResume: () {
          if (_barHidden) DisplayCorners.hideStatusBar();
        },
      );
    } else {
      _life?.dispose();
      _life = null;
      DisplayCorners.showStatusBar();
    }
  }

  @override
  void dispose() {
    _syncStatusBar(false);
    AppNotices.current.removeListener(_onAppNotice);
    DisplayCorners.android.removeListener(_onCorners);
    AppNotices.hosted = false;
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _say(String text) {
    _noticeTimer?.cancel();
    setState(() {
      _appNotice = null;
      _notice = text;
      _peek = false;
    });
    _noticeTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  /// The state to show, by priority: ask, listening, thinking, reply,
  /// notice, peek, rest.
  _K _kind(IslandContext c) {
    final v = widget.voice;
    if (v.ask != null) return _K.ask;
    if (v.listening) return _K.listening;
    final u = v.understood;
    if (u == 'Thinking…') return _K.thinking;
    if (u != null && u.isNotEmpty) return _K.reply;
    if (_notice != null) return _K.notice;
    if (_peek) {
      if (c.tab == MobileTab.patients && c.patient != null) {
        return _K.peekPatient;
      }
      if (c.tab == MobileTab.schedule) return _K.peekSchedule;
      return _K.peekQueue;
    }
    return _K.rest;
  }

  void _closeTransient() {
    _noticeTimer?.cancel();
    setState(() {
      _notice = null;
      _peek = false;
    });
  }

  void _holdStart() {
    MobileHaptics.commit();
    if (!widget.voice.available) {
      _say(widget.voice.error ?? "Voice isn't available on this device");
      return;
    }
    setState(() => _peek = false);
    widget.voice.onTalkStart();
  }

  void _holdEnd() {
    if (widget.voice.available) widget.voice.onTalkEnd();
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() => _peek = false);
    try {
      await action();
    } catch (e, st) {
      debugPrint('island action failed: $e\n$st');
      _say(
        e is QueueException ? e.message : "Couldn't complete that. Try again.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn =
        ref.watch(authStateProvider).value != null ||
        DemoSessionService.isDemoMode;
    AppNotices.hosted = signedIn;
    _syncStatusBar(signedIn);
    if (!signedIn) return const SizedBox.shrink();

    final ctx = ref.watch(islandContextProvider);
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.viewPaddingOf(context);
    final geo = IslandGeometry.resolve(
      screen: screen,
      viewPadding: pad,
      features: MediaQuery.displayFeaturesOf(context),
      platform: defaultTargetPlatform,
      cornerRadius: DisplayCorners.resolve(pad.top),
    );
    final kind = _kind(ctx);
    final rest = kind == _K.rest;
    final peeking =
        kind == _K.peekPatient ||
        kind == _K.peekSchedule ||
        kind == _K.peekQueue;

    final shape = rest
        ? IslandShape(
            minWidth: geo.restWidth,
            minHeight: geo.h,
            top: geo.restTop,
            centerX: geo.restCenterX,
            rTop: geo.h / 2,
            rBot: geo.h / 2,
            stadium: true,
          )
        : IslandShape(
            width: geo.grownWidth,
            minHeight: geo.grownMinHeight,
            top: geo.grownTop,
            centerX: screen.width / 2,
            rTop: geo.rTop,
            rBot: geo.rBot,
          );

    final canTap =
        rest || peeking || kind == _K.notice; // other states ignore taps
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Tapping anywhere else closes a peek. Always in the tree (only
          // its pointer handling toggles), so the surface below keeps its
          // place in the Stack and its animation state.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !peeking,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _peek = false),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: geo.restRect,
            child: IgnorePointer(
              child: TutorialAnchor(
                target: TutorialTarget.island,
                shape: TutorialShape.stadium,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onTap: !canTap
                  ? null
                  : () {
                      MobileHaptics.tap();
                      _noticeTimer?.cancel();
                      setState(() {
                        _notice = null;
                        _peek = !_peek;
                      });
                    },
              onLongPressStart: (_) => _holdStart(),
              onLongPressEnd: (_) => _holdEnd(),
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < -200) _closeTransient();
              },
              child: IslandSurface(
                stateKey: kind,
                shape: shape,
                superellipse: geo.useSuperellipse,
                child: _content(kind, ctx, geo),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Content -----------------------------------------------------------

  Widget _content(_K kind, IslandContext c, IslandGeometry geo) {
    final v = widget.voice;
    switch (kind) {
      case _K.rest:
        return _rest(c.queue, geo);
      case _K.ask:
        return _ask(v.ask!, geo);
      case _K.listening:
        return _grown(
          geo,
          left: _lead(_LevelBars(level: v.level), 'Listening', _white60),
          right: _caption('Release to send', _white60),
          body: v.heard.isEmpty
              ? null
              : Text(
                  v.heard,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MobileType.callout.tint(_white),
                ),
        );
      case _K.thinking:
        return _grown(
          geo,
          left: _lead(_sparkle(), 'Thinking', _white),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (v.heard.isNotEmpty) ...[
                Text(
                  v.heard,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MobileType.subhead.tint(_white60),
                ),
                const SizedBox(height: 10),
              ],
              const _Shimmer(),
            ],
          ),
        );
      case _K.reply:
        final hint = v.ready ? 'Say "confirm"' : v.need;
        return _grown(
          geo,
          left: _lead(_sparkle(), 'CruDoc AI', _white),
          right: hint == null || hint.isEmpty ? null : _caption(hint, _violet),
          body: Text(
            v.understood!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: MobileType.callout.tint(_white),
          ),
        );
      case _K.notice:
        return _notice_(geo);
      case _K.peekPatient:
        return _peekPatient(c, geo);
      case _K.peekSchedule:
        return _peekSchedule(c, geo);
      case _K.peekQueue:
        return _peekQueue(c, geo);
    }
  }

  // ---- Shared pieces -----------------------------------------------------

  Widget _caption(String text, Color color, {bool tabular = false}) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: (tabular ? MobileType.caption.tabular : MobileType.caption).w600
        .tint(color),
  );

  Widget _sparkle() =>
      CruIcon(CruIcons.sparkle, size: 14, strokeWidth: 2, color: _violet);

  Widget _dot(Color color) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );

  /// A band label: [lead] then [text].
  Widget _lead(Widget lead, String text, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      lead,
      const SizedBox(width: 8),
      Flexible(child: _caption(text, color)),
    ],
  );

  /// The header row of every grown state: [left] in the top-left corner,
  /// [right] in the top-right, halves of equal width so nothing ever sits
  /// under the camera. Its text sits as far from the island's top edge as
  /// from its side ([IslandGeometry.contentPadding] both ways), so each
  /// label lands on the corner's 45° line, evenly inset from both edges.
  Widget _band(IslandGeometry geo, Widget left, Widget? right) {
    final half = math.max(0.0, geo.bandHalf - IslandGeometry.contentPadding);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IslandGeometry.contentPadding,
        IslandGeometry.contentPadding - _capInset,
        IslandGeometry.contentPadding,
        0,
      ),
      child: Row(
        children: [
          SizedBox(
            width: half,
            child: Align(alignment: Alignment.centerLeft, child: left),
          ),
          SizedBox(width: geo.cameraGap + 2 * IslandGeometry.bandMargin),
          SizedBox(
            width: half,
            child: Align(
              alignment: Alignment.centerRight,
              child: right ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  /// Space between the top of a caption's line box and the top of its
  /// capitals, so the visible text (not its box) is inset evenly.
  static const double _capInset = 4;

  Widget _grown(
    IslandGeometry geo, {
    required Widget left,
    Widget? right,
    Widget? body,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _band(geo, left, right),
      if (body != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            IslandGeometry.contentPadding,
            12,
            IslandGeometry.contentPadding,
            20,
          ),
          child: body,
        )
      else
        const SizedBox(height: 20),
    ],
  );

  Widget _capsule(
    String label, {
    required bool filled,
    required VoidCallback onTap,
    CruIconData? glyph,
    double height = 44,
    bool expand = false,
  }) {
    final fg = filled ? _black : _white;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: MobileType.callout.w600.tint(fg),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        MobileHaptics.tap();
        onTap();
      },
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: ShapeDecoration(
          color: filled ? _white : _white10,
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (glyph != null) ...[
              CruIcon(glyph, size: 14, strokeWidth: 2.4, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(child: text),
          ],
        ),
      ),
    );
  }

  // ---- Rest --------------------------------------------------------------

  /// The resting pill, always the live queue. Its middle stays empty, where
  /// the camera sits; the state reads at its ends, in two halves of equal
  /// width so the gap is exactly under the camera.
  Widget _rest(IslandQueue q, IslandGeometry geo) {
    final serving = q.serving;
    final waiting = q.glance?.waiting ?? 0;
    Widget? left;
    Widget? right;
    if (serving != null) {
      left = _dotText(CruBrand.ink400, serving.firstName);
      if (waiting > 0) right = _caption('+$waiting', _amber, tabular: true);
    } else if (waiting > 0) {
      left = _dotText(_amber, '$waiting');
      right = _caption('waiting', _white, tabular: true);
    }
    // Nothing live: the bare pill over the camera (hold still talks).

    Widget ghost(Widget? w) => w == null
        ? const SizedBox.shrink()
        : Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: w,
          );
    // Each half's cap, so the whole pill stays within restMaxWidth.
    const margin = IslandGeometry.bandMargin - 2;
    final halfMax = math.max(
      0.0,
      (geo.restMaxWidth - geo.cameraGap - geo.h * 0.6) / 2 - 2 * margin,
    );
    Widget half(Widget? shown, Widget? other, Alignment a) {
      if (shown == null && other == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: margin),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: halfMax),
          child: Stack(alignment: a, children: [ghost(other), ?shown]),
        ),
      );
    }

    return SizedBox(
      height: geo.h,
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: geo.h * 0.3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              half(left, right, Alignment.centerRight),
              SizedBox(width: geo.cameraGap),
              half(right, left, Alignment.centerLeft),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dotText(Color dot, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _dot(dot),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: MobileType.caption.w600.tabular.tint(_white),
        ),
      ),
    ],
  );

  // ---- Ask / notice ------------------------------------------------------

  Widget _ask(VoiceAsk ask, IslandGeometry geo) {
    final opts = ask.options;
    final inline =
        opts.length <= 2 &&
        opts.every((o) => o.detail == null && o.label.length <= 16);
    final Widget choices;
    if (opts.isEmpty) {
      choices = const SizedBox.shrink();
    } else if (inline) {
      choices = Row(
        children: [
          for (var i = 0; i < opts.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _capsule(
                opts[i].label,
                filled: i == 0,
                expand: true,
                onTap: () => widget.voice.onPick(i),
              ),
            ),
          ],
        ],
      );
    } else {
      choices = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < opts.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                MobileHaptics.tap();
                widget.voice.onPick(i);
              },
              child: Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: ShapeDecoration(
                  color: _white10,
                  shape: cruShape(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(opts[i].label, style: MobileType.callout.tint(_white)),
                    if (opts[i].detail != null)
                      Text(
                        opts[i].detail!,
                        style: MobileType.caption.tint(_white60),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return _grown(
      geo,
      left: _lead(_sparkle(), 'Confirm', _white),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(ask.prompt, style: MobileType.headline.tint(_white)),
          SizedBox(height: inline ? 12 : 4),
          choices,
        ],
      ),
    );
  }

  Widget _notice_(IslandGeometry geo) {
    final n = _appNotice;
    final change = n?.from != null && n?.to != null
        ? '${n!.from} → ${n.to}'
        : null;
    final action = n?.actionLabel;
    return _grown(
      geo,
      left: _lead(_dot(_white60), change ?? 'CruDoc', _white60),
      body: Row(
        children: [
          Expanded(
            child: Text(
              _notice!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MobileType.callout.tint(_white),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            _capsule(
              action,
              filled: true,
              height: 36,
              onTap: () {
                final cur = _appNotice;
                AppNotices.clear();
                cur?.onAction?.call();
              },
            ),
          ],
        ],
      ),
    );
  }

  // ---- Peeks -------------------------------------------------------------

  /// Hairline, stats left, the voice hint right. The hint drops to its own
  /// line when large system text leaves no room for both.
  Widget _footer(IslandQueue q, {String? hold}) {
    final g = q.glance;
    final talk = widget.voice.available;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Container(height: 1, color: _white10),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (g != null) ...[
                  _stat('${g.seen}/${g.total}', 'seen'),
                  const SizedBox(width: 18),
                  _stat('${g.waiting}', 'waiting'),
                ],
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CruIcon(
                  CruIcons.mic,
                  size: 15,
                  strokeWidth: 2,
                  color: talk ? CruBrand.ink300 : _white60,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    talk ? (hold ?? 'Hold to talk') : 'Voice off',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MobileType.caption.tint(_white60),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(String value, String label) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: value, style: MobileType.callout.tabular.tint(_white)),
        TextSpan(text: ' $label', style: MobileType.caption.tint(_white60)),
      ],
    ),
  );

  Widget _peekPatient(IslandContext c, IslandGeometry geo) {
    final p = c.patient!;
    final sub = [
      if (p.ageSex.isNotEmpty) p.ageSex,
      if (p.lastVisit != null)
        'Last visit ${DashFormat.shortDate(p.lastVisit!)}',
    ].join(' · ');
    return _grown(
      geo,
      left: _caption('Patient', _white),
      right: p.balance > 0
          ? _caption(
              '${DashFormat.rupees(p.balance)} due',
              _amber,
              tabular: true,
            )
          : null,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Grey monogram: patient avatars are never coloured.
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _white10,
                ),
                child: Text(
                  CruMonogram.initialsOf(p.name),
                  style: MobileType.callout.w600.tint(_white60),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MobileType.title2.tint(_white),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileType.subhead.tint(_white60),
                      ),
                  ],
                ),
              ),
            ],
          ),
          _footer(
            c.queue,
            hold: p.firstName.isEmpty
                ? 'Hold to ask'
                : 'Hold to ask about ${p.firstName}',
          ),
        ],
      ),
    );
  }

  Widget _peekSchedule(IslandContext c, IslandGeometry geo) {
    final q = c.queue;
    final g = q.glance;
    final nb = q.nextBooking;
    final next = nb == null
        ? 'Nothing else booked today'
        : q.nextBookingName == null
        ? 'Next at ${DashFormat.time(nb)}'
        : 'Next at ${DashFormat.time(nb)} · ${q.nextBookingName}';
    return _grown(
      geo,
      left: _caption('Today', _white),
      right: g == null
          ? null
          : _caption('${g.seen}/${g.total} seen', _white60, tabular: true),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            next,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MobileType.title2.tabular.tint(_white),
          ),
          _footer(q),
        ],
      ),
    );
  }

  Widget _peekQueue(IslandContext c, IslandGeometry geo) {
    final q = c.queue;
    final serving = q.serving;
    final up = q.up;
    final nav = widget.navContext;
    final waiting = q.glance?.waiting ?? 0;

    final String title;
    final String? detail;
    final Widget? action;
    if (up != null) {
      title = up.name;
      detail = serving != null
          ? 'Next up · ${up.details}'
          : [
              'Waiting ${DashFormat.minutes(up.waitMinutes)}',
              if (up.details.isNotEmpty) up.details,
            ].join(' · ');
      action = _capsule(
        serving != null ? 'Finish & start' : 'Start',
        filled: true,
        height: 40,
        glyph: CruIcons.play,
        onTap: () => _act(() async {
          if (serving?.entryId != null) {
            await ref.read(queueRepositoryProvider).complete(serving!.entryId!);
          }
          if (serving == null && !up.isNextInCallOrder) {
            ref.read(mobileTabSwitcherProvider)?.call(MobileTab.schedule);
            return;
          }
          final called = await ref.read(queueRepositoryProvider).callNext();
          await ref.read(queueRepositoryProvider).startConsultation(called.id);
        }),
      );
    } else if (serving != null) {
      title = serving.name;
      detail = serving.detail;
      action = serving.entryId == null
          ? null
          : _capsule(
              'Finish',
              filled: true,
              height: 40,
              glyph: CruIcons.check,
              onTap: () => _act(
                () => ref
                    .read(queueRepositoryProvider)
                    .complete(serving.entryId!),
              ),
            );
    } else {
      title = q.nextBooking == null
          ? 'Nothing else booked today'
          : 'Next at ${DashFormat.time(q.nextBooking!)}';
      detail = null;
      action = _capsule(
        'Check in',
        filled: true,
        height: 40,
        glyph: CruIcons.userCheck,
        onTap: () => _act(() => DashboardActions.newVisit(nav())),
      );
    }

    final Widget left = serving != null
        ? _lead(_dot(CruBrand.ink400), 'In consultation', _white)
        : up != null
        ? _lead(_dot(_amber), 'Up next', _white)
        : _caption('No one waiting', _white60);

    return _grown(
      geo,
      left: left,
      right: waiting > 0
          ? _caption('$waiting waiting', _amber, tabular: true)
          : null,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MobileType.title2.tabular.tint(_white),
                    ),
                    if (detail != null && detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileType.subhead.tint(_white60),
                      ),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 12), action],
            ],
          ),
          _footer(q),
        ],
      ),
    );
  }
}

// ---- Small animated pieces (each repaints on its own, no rebuilds) ---------

/// Five bars that follow the microphone level. Repaints from [level] alone.
class _LevelBars extends StatefulWidget {
  const _LevelBars({required this.level});

  final ValueListenable<double> level;

  @override
  State<_LevelBars> createState() => _LevelBarsState();
}

class _LevelBarsState extends State<_LevelBars> {
  late final _BarsPainter _painter = _BarsPainter(widget.level);

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(27, 20), painter: _painter);
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.level) : super(repaint: level);

  final ValueListenable<double> level;
  double _smooth = 0;
  static const _k = [0.5, 0.8, 1.0, 0.7, 0.45];
  static final _paint = Paint()..color = _violet;

  @override
  void paint(Canvas canvas, Size size) {
    // Ease toward the live level so the bars move, not flicker.
    _smooth += (level.value.clamp(0.0, 1.0) - _smooth) * 0.45;
    for (var i = 0; i < _k.length; i++) {
      final h = 5 + 15 * (_smooth * _k[i]).clamp(0.0, 1.0);
      final x = i * 6.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, 3, h),
          const Radius.circular(1.5),
        ),
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => false;
}

/// A thin violet line with a highlight running along it. Its own ticker,
/// alive only while the Thinking state is mounted.
class _Shimmer extends StatefulWidget {
  const _Shimmer();

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 2, child: CustomPaint(painter: _ShimmerPainter(_c)));
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter(this.t) : super(repaint: t);

  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(1),
    );
    canvas.drawRRect(track, Paint()..color = _violet.withValues(alpha: 0.18));
    canvas.save();
    canvas.clipRRect(track);
    final w = size.width * 0.4;
    final x = t.value * (size.width + w) - w;
    final r = Rect.fromLTWH(x, 0, w, size.height);
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          colors: [
            _violet.withValues(alpha: 0),
            _violet,
            _violet.withValues(alpha: 0),
          ],
        ).createShader(r),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.t != t;
}
