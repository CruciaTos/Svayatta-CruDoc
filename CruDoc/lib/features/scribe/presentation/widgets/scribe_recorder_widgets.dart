import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/scribe/presentation/scribe_session_controller.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_processing_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

String formatScribeDuration(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Icons the scribe needs beyond [CruIcons], drawn the same way.
abstract final class ScribeIcons {
  static const pause = CruIconData('M8.5 5.5v13M15.5 5.5v13');
  static const stop = CruIconData(
    'M7 6.5h10a.5.5 0 0 1 .5.5v10a.5.5 0 0 1-.5.5H7a.5.5 0 0 1-.5-.5V7a.5.5 0 0 1 .5-.5z',
  );
  static const trash = CruIconData(
    'M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 12.5h9l1-12.5',
  );
  static const retry = CruIconData(
    'M4.5 12a7.5 7.5 0 0 1 13-5.1M19.5 12a7.5 7.5 0 0 1-13 5.1M17.5 3.5v3.4h-3.4M6.5 20.5v-3.4h3.4',
  );
  static const lock = CruIconData(
    'M7 10.5V8a5 5 0 0 1 10 0v2.5M6 10.5h12v9.5H6z',
  );
}

/// Live microphone level bars, newest on the right.
class ScribeWaveform extends StatelessWidget {
  const ScribeWaveform({
    super.key,
    required this.levels,
    required this.color,
    this.height = 48,
  });

  final ValueListenable<List<double>> levels;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(
        child: ValueListenableBuilder<List<double>>(
          valueListenable: levels,
          builder: (context, values, _) => CustomPaint(
            painter: _WaveformPainter(values: values, color: color),
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const minBar = 4.0;
    final slot = size.width / values.length;
    final barWidth = (slot * 0.55).clamp(2.0, 5.0);
    final paint = Paint()..strokeCap = StrokeCap.round;
    final mid = size.height / 2;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final h = minBar + (size.height - minBar) * v;
      final x = slot * i + slot / 2;
      paint
        ..color = color.withValues(alpha: 0.25 + 0.75 * v)
        ..strokeWidth = barWidth;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.values != values || old.color != color;
}

/// The consent acknowledgement that gates recording.
class ScribeConsentCard extends StatelessWidget {
  const ScribeConsentCard({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: () => onChanged(!value),
      scaleOnPress: false,
      semanticLabel: 'The patient has agreed to be recorded',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s8,
          CruSpace.s10,
          CruSpace.s16,
          CruSpace.s12,
        ),
        decoration: ShapeDecoration(
          color: value ? c.accentTint : (hovered ? c.hoverFill : c.inset),
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: c.accent,
              checkColor: c.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              side: BorderSide(color: c.separator, width: 1.5),
            ),
            const SizedBox(width: CruSpace.s4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: CruSpace.s10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The patient knows this consultation is being recorded '
                      'and has agreed',
                      style: CruType.row.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s4),
                    Text(
                      'The conversation is transcribed and an AI writes the '
                      'session note from it. The recording is deleted from '
                      'this device as soon as it stops.',
                      style: CruType.caption.tint(c.label2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Start recording": faded, and not tappable, until the patient's
/// consent is ticked.
class ScribeStartButton extends StatelessWidget {
  const ScribeStartButton({super.key, required this.onPressed});

  /// Null while recording can't start yet.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: CruMotion.of(context, CruMotion.fast),
      opacity: onPressed == null ? 0.4 : 1,
      child: CruButton(
        label: 'Start recording',
        icon: CruIcons.mic,
        large: true,
        expand: true,
        onPressed: onPressed,
      ),
    );
  }
}

/// Talk → AI writes the notes → saved to the record.
class ScribeStepsStrip extends StatelessWidget {
  const ScribeStepsStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    const steps = [
      (CruIcons.mic, 'Talk with the patient'),
      (CruIcons.sparkle, 'AI writes the session notes'),
      (CruIcons.fileText, 'Saved to the patient record'),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(top: CruSpace.s10),
              child: CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
            ),
          Expanded(
            child: Column(
              children: [
                CruIconTile(
                  icon: steps[i].$1,
                  tone: i == 1 ? CruTileTone.accent : CruTileTone.neutral,
                ),
                const SizedBox(height: CruSpace.s8),
                Text(
                  steps[i].$2,
                  textAlign: TextAlign.center,
                  style: CruType.caption.tint(c.label2),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "Recording" (a pulsing red dot) or "Paused" (amber).
class ScribeStatusPill extends StatefulWidget {
  const ScribeStatusPill({super.key, required this.paused});

  final bool paused;

  @override
  State<ScribeStatusPill> createState() => _ScribeStatusPillState();
}

class _ScribeStatusPillState extends State<ScribeStatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.paused) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(ScribeStatusPill old) {
    super.didUpdateWidget(old);
    if (!widget.paused && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (widget.paused && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final paused = widget.paused;
    final fg = paused ? c.amberText : c.redText;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s10,
        vertical: CruSpace.s4,
      ),
      decoration: ShapeDecoration(
        color: paused ? c.amberTint : c.redTint,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: CruSpace.s6),
          Text(
            paused ? 'Paused' : 'Recording',
            style: CruType.caption.w600.tint(fg),
          ),
        ],
      ),
    );
  }
}

/// Timer, live waveform, what has been heard, and pause / finish /
/// discard: the recorder on the phone's sheet and the desktop panel.
class ScribeRecorderPanel extends StatelessWidget {
  const ScribeRecorderPanel({
    super.key,
    required this.controller,
    required this.onDiscard,
  });

  final ScribeSessionController controller;

  /// Called when the doctor taps Discard; the host confirms first.
  final VoidCallback onDiscard;

  static const _warnBefore = Duration(minutes: 5);

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final paused = controller.phase == ScribeSessionPhase.paused;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: ScribeStatusPill(paused: paused)),
        const SizedBox(height: CruSpace.s12),
        ValueListenableBuilder<Duration>(
          valueListenable: controller.elapsed,
          builder: (context, elapsed, _) => Text(
            formatScribeDuration(elapsed),
            textAlign: TextAlign.center,
            style: CruType.metric.copyWith(fontSize: 44).tint(c.label),
          ),
        ),
        const SizedBox(height: CruSpace.s16),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s14,
            vertical: CruSpace.s10,
          ),
          decoration: ShapeDecoration(
            color: c.inset,
            shape: cruShape(CruRadius.control),
          ),
          child: ScribeWaveform(
            levels: controller.levels,
            color: paused ? c.label3 : c.redText,
          ),
        ),
        const SizedBox(height: CruSpace.s10),
        ValueListenableBuilder<Duration>(
          valueListenable: controller.elapsed,
          builder: (context, elapsed, _) {
            final remaining =
                ScribeProcessingService.maxRecordingDuration - elapsed;
            final nearLimit = remaining <= _warnBefore;
            return Text(
              nearLimit
                  ? 'Recording stops automatically in '
                        '${formatScribeDuration(remaining)}'
                  : paused
                  ? 'Paused. Resume when the consultation continues.'
                  : 'Talk with the patient as you normally would. Keep the '
                        'device between you.',
              textAlign: TextAlign.center,
              style: nearLimit
                  ? CruType.caption.w600.tint(c.amberText)
                  : CruType.caption.tint(c.label2),
            );
          },
        ),
        const SizedBox(height: CruSpace.s12),
        Container(
          padding: const EdgeInsets.all(CruSpace.s12),
          decoration: ShapeDecoration(
            color: c.aiTint,
            shape: cruShape(CruRadius.control),
          ),
          child: ScribeLiveTranscript(
            transcript: controller.transcript,
            maxHeight: 96,
          ),
        ),
        const SizedBox(height: CruSpace.s20),
        ScribeRecorderControls(controller: controller, onDiscard: onDiscard),
      ],
    );
  }
}

/// Discard, pause / resume and Finish, in one row.
class ScribeRecorderControls extends StatelessWidget {
  const ScribeRecorderControls({
    super.key,
    required this.controller,
    required this.onDiscard,
    this.compact = false,
  });

  final ScribeSessionController controller;
  final VoidCallback onDiscard;

  /// Fits a toolbar: the Finish button keeps its own width.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final paused = controller.phase == ScribeSessionPhase.paused;
    final finish = CruButton(
      label: compact ? 'Finish & write notes' : 'Finish',
      icon: ScribeIcons.stop,
      large: !compact,
      expand: !compact,
      semanticLabel: 'Stop recording and write the session notes',
      onPressed: controller.finish,
    );
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        CruIconButton(
          icon: ScribeIcons.trash,
          semanticLabel: 'Discard recording',
          tooltip: 'Discard recording',
          onPressed: onDiscard,
        ),
        const SizedBox(width: CruSpace.s8),
        CruButton(
          label: paused ? 'Resume' : 'Pause',
          icon: paused ? CruIcons.play : ScribeIcons.pause,
          kind: CruButtonKind.secondary,
          large: !compact,
          onPressed: paused ? controller.resume : controller.pause,
        ),
        const SizedBox(width: CruSpace.s8),
        if (compact) finish else Expanded(child: finish),
      ],
    );
  }
}

