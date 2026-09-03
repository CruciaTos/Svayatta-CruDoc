import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/chatbot/services/voice_transcription_service.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/services/homeopathy_voice_scribe_service.dart';

/// Full case consultation voice scribe modal.
///
/// Records consultation narrative, transcribes via Gemini 2.0 Flash,
/// extracts homeopathic clinical totality, and returns a populated
/// [HomeopathyCaseSheet].
class HomeopathyVoiceScribeModal extends StatefulWidget {
  final HomeopathyCaseSheet existingSheet;

  const HomeopathyVoiceScribeModal({
    super.key,
    required this.existingSheet,
  });

  /// Displays the modal and returns the populated [HomeopathyCaseSheet] if successful.
  static Future<HomeopathyCaseSheet?> show(
    BuildContext context, {
    required HomeopathyCaseSheet existingSheet,
  }) {
    return showModalBottomSheet<HomeopathyCaseSheet>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => HomeopathyVoiceScribeModal(
        existingSheet: existingSheet,
      ),
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

      _amplitudeTimer =
          Timer.periodic(const Duration(milliseconds: 100), (_) async {
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
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 28 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Voice Case Scribe',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                    Text(
                      'Speak entire consultation or case story in one go',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _cancelRecording,
              ),
            ],
          ),

          const SizedBox(height: 24),

          if (_isRecording) ...[
            _buildRecordingUI(theme),
          ] else if (_isProcessing) ...[
            _buildProcessingUI(theme),
          ] else if (_errorMessage != null) ...[
            _buildErrorUI(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordingUI(ThemeData theme) {
    return Column(
      children: [
        // Waveform
        Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(9, (i) {
              final barHeight = 16.0 + (_amplitudeBars[i] * 50.0);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 7,
                height: barHeight,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF81C784)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),

        // Live recording badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Recording Consultation • $_formattedTimer',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Spoken guide tips
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tip: Mention any of the following naturally:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '• Chief complaints, sensations, locations & durations\n'
                '• Modalities (worse at 3 PM, heat, cold drinks)\n'
                '• Thermals (chilly / hot), thirst manner & food cravings\n'
                '• Mind, fears, anxiety, family/work stress\n'
                '• Remedy considered, potency & dose',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green.shade900.withValues(alpha: 0.8),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _cancelRecording,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: _stopAndProcess,
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              label: const Text('Finish & Auto-Fill'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProcessingUI(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          const SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Analyzing with Gemini 2.0 Flash',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _processingStage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF2E7D32),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Synthesizing totality, modalities, generals, and mental rubrics...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorUI(ThemeData theme) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.red, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _errorMessage ?? 'An error occurred during processing.',
                  style: const TextStyle(fontSize: 13, color: Colors.red),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: _startRecording,
              icon: const Icon(Icons.mic_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
