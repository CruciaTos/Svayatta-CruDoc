import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

/// PS2 startup style two-phase blur reveal (AI text-reveal).
///
/// Features:
/// 1. Instant Disappearance on Input Detection (`isPending: true`):
///    As soon as the speech engine detects that a field is being spoken (e.g. "birth date..."),
///    the old content / placeholder immediately blurs out horizontally into smoke
///    and stays dissolved/foggy while the model finishes processing the full clean value.
/// 2. Emergence on Finalization (`revealKey` change):
///    The clean, accurate input emerges from that very fog into razor-sharp clarity.
/// 3. Direct Arrival:
///    If a final value arrives without a preceding pending signal, it runs the full
///    dissolve -> emerge sequence smoothly.
/// 4. Zero Bleed:
///    Strictly clipped inside the field boundary with ClipRect; zero outer glow or border expansion.
class AiBlurReveal extends StatefulWidget {
  const AiBlurReveal({
    super.key,
    required this.child,
    this.outgoingChild,
    this.revealKey,
    this.isPending = false,
    this.dissolveDuration = const Duration(milliseconds: 280),
    this.emergeDuration = const Duration(milliseconds: 380),
    this.maxBlurX = 20.0,
    this.maxBlurY = 6.0,
    this.stagger = Duration.zero,
  });

  final Widget child;

  /// Optional outgoing representation (old text / placeholder) to blur out first.
  /// If null, falls back to the previous widget child.
  final Widget? outgoingChild;

  /// Triggered whenever this object changes (e.g. an integer counter) to indicate
  /// that a finalized value has arrived and should be revealed.
  final Object? revealKey;

  /// Whether the field is currently being detected or spoken by the user.
  /// When true, the field immediately animates the old content/placeholder
  /// dissolving into smoke and stays dissolved/foggy while waiting for the final input.
  final bool isPending;

  final Duration dissolveDuration;
  final Duration emergeDuration;
  final double maxBlurX;
  final double maxBlurY;
  final Duration stagger;

  @override
  State<AiBlurReveal> createState() => _AiBlurRevealState();
}