/// What the scribe has heard so far, kept scrolled to the newest words.
class ScribeLiveTranscript extends StatefulWidget {
  const ScribeLiveTranscript({
    super.key,
    required this.transcript,
    this.maxHeight,
    this.large = false,
  });

  final ValueListenable<String> transcript;

  /// Grows up to this height, then scrolls. Null fills the space given.
  final double? maxHeight;

  /// Body-size text, for the desktop's full conversation pane.
  final bool large;

  @override
  State<ScribeLiveTranscript> createState() => _ScribeLiveTranscriptState();
}

class _ScribeLiveTranscriptState extends State<ScribeLiveTranscript> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.transcript.addListener(_followNewest);
  }

  @override
  void didUpdateWidget(ScribeLiveTranscript old) {
    super.didUpdateWidget(old);
    if (old.transcript != widget.transcript) {
      old.transcript.removeListener(_followNewest);
      widget.transcript.addListener(_followNewest);
    }
  }

  @override
  void dispose() {
    widget.transcript.removeListener(_followNewest);
    _scroll.dispose();
    super.dispose();
  }

  void _followNewest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final style = widget.large ? CruType.body : CruType.subhead;
    return ValueListenableBuilder<String>(
      valueListenable: widget.transcript,
      builder: (context, text, _) {
        if (text.trim().isEmpty) {
          return Row(
            children: [
              CruIcon(CruIcons.mic, size: 16, color: c.ai),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Text(
                  'Listening… the conversation appears here as it is heard.',
                  style: style.tint(c.label2),
                ),
              ),
            ],
          );
        }
        final body = SingleChildScrollView(
          controller: _scroll,
          child: SizedBox(
            width: double.infinity,
            child: Text(text, style: style.tint(c.label)),
          ),
        );
        final maxHeight = widget.maxHeight;
        return maxHeight == null
            ? body
            : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: body,
              );
      },
    );
  }
}

