import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/services/voice_transcription_service.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/services/homeopathy_voice_scribe_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Full case consultation voice scribe modal.
///
/// Records consultation narrative, transcribes it with Gemini,
/// extracts homeopathic clinical totality, and returns a populated
/// [HomeopathyCaseSheet].
class HomeopathyVoiceScribeModal extends StatefulWidget {
  final HomeopathyCaseSheet existingSheet;

  const HomeopathyVoiceScribeModal({super.key, required this.existingSheet});

  /// Displays the modal and returns the populated [HomeopathyCaseSheet] if successful.
  static Future<HomeopathyCaseSheet?> show(
    BuildContext context, {
    required HomeopathyCaseSheet existingSheet,
  }) {
    return showModalBottomSheet<HomeopathyCaseSheet>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          HomeopathyVoiceScribeModal(existingSheet: existingSheet),
    );
  }

  @override
  State<HomeopathyVoiceScribeModal> createState() =>
      _HomeopathyVoiceScribeModalState();
}

class _HomeopathyVoiceScribeModalState extends State<HomeopathyVoiceScribeModal>
    with TickerProviderStateMixin {
  final _transcriptionService = VoiceTranscriptionService.instance;
  final _scribeService = HomeopathyVoiceScribeService.instance;

  late AnimationController _pulseController;
  late AnimationController _waveController;
  Timer? _timer;
  Timer? _amplitudeTimer;

  bool _isRecording = false;
  bool _isProcessing = false;
  String _processingStage = '';
  String? _errorMessage;
  int _secondsRecorded = 0;
  List<double> _amplitudeBars = List.filled(9, 0.2);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _startRecording();
  }

  @override
  void dispose() {
    _stopTimers();
    _pulseController.dispose();
    _waveController.dispose();
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

  Future<void> _startRecording() async {
    _stopTimers();
    setState(() {
      _isRecording = true;
      _isProcessing = false;
      _errorMessage = null;
      _secondsRecorded = 0;
    });

    try {
      await _transcriptionService.startRecording();
      _pulseController.repeat(reverse: true);

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _secondsRecorded++;
        });
        // Auto-stop at 5 minutes
        if (_secondsRecorded >= 300) {
          _stopAndProcess();
        }
      });

      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
        if (!mounted || !_isRecording) return;
        final amp = await _transcriptionService.getAmplitude();
        final normalized = ((amp.current + 60) / 60).clamp(0.12, 1.0);

        setState(() {
          _amplitudeBars = List.generate(9, (i) {
            final variance = (i - 4).abs() * 0.08;
            return (normalized - variance).clamp(0.15, 1.0);
          });
        });
      });
    } on VoiceTranscriptionException catch (e) {
      _stopTimers();
      _pulseController.stop();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      _stopTimers();
      _pulseController.stop();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _errorMessage = 'Could not access microphone: $e';
      });
    }
  }

  Future<void> _stopAndProcess() async {
    if (!_isRecording) return;
    _stopTimers();
    _pulseController.stop();

    setState(() {
      _isRecording = false;
      _isProcessing = true;
      _processingStage = 'Transcribing consultation recording...';
      _errorMessage = null;
    });

    try {
      final transcript = await _transcriptionService.stopAndTranscribe();
      if (!mounted) return;

      if (transcript.isEmpty) {
        setState(() {
          _isProcessing = false;
          _errorMessage =
              'No speech detected. Please speak louder and closer to the mic.';
        });
        return;
      }

      setState(() {
        _processingStage =
            'Extracting homeopathic totality, rubrics & symptoms...';
      });

      final updatedSheet = await _scribeService.extractFromTranscript(
        transcript,
        existingSheet: widget.existingSheet,
      );

      if (!mounted) return;

      Navigator.of(context).pop(updatedSheet);
    } on VoiceTranscriptionException catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Processing failed: $e';
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
        CruSpace.s24,
        CruSpace.s16,
        CruSpace.s24,
        CruSpace.s24 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: CruSpace.s32 + CruSpace.s16,
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
                  color: c.aiTint,
                  borderRadius: BorderRadius.circular(CruRadius.iconTile),
                ),
                child: Center(child: CruIcon(CruIcons.sparkle, color: c.ai)),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI case scribe',
                      style: CruType.headline.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      'Speak the whole consultation or case story in one go.',
                      style: CruType.caption.tint(c.label2),
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
          const SizedBox(height: CruSpace.s24),
          if (_isRecording)
            _buildRecordingUI(c)
          else if (_isProcessing)
            _buildProcessingUI(c)
          else if (_errorMessage != null)
            _buildErrorUI(c),
        ],
      ),
    );
  }

  Widget _buildRecordingUI(CruColors c) {
    return Column(
      children: [
        // Live level bars in Ink Blue, the "now" colour.
        SizedBox(
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(9, (i) {
              final barHeight = CruSpace.s16 + (_amplitudeBars[i] * 50.0);
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
        const SizedBox(height: CruSpace.s16),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s16,
            vertical: CruSpace.s8,
          ),
          decoration: BoxDecoration(
            color: c.accentWash,
            borderRadius: BorderRadius.circular(CruRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: CruSize.statusDot,
                height: CruSize.statusDot,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: CruSpace.s8),
              Text(
                'Recording · $_formattedTimer',
                style: CruType.callout.w600.tabular.tint(c.accentText),
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.s16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(CruSpace.s12),
          decoration: BoxDecoration(
            color: c.inset,
            borderRadius: BorderRadius.circular(CruRadius.control),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mention any of these naturally:',
                style: CruType.caption.w600.tint(c.label),
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                [
                  '• Chief complaints, sensations, locations and durations',
                  '• Modalities (worse at 3 PM, heat, cold drinks)',
                  '• Thermals (chilly or hot), thirst and food cravings',
                  '• Mind, fears, anxiety, family or work stress',
                  '• Remedy considered, potency and dose',
                ].join('\n'),
                style: CruType.caption.tint(c.label2),
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.s24),
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
              label: 'Finish and fill',
              icon: CruIcons.sparkle,
              onPressed: _stopAndProcess,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProcessingUI(CruColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s32),
      child: Column(
        children: [
          SizedBox.square(
            dimension: CruSpace.s32 + CruSpace.s16,
            child: CircularProgressIndicator(strokeWidth: 3, color: c.ai),
          ),
          const SizedBox(height: CruSpace.s24),
          Text(
            'Reading the consultation',
            style: CruType.headline.tint(c.label),
          ),
          const SizedBox(height: CruSpace.s8),
          Text(
            _processingStage,
            style: CruType.caption.w500.tint(c.ai),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CruSpace.s6),
          Text(
            'Totality, modalities, generals and mental rubrics.',
            style: CruType.caption.tint(c.label2),
            textAlign: TextAlign.center,
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
                  _errorMessage ?? 'Something went wrong while processing.',
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
              onPressed: _startRecording,
            ),
          ],
        ),
      ],
    );
  }
}
