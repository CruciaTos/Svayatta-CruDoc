import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
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

  /// Voice works on this device (the clinic PC today, not phones).
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

enum _Mode { compact, expanded, listening, result, question, notice }

/// The phone's island: a black capsule in the status bar, like the
/// iPhone's. At rest it carries the live queue (who's with you, how many
/// are waiting). Tap it for who's next with one-tap actions; hold it to
/// talk. It grows into whatever it is showing and shrinks back after.
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
  bool _expanded = false;
  String? _notice;
  Timer? _noticeTimer;

  static const _spring = Cubic(0.2, 1.18, 0.32, 1);
  static const _morph = Duration(milliseconds: 420);
  static const _black = Color(0xFF000000);

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _say(String text) {
    _noticeTimer?.cancel();
    setState(() {
      _notice = text;
      _expanded = false;
    });
    _noticeTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  _Mode get _mode {
    final v = widget.voice;
    if (v.ask != null) return _Mode.question;
    if (v.listening) return _Mode.listening;
    if (_notice != null) return _Mode.notice;
    if (v.understood != null && v.understood!.isNotEmpty) return _Mode.result;
    if (_expanded) return _Mode.expanded;
    return _Mode.compact;
  }

  void _holdStart() {
    MobileHaptics.commit();
    if (!widget.voice.available) {
      _say(
        widget.voice.error ??
            'Voice runs on the clinic PC for now. Phones are next.',
      );
      return;
    }
    setState(() => _expanded = false);
    widget.voice.onTalkStart();
  }

  void _holdEnd() {
    if (widget.voice.available) widget.voice.onTalkEnd();
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() => _expanded = false);
    try {
      await action();
    } catch (e) {
      _say('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn =
        ref.watch(authStateProvider).value != null ||
        DemoSessionService.isDemoMode;
    if (!signedIn) return const SizedBox.shrink();

    final data = ref.watch(dashboardDataProvider);
    final pad = MediaQuery.paddingOf(context);
    final screen = MediaQuery.sizeOf(context);
    final bar = pad.top >= 20 ? pad.top : 0.0;
    final compactH = bar == 0 ? 34.0 : (bar - 10).clamp(26.0, 37.0);
    final top = bar == 0 ? 8.0 : ((bar - compactH) / 2).clamp(2.0, 14.0);
    final mode = _mode;
    final wide = (screen.width - 16).clamp(0.0, 420.0);

    final (double? width, double radius) = switch (mode) {
      _Mode.compact => (null, compactH / 2),
      _Mode.listening ||
      _Mode.result ||
      _Mode.notice => ((screen.width - 40).clamp(0.0, 360.0), 24),
      _Mode.expanded || _Mode.question => (wide, 32),
    };

    final island = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        MobileHaptics.tap();
        setState(() {
          _notice = null;
          _expanded = !_expanded;
        });
      },
      onLongPressStart: (_) => _holdStart(),
      onLongPressEnd: (_) => _holdEnd(),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) setState(() => _expanded = false);
      },
      child: AnimatedContainer(
        duration: _morph,
        curve: _spring,
        width: width,
        constraints: BoxConstraints(minHeight: compactH),
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: _black,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          shadows: mode == _Mode.compact
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: AnimatedSize(
          duration: _morph,
          curve: _spring,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            reverseDuration: const Duration(milliseconds: 90),
            switchInCurve: const Interval(0.3, 1, curve: Curves.easeOut),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [
                for (final p in previous)
                  Positioned.fill(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      maxHeight: double.infinity,
                      child: p,
                    ),
                  ),
                ?current,
              ],
            ),
            child: KeyedSubtree(
              key: ValueKey(mode),
              child: switch (mode) {
                _Mode.compact => _compact(data, compactH),
                _Mode.expanded => _card(data),
                _Mode.listening => _listening(),
                _Mode.result => _line(
                  widget.voice.understood!,
                  hint: widget.voice.ready
                      ? 'Say "confirm"'
                      : widget.voice.need,
                ),
                _Mode.notice => _line(_notice!),
                _Mode.question => _question(),
              },
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        // Tapping anywhere else closes the open island.
        if (mode == _Mode.expanded)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = false),
            ),
          ),
        Positioned(
          top: top,
          left: 0,
          right: 0,
          child: Center(
            child: Material(type: MaterialType.transparency, child: island),
          ),
        ),
      ],
    );
  }

  static const _white = Colors.white;
  static final _white60 = Colors.white.withValues(alpha: 0.6);

  ScheduleItem? _serving(DashboardData d) {
    for (final s in d.schedule ?? const <ScheduleItem>[]) {
      if (s.status == ScheduleStatus.inConsultation) return s;
    }
    return null;
  }

  /// The resting capsule. Its middle stays empty, where a phone's front
  /// camera usually sits; the live state reads at its ends.
  Widget _compact(DashboardData d, double h) {
    final serving = _serving(d);
    final waiting = d.glance?.waiting ?? 0;
    // Without voice (phones, for now) there is no mic: the state splits
    // around the camera, its two halves the same width so the gap sits
    // right under it, and the capsule stays small.
    final talk = widget.voice.available;
    if (!talk) {
      final Color? dot = serving != null
          ? CruBrand.ink400
          : waiting > 0
          ? const Color(0xFFFF9F0A)
          : null;
      final (String a, String b) = serving != null
          ? (serving.firstName, waiting > 0 ? '+$waiting' : 'now')
          : waiting > 0
          ? ('$waiting', 'waiting')
          : ('', '');
      final style = MobileType.caption.w600.tabular;
      final scaler = MediaQuery.textScalerOf(context);
      double w(String t) => (TextPainter(
        text: TextSpan(text: t, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout()).width;
      final side = (math.max(w(a) + (dot == null ? 0 : 12), w(b)) + 4)
          .ceilToDouble();
      return SizedBox(
        height: h,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: h * 0.38),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: side,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (dot != null) ...[_dot(dot), const SizedBox(width: 5)],
                    Flexible(child: _label(a)),
                  ],
                ),
              ),
              const SizedBox(width: 26),
              SizedBox(
                width: side,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: serving != null && waiting > 0
                      ? _plus(waiting)
                      : _label(b),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final Widget? lead = serving != null
        ? _dotText(CruBrand.ink400, serving.firstName)
        : waiting > 0
        ? _dotText(const Color(0xFFFF9F0A), '$waiting waiting')
        : null;
    return SizedBox(
      height: h,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: h * 0.38),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?lead,
            SizedBox(width: lead == null ? 34 : 28),
            if (serving != null && waiting > 0)
              _plus(waiting)
            else
              CruIcon(CruIcons.mic, size: 15, strokeWidth: 2, color: _white60),
          ],
        ),
      ),
    );
  }

  Widget _dotText(Color dot, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [_dot(dot), const SizedBox(width: 6), _label(text)],
  );

  Widget _dot(Color color) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );

  Widget _label(String text) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 96),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: MobileType.caption.w600.tabular.tint(_white),
    ),
  );

  Widget _plus(int waiting) => Text(
    '+$waiting',
    style: MobileType.caption.w600.tabular.tint(const Color(0xFFFFB340)),
  );

  /// Open: what's happening now and the one thing to do about it.
  Widget _card(DashboardData d) {
    final serving = _serving(d);
    final up = d.upNext;
    final nav = widget.navContext;

    final String label;
    final String title;
    final String? detail;
    final Widget? action;
    if (up != null) {
      label = serving != null
          ? 'With ${serving.firstName} · next up'
          : 'Up next · waiting ${DashFormat.minutes(up.waitMinutes)}';
      title = up.name;
      detail = up.details;
      action = _pill(
        serving != null ? 'Finish & start' : 'Start',
        CruIcons.play,
        () => _act(() async {
          if (serving?.queueEntryId != null) {
            await ref
                .read(queueRepositoryProvider)
                .complete(serving!.queueEntryId!);
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
      label = 'In consultation';
      title = serving.name;
      detail = [?serving.ageSex, ?serving.reason].join(' · ');
      action = serving.queueEntryId == null
          ? null
          : _pill(
              'Finish',
              CruIcons.check,
              () => _act(
                () => ref
                    .read(queueRepositoryProvider)
                    .complete(serving.queueEntryId!),
              ),
            );
    } else {
      label = 'No one waiting';
      title = d.nextBooking == null
          ? 'Nothing else booked today'
          : 'Next at ${DashFormat.time(d.nextBooking!)}';
      detail = null;
      action = _pill(
        'Check in',
        CruIcons.userCheck,
        () => _act(() => DashboardActions.newVisit(nav())),
      );
    }

    final g = d.glance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: MobileType.caption.w600.tint(_white60)),
          const SizedBox(height: 6),
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
                      style: MobileType.title2.tint(_white),
                    ),
                    if (detail != null && detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileType.subhead.tint(_white60),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 12), action],
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          Row(
            children: [
              if (g != null) ...[
                _stat('${g.seen}/${g.total}', 'seen'),
                const SizedBox(width: 18),
                _stat('${g.waiting}', 'waiting'),
              ],
              const Spacer(),
              CruIcon(
                CruIcons.mic,
                size: 15,
                strokeWidth: 2,
                color: widget.voice.available ? CruBrand.ink300 : _white60,
              ),
              const SizedBox(width: 6),
              Text(
                widget.voice.available ? 'Hold to talk' : 'Voice: clinic PC',
                style: MobileType.caption.tint(_white60),
              ),
            ],
          ),
        ],
      ),
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

  Widget _pill(String label, CruIconData icon, VoidCallback onTap) =>
      GestureDetector(
        onTap: () {
          MobileHaptics.commit();
          onTap();
        },
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const ShapeDecoration(
            color: _white,
            shape: StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CruIcon(icon, size: 14, strokeWidth: 2.4, color: _black),
              const SizedBox(width: 6),
              Text(label, style: MobileType.callout.tint(_black)),
            ],
          ),
        ),
      );

  Widget _listening() {
    final v = widget.voice;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          _Bars(level: v.level),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v.heard.isEmpty ? 'Listening…' : v.heard,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MobileType.callout.tint(_white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String text, {String? hint}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MobileType.callout.tint(_white),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 10),
          Text(
            hint,
            style: MobileType.caption.w600.tint(const Color(0xFFCDB0F2)),
          ),
        ],
      ],
    ),
  );

  Widget _question() {
    final ask = widget.voice.ask!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ask.prompt, style: MobileType.headline.tint(_white)),
          const SizedBox(height: 10),
          for (var i = 0; i < ask.options.length; i++)
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
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: cruShape(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ask.options[i].label,
                      style: MobileType.callout.tint(_white),
                    ),
                    if (ask.options[i].detail != null)
                      Text(
                        ask.options[i].detail!,
                        style: MobileType.caption.tint(_white60),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Five bars that follow the microphone level.
class _Bars extends StatelessWidget {
  const _Bars({required this.level});

  final ValueListenable<double> level;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: level,
      builder: (context, v, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final k in const [0.5, 0.8, 1.0, 0.7, 0.45])
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: 5 + 15 * (v * k).clamp(0.0, 1.0),
              decoration: BoxDecoration(
                color: const Color(0xFFCDB0F2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