class _AiBlurRevealState extends State<AiBlurReveal>
    with TickerProviderStateMixin {
  late final AnimationController _dissolveController;
  late final AnimationController _emergeController;
  Timer? _staggerTimer;
  Timer? _sequenceTimer;
  Object? _lastRevealKey;
  Widget? _activeOutgoing;
  bool _wasPending = false;

  @override
  void initState() {
    super.initState();
    _lastRevealKey = widget.revealKey;
    _wasPending = widget.isPending;

    // 0.0 = visible, 1.0 = dissolved into smoke
    _dissolveController = AnimationController(
      vsync: this,
      duration: widget.dissolveDuration,
      value: 1.0,
    );

    // 0.0 = hidden in fog, 1.0 = crisp clarity
    _emergeController =
        AnimationController(
          vsync: this,
          duration: widget.emergeDuration,
          value: widget.isPending ? 0.0 : 1.0,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() {
              _activeOutgoing = null;
            });
          }
        });

    if (widget.isPending) {
      _dissolveController.value = 1.0;
      _emergeController.value = 0.0;
    }
  }

  @override
  void didUpdateWidget(AiBlurReveal oldWidget) {
    super.didUpdateWidget(oldWidget);

    final pendingTurnedOn = widget.isPending && !oldWidget.isPending;
    final pendingTurnedOff = !widget.isPending && oldWidget.isPending;
    final revealKeyChanged =
        widget.revealKey != null && widget.revealKey != _lastRevealKey;

    if (pendingTurnedOn) {
      // 1. Instant Disappearance: Speech detected for this field!
      // Immediately dissolve old content into smoke and STAY dissolved!
      _wasPending = true;
      _lastRevealKey = widget.revealKey;
      _activeOutgoing = widget.outgoingChild;
      _staggerTimer?.cancel();
      _sequenceTimer?.cancel();
      _emergeController.value = 0.0; // Hide incoming text
      _dissolveController.forward(from: 0.0); // Dissolve old into smoke
    } else if (revealKeyChanged) {
      // 2. Finalized Value Arrived!
      _lastRevealKey = widget.revealKey;
      if (_wasPending || oldWidget.isPending) {
        // Field was already dissolved into smoke and waiting in fog!
        _wasPending = false;
        _activeOutgoing = null;
        _staggerTimer?.cancel();
        _sequenceTimer?.cancel();
        _dissolveController.value = 1.0; // Ensure outgoing is fully dissolved
        _triggerEmerge();
      } else {
        // Direct arrival without prior pending: dissolve old -> emerge new
        _activeOutgoing = widget.outgoingChild;
        _triggerFullSequence();
      }
    } else if (pendingTurnedOff && !revealKeyChanged) {
      // 3. User changed mind / cancelled speech: restore original content
      _wasPending = false;
      _activeOutgoing = null;
      _staggerTimer?.cancel();
      _sequenceTimer?.cancel();
      _dissolveController.reverse();
      _emergeController.forward(from: 1.0);
    }
  }

  void _triggerEmerge() {
    _emergeController.value = 0.0;
    if (widget.stagger > Duration.zero) {
      _staggerTimer?.cancel();
      _staggerTimer = Timer(widget.stagger, () {
        if (mounted) {
          _emergeController.forward(from: 0.0);
        }
      });
    } else {
      _emergeController.forward(from: 0.0);
    }
  }

  void _triggerFullSequence() {
    _staggerTimer?.cancel();
    _sequenceTimer?.cancel();
    _dissolveController.value = 0.0;
    _emergeController.value = 0.0;
    _dissolveController.forward(from: 0.0);
    // Smooth overlap: start emerging when dissolve reaches ~60%
    _sequenceTimer = Timer(const Duration(milliseconds: 170), () {
      if (mounted) {
        _triggerEmerge();
      }
    });
  }

  @override
  void dispose() {
    _staggerTimer?.cancel();
    _sequenceTimer?.cancel();
    _dissolveController.dispose();
    _emergeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_dissolveController, _emergeController]),
      builder: (context, child) {
        final isDissolving =
            _dissolveController.isAnimating || _dissolveController.value < 1.0;
        final isEmerging =
            _emergeController.isAnimating || _emergeController.value < 1.0;
        final isPending = widget.isPending;

        // If completely idle, clear snapshot and render raw child
        if (!isDissolving && !isEmerging && !isPending) {
          _activeOutgoing = null;
          return child!;
        }

        // Outgoing dissolution calculation (Phase 1)
        final dVal = _dissolveController.value;
        final curveOut = Curves.easeInOutCubic.transform(dVal);
        final sigmaOutX = curveOut * widget.maxBlurX;
        final sigmaOutY = curveOut * widget.maxBlurY;
        final opacityOut = (1.0 - curveOut).clamp(0.0, 1.0);
        final scaleOut = 1.0 + (0.025 * curveOut);

        // Incoming emergence calculation (Phase 2)
        final eVal = _emergeController.value;
        final curveIn = Curves.easeOutCubic.transform(eVal);
        final sigmaInX = (1.0 - curveIn) * widget.maxBlurX;
        final sigmaInY = (1.0 - curveIn) * widget.maxBlurY;
        final opacityIn = curveIn.clamp(0.0, 1.0);
        final scaleIn = 0.98 + (0.02 * curveIn);

        final outgoing = _activeOutgoing;

        return ClipRect(
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Primary child establishes layout geometry and emerges from fog
              Opacity(
                opacity: opacityIn,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: sigmaInX > 0.01 ? sigmaInX : 0.001,
                    sigmaY: sigmaInY > 0.01 ? sigmaInY : 0.001,
                    tileMode: TileMode.clamp,
                  ),
                  child: Transform.scale(
                    scale: scaleIn,
                    alignment: Alignment.centerLeft,
                    child: child,
                  ),
                ),
              ),
              // Outgoing layer: old info or placeholder dissolving into fog
              if (outgoing != null && opacityOut > 0.005)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: opacityOut,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: sigmaOutX > 0.01 ? sigmaOutX : 0.001,
                          sigmaY: sigmaOutY > 0.01 ? sigmaOutY : 0.001,
                          tileMode: TileMode.clamp,
                        ),
                        child: Transform.scale(
                          scale: scaleOut,
                          alignment: Alignment.centerLeft,
                          child: outgoing,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}
