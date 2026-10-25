import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/services/voice_transcription_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Modal bottom sheet for hands-free voice dictation into a specific clinical field.
class HomeopathyVoiceDictationSheet extends StatefulWidget {
  final String fieldName;
  final String initialText;

  const HomeopathyVoiceDictationSheet({
    super.key,
    required this.fieldName,
    this.initialText = '',
  });

  /// Displays the voice dictation modal sheet and returns the transcribed text.
  static Future<String?> show(
    BuildContext context, {
    required String fieldName,
    String initialText = '',
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => HomeopathyVoiceDictationSheet(
        fieldName: fieldName,
        initialText: initialText,
      ),
    );
  }

  @override
  State<HomeopathyVoiceDictationSheet> createState() =>
      _HomeopathyVoiceDictationSheetState();
}

class _HomeopathyVoiceDictationSheetState
    extends State<HomeopathyVoiceDictationSheet>
    with TickerProviderStateMixin {
  final _transcriptionService = VoiceTranscriptionService.instance;
  final TextEditingController _textController = TextEditingController();

  late AnimationController _pulseController;
  late AnimationController _waveController;
  Timer? _timer;
  Timer? _amplitudeTimer;

  bool _isListening = false;
  bool _isTranscribing = false;
  String? _errorMessage;
  int _secondsRecorded = 0;
  List<double> _amplitudeBars = List.filled(7, 0.2);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _startListening();
  }

  @override
  void dispose() {
    _stopTimers();
    _pulseController.dispose();
    _waveController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _stopTimers() {
    _timer?.cancel();
    _timer = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
  }

  String get _formattedTimer {
    final m = (_secondsRecorded ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsRecorded % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _startListening() async {
    _stopTimers();
    setState(() {
      _isListening = true;
      _isTranscribing = false;
      _errorMessage = null;
      _secondsRecorded = 0;
    });

    try {
      await _transcriptionService.startRecording();
      _pulseController.repeat(reverse: true);

      // Duration timer
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _secondsRecorded++;
        });
        if (_secondsRecorded >= 45) {
          _stopAndTranscribe();
        }
      });

      // Amplitude polling
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
        if (!mounted || !_isListening) return;
        final amp = await _transcriptionService.getAmplitude();
        final normalized = ((amp.current + 60) / 60).clamp(0.12, 1.0);

        setState(() {
          _amplitudeBars = List.generate(7, (i) {
            final variance = (i - 3).abs() * 0.1;
            return (normalized - variance).clamp(0.15, 1.0);
          });
        });
      });
    } on VoiceTranscriptionException catch (e) {
      _stopTimers();
      _pulseController.stop();
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      _stopTimers();
      _pulseController.stop();
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _errorMessage = 'Could not access microphone: $e';
      });
    }
  }

  Future<void> _stopAndTranscribe() async {
    if (!_isListening) return;
    _stopTimers();
    _pulseController.stop();

    setState(() {
      _isListening = false;
      _isTranscribing = true;
      _errorMessage = null;
    });

    try {
      final transcript = await _transcriptionService.stopAndTranscribe();
      if (!mounted) return;

      if (transcript.isNotEmpty) {
        setState(() {
          _isTranscribing = false;
          _textController.text = transcript;
        });
      } else {
        setState(() {
          _isTranscribing = false;
          _errorMessage = 'No speech detected. Please try speaking again.';
        });
      }
    } on VoiceTranscriptionException catch (e) {
      if (!mounted) return;
      setState(() {
        _isTranscribing = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTranscribing = false;
        _errorMessage = 'Transcription failed: $e';
      });
    }
  }

  Future<void> _cancelRecording() async {
    _stopTimers();
    _pulseController.stop();
    await _transcriptionService.cancelRecording();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _confirmInsert() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CruRadius.card),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s16,
        CruSpace.s20,
        CruSpace.s20 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: CruSpace.s32 + CruSpace.s12,
              height: CruSpace.s4,
              decoration: BoxDecoration(
                color: c.track,
                borderRadius: BorderRadius.circular(CruRadius.full),
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s16),
          Row(
            children: [
              Container(
                width: CruSize.iconTile,
                height: CruSize.iconTile,
                decoration: BoxDecoration(
                  color: c.inset,
                  borderRadius: BorderRadius.circular(CruRadius.iconTile),
                ),
                child: Center(child: CruIcon(CruIcons.mic, color: c.label2)),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dictate', style: CruType.headline.tint(c.label)),
                    Text(
                      widget.fieldName,
                      style: CruType.caption.tint(c.label2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              CruIconButton(
                icon: CruIcons.close,
                onPressed: _cancelRecording,
                semanticLabel: 'Close',
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s20),
          if (_isListening)
            _buildListeningUI(c)
          else if (_isTranscribing)
            _buildTranscribingUI(c)
          else if (_errorMessage != null)
            _buildErrorUI(c)
          else
            _buildReviewUI(c),
        ],
      ),
    );
  }

  Widget _buildListeningUI(CruColors c) {
    return Column(
      children: [
        // Live level bars in Ink Blue, the "now" colour.
        SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(7, (i) {
              final barHeight = CruSpace.s14 + (_amplitudeBars[i] * 42.0);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                margin: const EdgeInsets.symmetric(horizontal: CruSpace.s4),
                width: CruSpace.s6,
                height: barHeight,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(CruRadius.full),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: CruSpace.s12),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s14,
            vertical: CruSpace.s6,
          ),
          decoration: BoxDecoration(
            color: c.accentWash,
            borderRadius: BorderRadius.circular(CruRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: CruSize.smallDot,
                height: CruSize.smallDot,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: CruSpace.s8),
              Text(
                'Listening · $_formattedTimer',
                style: CruType.caption.w600.tabular.tint(c.accentText),
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.s10),
        Text(
          'Speak symptoms, modalities or mental rubrics clearly.',
          style: CruType.caption.tint(c.label2),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: CruSpace.s20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CruButton(
              label: 'Cancel',
              kind: CruButtonKind.secondary,
              onPressed: _cancelRecording,
            ),
            const SizedBox(width: CruSpace.s12),
            CruButton(
              label: 'Done',
              icon: CruIcons.check,
              onPressed: _stopAndTranscribe,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTranscribingUI(CruColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s32),
      child: Column(
        children: [
          SizedBox.square(
            dimension: CruSpace.s32 + CruSpace.s12,
            child: CircularProgressIndicator(strokeWidth: 3, color: c.ai),
          ),
          const SizedBox(height: CruSpace.s20),
          Text('Writing it down…', style: CruType.callout.w600.tint(c.label)),
          const SizedBox(height: CruSpace.s6),
          Text(
            'Turning speech into clinical wording.',
            style: CruType.caption.tint(c.label2),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorUI(CruColors c) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(CruSpace.s14),
          decoration: BoxDecoration(
            color: c.inset,
            borderRadius: BorderRadius.circular(CruRadius.control),
          ),
          child: Row(
            children: [
              CruIcon(CruIcons.warning, color: c.label2),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Text(
                  _errorMessage ?? 'Something went wrong while writing it down.',
                  style: CruType.text.tint(c.label),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.s20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CruButton(
              label: 'Cancel',
              kind: CruButtonKind.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: CruSpace.s12),
            CruButton(
              label: 'Try again',
              icon: CruIcons.mic,
              onPressed: _startListening,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReviewUI(CruColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'What was heard',
          style: CruType.caption.w600.tint(c.label2),
        ),
        const SizedBox(height: CruSpace.s8),
        TextField(
          controller: _textController,
          maxLines: 4,
          style: CruType.input.tint(c.label),
          decoration: const InputDecoration(hintText: 'Dictated text'),
        ),
        const SizedBox(height: CruSpace.s16),
        Row(
          children: [
            CruCapsuleButton(
              label: 'Record again',
              icon: CruIcons.mic,
              onPressed: _startListening,
            ),
            const Spacer(),
            CruButton(
              label: 'Discard',
              kind: CruButtonKind.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: CruSpace.s8),
            CruButton(label: 'Insert', onPressed: _confirmInsert),
          ],
        ),
      ],
    );
  }
}