/// Spinner with progress copy while the AI writes the notes.
class ScribeProcessingPanel extends StatelessWidget {
  const ScribeProcessingPanel({super.key, required this.controller});

  final ScribeSessionController controller;

  static String _stage(int seconds) {
    if (seconds < 4) return 'Reading through the conversation…';
    if (seconds < 30) return 'Writing the session notes…';
    return 'Still working. Long consultations take a little longer…';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          padding: const EdgeInsets.all(CruSpace.s18),
          decoration: ShapeDecoration(
            color: c.aiTint,
            shape: const CircleBorder(),
          ),
          child: CircularProgressIndicator(strokeWidth: 2.5, color: c.ai),
        ),
        const SizedBox(height: CruSpace.s16),
        Text(
          'Writing session notes',
          textAlign: TextAlign.center,
          style: CruType.headline.tint(c.label),
        ),
        const SizedBox(height: CruSpace.s6),
        ValueListenableBuilder<int>(
          valueListenable: controller.processingSeconds,
          builder: (context, seconds, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _stage(seconds),
              key: ValueKey(_stage(seconds)),
              textAlign: TextAlign.center,
              style: CruType.subhead.w500.tint(c.ai),
            ),
          ),
        ),
        const SizedBox(height: CruSpace.s4),
        Text(
          "They're saved to the patient's record as soon as they're ready.",
          textAlign: TextAlign.center,
          style: CruType.caption.tint(c.label2),
        ),
      ],
    );
  }
}

/// Shown when the notes couldn't be written: says why and offers a way
/// on.
class ScribeFailurePanel extends StatelessWidget {
  const ScribeFailurePanel({
    super.key,
    required this.controller,
    required this.onDiscard,
  });

  final ScribeSessionController controller;

  /// Called when the doctor taps Discard; the host confirms first.
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: CruIconTile(icon: CruIcons.warning, tone: CruTileTone.red),
        ),
        const SizedBox(height: CruSpace.s14),
        Text(
          "Couldn't write the session notes",
          textAlign: TextAlign.center,
          style: CruType.headline.tint(c.label),
        ),
        const SizedBox(height: CruSpace.s6),
        Text(
          controller.error ?? 'Something went wrong.',
          textAlign: TextAlign.center,
          style: CruType.subhead.tint(c.label2),
        ),
        const SizedBox(height: CruSpace.s20),
        if (controller.canRetry) ...[
          CruButton(
            label: 'Try again',
            icon: ScribeIcons.retry,
            large: true,
            expand: true,
            onPressed: controller.retry,
          ),
          const SizedBox(height: CruSpace.s10),
        ],
        if (controller.canSaveTranscript) ...[
          CruButton(
            label: 'Save the transcript instead',
            icon: CruIcons.fileText,
            kind: CruButtonKind.secondary,
            large: true,
            expand: true,
            onPressed: controller.saveTranscript,
          ),
          const SizedBox(height: CruSpace.s10),
        ],
        Center(
          child: CruLink(
            label: 'Discard the conversation',
            color: c.redText,
            onPressed: onDiscard,
          ),
        ),
      ],
    );
  }
}

enum ScribeNoticeTone { success, warning, danger, ai }

/// A tinted line or two inside a scribe panel: saved, check this, or why
/// something failed.
class ScribeNotice extends StatelessWidget {
  const ScribeNotice({
    super.key,
    required this.tone,
    required this.message,
    this.title,
  });

  final ScribeNoticeTone tone;
  final String message;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (CruIconData icon, Color fg, Color bg) = switch (tone) {
      ScribeNoticeTone.success => (CruIcons.check, c.greenText, c.greenTint),
      ScribeNoticeTone.warning => (CruIcons.warning, c.amberText, c.amberTint),
      ScribeNoticeTone.danger => (CruIcons.warning, c.redText, c.redTint),
      ScribeNoticeTone.ai => (CruIcons.sparkle, c.ai, c.aiTint),
    };
    return Container(
      padding: const EdgeInsets.all(CruSpace.s12),
      decoration: ShapeDecoration(
        color: bg,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CruIcon(icon, size: 18, color: fg),
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: CruType.subhead.w600.tint(fg)),
                  const SizedBox(height: CruSpace.s2),
                ],
                Text(message, style: CruType.subhead.tint(fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
