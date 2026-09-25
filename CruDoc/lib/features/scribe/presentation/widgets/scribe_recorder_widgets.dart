import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_session_controller.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_draft_form.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_palette.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_processing_service.dart';

String formatScribeDuration(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Confirmation dialog styled like the host screen's other dialogs.
Future<bool> showScribeConfirmDialog(
  BuildContext context, {
  required ScribePalette palette,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = true,
  IconData? icon,
}) async {
  final color = destructive ? palette.danger : palette.primary;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.labelsOutsideCards
          ? AppColors.cardSurface
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(palette.cardRadius + 4),
      ),
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: AppColors.headingFontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: palette.textSecondary,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Live microphone level bars, newest on the right.
class ScribeWaveform extends StatelessWidget {
  const ScribeWaveform({
    super.key,
    required this.levels,
    required this.color,
    this.height = 56,
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

/// The consent acknowledgement that gates recording (§0.8 of the plan).
class ScribeConsentCard extends StatelessWidget {
  const ScribeConsentCard({
    super.key,
    required this.value,
    required this.onChanged,
    required this.palette,
    this.background,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final ScribePalette palette;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background ?? palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(palette.cardRadius),
        side: BorderSide(
          color: value
              ? palette.primary.withValues(alpha: 0.45)
              : palette.cardBorder,
          width: value ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: palette.primary,
                side: BorderSide(color: palette.hint, width: 1.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'The patient knows this consultation is being '
                        'recorded and has agreed',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'The audio is only used to draft your note and is '
                        'deleted from this device once the draft is ready.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Record → AI drafts → you review, as a compact three-step strip.
class ScribeStepsStrip extends StatelessWidget {
  const ScribeStepsStrip({super.key, required this.palette});

  final ScribePalette palette;

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.mic_none_rounded, 'Record the\nconsultation'),
      (Icons.auto_awesome_outlined, 'AI drafts\nthe note'),
      (Icons.fact_check_outlined, 'You review\n& confirm'),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: palette.hint,
              ),
            ),
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(steps[i].$1, size: 20, color: palette.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  steps[i].$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Timer, live waveform and pause / finish / discard controls.
class ScribeRecorderPanel extends StatelessWidget {
  const ScribeRecorderPanel({
    super.key,
    required this.controller,
    required this.palette,
    required this.onDiscard,
  });

  final ScribeSessionController controller;
  final ScribePalette palette;

  /// Called when the doctor taps Discard; the host confirms first.
  final VoidCallback onDiscard;

  static const _warnBefore = Duration(minutes: 5);

  @override
  Widget build(BuildContext context) {
    final paused = controller.phase == ScribeSessionPhase.paused;
    final statusColor = paused ? palette.warning : palette.danger;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusPill(
          color: statusColor,
          label: paused ? 'Paused' : 'Recording',
          pulsing: !paused,
        ),
        const SizedBox(height: 14),
        ValueListenableBuilder<Duration>(
          valueListenable: controller.elapsed,
          builder: (context, elapsed, _) => Text(
            formatScribeDuration(elapsed),
            style: TextStyle(
              fontFamily: AppColors.headingFontFamily,
              fontSize: 44,
              fontWeight: FontWeight.w300,
              letterSpacing: 2,
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(palette.cardRadius),
            border: Border.all(color: palette.cardBorder),
          ),
          child: ScribeWaveform(
            levels: controller.levels,
            color: paused ? palette.hint : palette.danger,
          ),
        ),
        const SizedBox(height: 12),
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
                  ? 'Recording paused — resume when the consultation continues.'
                  : 'Speak naturally. Keep the device between you and the '
                        'patient.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: nearLimit ? palette.warning : palette.textSecondary,
                fontWeight: nearLimit ? FontWeight.w600 : FontWeight.w400,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        // The AI only hears the session — findings measured silently
        // (goniometer, MMT) never reach the note unless said aloud.
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: palette.accentSoft,
            borderRadius: BorderRadius.circular(palette.fieldRadius + 2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.record_voice_over_rounded,
                size: 18,
                color: palette.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Say your findings aloud. ',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: palette.accent,
                        ),
                      ),
                      const TextSpan(
                        text:
                            '"Right knee flexion 95 degrees, McMurray '
                            'positive, quads 4 by 5, pain 6 out of 10."',
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RoundAction(
              icon: Icons.delete_outline_rounded,
              label: 'Discard',
              color: palette.textSecondary,
              palette: palette,
              onTap: onDiscard,
            ),
            const SizedBox(width: 28),
            _RoundAction(
              icon: Icons.stop_rounded,
              label: 'Finish',
              color: Colors.white,
              background: palette.danger,
              size: 72,
              iconSize: 34,
              palette: palette,
              onTap: controller.finish,
              tooltip: 'Stop recording and create the draft',
            ),
            const SizedBox(width: 28),
            _RoundAction(
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              label: paused ? 'Resume' : 'Pause',
              color: palette.textPrimary,
              palette: palette,
              onTap: paused ? controller.resume : controller.pause,
            ),
          ],
        ),
      ],
    );
  }
}

/// Spinner with progress copy while the AI works.
class ScribeProcessingPanel extends StatelessWidget {
  const ScribeProcessingPanel({
    super.key,
    required this.controller,
    required this.palette,
  });

  final ScribeSessionController controller;
  final ScribePalette palette;

  static String _stage(int seconds) {
    if (seconds < 4) return 'Preparing the recording…';
    if (seconds < 20) return 'Transcribing the conversation…';
    if (seconds < 50) return 'Extracting clinical details…';
    return 'Still working — long consultations take a little longer…';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: palette.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: palette.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Creating your draft note',
          style: TextStyle(
            fontFamily: AppColors.headingFontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<int>(
          valueListenable: controller.processingSeconds,
          builder: (context, seconds, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _stage(seconds),
              key: ValueKey(_stage(seconds)),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: palette.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'This usually takes under a minute. Keep this screen open.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Shown when processing failed: explains why and offers recovery.
class ScribeFailurePanel extends StatelessWidget {
  const ScribeFailurePanel({
    super.key,
    required this.controller,
    required this.palette,
    required this.onDiscard,
  });

  final ScribeSessionController controller;
  final ScribePalette palette;

  /// Called when the doctor taps Discard recording; the host confirms first.
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: palette.dangerSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_off_rounded,
              size: 30,
              color: palette.danger,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "Couldn't create the draft",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppColors.headingFontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          controller.error ?? 'Something went wrong.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 22),
        if (controller.canRetry) ...[
          ScribePrimaryButton(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            color: palette.primary,
            onPressed: controller.retry,
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: controller.startManualNote,
          icon: const Icon(Icons.edit_note_rounded, size: 20),
          label: const Text('Write the note manually'),
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.textPrimary,
            minimumSize: const Size.fromHeight(48),
            side: BorderSide(color: palette.border),
            textStyle: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: onDiscard,
          style: TextButton.styleFrom(foregroundColor: palette.danger),
          child: const Text('Discard recording'),
        ),
      ],
    );
  }
}

/// Offer to reopen an unreviewed draft saved earlier for this visit.
class ScribePendingDraftNotice extends StatelessWidget {
  const ScribePendingDraftNotice({
    super.key,
    required this.createdAt,
    required this.palette,
    required this.onReview,
  });

  final DateTime createdAt;
  final ScribePalette palette;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(createdAt).format(context);
    final today = DateUtils.isSameDay(createdAt, DateTime.now());
    return ScribeNotice(
      icon: Icons.pending_actions_rounded,
      color: palette.warning,
      background: palette.warningSoft,
      title: 'Unreviewed draft',
      message:
          'A draft note from ${today ? 'today' : 'an earlier session'} '
          'at $time is waiting for your review.',
      action: TextButton.icon(
        onPressed: onReview,
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
        iconAlignment: IconAlignment.end,
        label: const Text('Review draft'),
        style: TextButton.styleFrom(
          foregroundColor: palette.warning,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class ScribePrimaryButton extends StatelessWidget {
  const ScribePrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
        minimumSize: const Size.fromHeight(50),
        textStyle: const TextStyle(
          fontFamily: AppColors.bodyFontFamily,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _StatusPill extends StatefulWidget {
  const _StatusPill({
    required this.color,
    required this.label,
    required this.pulsing,
  });

  final Color color;
  final String label;
  final bool pulsing;

  @override
  State<_StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<_StatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusPill old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.pulsing && _pulse.isAnimating) {
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.palette,
    required this.onTap,
    this.background,
    this.size = 56,
    this.iconSize = 24,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color? background;
  final ScribePalette palette;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: background ?? palette.card,
      shape: CircleBorder(
        side: background == null
            ? BorderSide(color: palette.border)
            : BorderSide.none,
      ),
      elevation: background == null ? 0 : 2,
      shadowColor: (background ?? Colors.black).withValues(alpha: 0.4),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: color),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 72,
          child: Center(
            child: tooltip == null
                ? button
                : Tooltip(message: tooltip!, child: button),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}
