import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/tutorial/presentation/tutorial_controller.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The tour's card: title, one line of body, progress, and Skip / Back /
/// Next. The welcome card carries the app mark and "Start tour" instead.
class TutorialCard extends StatelessWidget {
  const TutorialCard({
    super.key,
    required this.state,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final TutorialState state;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  /// What a screen reader announces as the card changes.
  static String announcement(TutorialState s) {
    final welcome = s.step?.isWelcome ?? false;
    final lead = welcome ? '' : 'Step ${s.position} of ${s.total}. ';
    return '$lead${s.title}. ${s.body}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final step = state.step;
    if (step == null) return const SizedBox.shrink();
    final welcome = step.isWelcome;

    return Semantics(
      container: true,
      liveRegion: true,
      label: announcement(state),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.surface,
          shape: cruShape(
            CruRadius.card,
            side: BorderSide(color: c.cardBorder),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CruSpace.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (welcome) ...[
                const _AppMark(),
                const SizedBox(height: CruSpace.s16),
              ],
              if (step.ai) ...[
                const _AiBadge(),
                const SizedBox(height: CruSpace.s12),
              ],
              ExcludeSemantics(
                child: Text(state.title, style: CruType.title2.tint(c.label)),
              ),
              const SizedBox(height: CruSpace.s8),
              ExcludeSemantics(
                child: Text(state.body, style: CruType.body.tint(c.label2)),
              ),
              if (!welcome) ...[
                const SizedBox(height: CruSpace.s16),
                ExcludeSemantics(
                  child: _Progress(
                    position: state.position,
                    total: state.total,
                  ),
                ),
              ],
              const SizedBox(height: CruSpace.s20),
              // Tab order follows the row: Skip, Back, Next.
              Row(
                children: [
                  _SkipButton(onPressed: onSkip),
                  const Spacer(),
                  if (!state.isFirst) ...[
                    CruButton(
                      label: 'Back',
                      kind: CruButtonKind.inset,
                      semanticLabel: 'Previous step',
                      onPressed: onBack,
                    ),
                    const SizedBox(width: CruSpace.s8),
                  ],
                  CruButton(
                    label: welcome
                        ? 'Start tour'
                        : state.isLast
                        ? 'Done'
                        : 'Next',
                    semanticLabel: welcome
                        ? 'Start tour'
                        : state.isLast
                        ? 'Finish tour'
                        : 'Next step',
                    onPressed: onNext,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The CruDoc mark, as in the sidebar.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return ExcludeSemantics(
      child: Container(
        width: CruSize.appMark,
        height: CruSize.appMark,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: c.accent,
          shape: cruShape(CruRadius.appMark),
        ),
        child: CruIcon(
          CruIcons.plus,
          size: 16,
          strokeWidth: 3.4,
          color: c.onAccent,
        ),
      ),
    );
  }
}

/// Violet is for AI only: this badge sits on the scribe step alone.
class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s8,
        vertical: CruSpace.s4,
      ),
      decoration: ShapeDecoration(
        color: c.aiTint,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CruIcon(CruIcons.sparkle, size: 13, color: c.ai),
          const SizedBox(width: CruSpace.s4),
          Text('AI', style: CruType.micro.w600.tint(c.ai)),
        ],
      ),
    );
  }
}

/// Dots plus "2 of 7".
class _Progress extends StatelessWidget {
  const _Progress({required this.position, required this.total});

  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      children: [
        for (var i = 1; i <= total; i++) ...[
          if (i > 1) const SizedBox(width: CruSpace.s4),
          Container(
            width: CruSize.smallDot,
            height: CruSize.smallDot,
            decoration: ShapeDecoration(
              color: i == position ? c.accent : c.track,
              shape: const CircleBorder(),
            ),
          ),
        ],
        const SizedBox(width: CruSpace.s8),
        Flexible(
          child: Text(
            '$position of $total',
            style: CruType.caption.tabular.tint(c.label2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Plain text on a capsule that fills on hover.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onPressed,
      semanticLabel: 'Skip tour',
      scaleOnPress: false,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: CruSize.control,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : Colors.transparent,
          shape: const StadiumBorder(),
        ),
        child: Text('Skip', style: CruType.text.w500.tint(c.label2)),
      ),
    );
  }
}
