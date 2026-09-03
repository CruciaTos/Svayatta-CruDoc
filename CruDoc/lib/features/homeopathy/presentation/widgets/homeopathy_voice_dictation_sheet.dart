import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/chatbot/services/voice_transcription_service.dart';

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
  static const Color _primaryGreen = Color(0xFF2E7D32);
  static const Color _lightGreen = Color(0xFF81C784);

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
      _amplitudeTimer =
          Timer.periodic(const Duration(milliseconds: 100), (_) async {
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
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  color: _primaryGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice Dictation',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _primaryGreen,
                      ),
                    ),
                    Text(
                      widget.fieldName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _cancelRecording,
                tooltip: 'Close',
              ),
            ],
          ),

          const SizedBox(height: 20),

          // State-specific UI
          if (_isListening) ...[
            // Listening mode
            _buildListeningUI(theme),
          ] else if (_isTranscribing) ...[
            // Transcribing mode
            _buildTranscribingUI(theme),
          ] else if (_errorMessage != null) ...[
            // Error mode
            _buildErrorUI(theme),
          ] else ...[
            // Review & edit mode
            _buildReviewUI(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildListeningUI(ThemeData theme) {
    return Column(
      children: [
        // Waveform bars
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(7, (i) {
              final barHeight = 14.0 + (_amplitudeBars[i] * 42.0);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 6,
                height: barHeight,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_primaryGreen, _lightGreen],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),

        // Live timer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Listening • $_formattedTimer',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Speak clinical symptoms, modalities, or mental rubrics clearly...',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.65),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),

        // Done button
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _cancelRecording,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: _stopAndTranscribe,
              icon: const Icon(Icons.check_rounded, size: 20),
              label: const Text('Done Speaking'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTranscribingUI(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3.5,
              valueColor: AlwaysStoppedAnimation<Color>(_primaryGreen),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Transcribing with Gemini AI...',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Converting speech to precise clinical terminology',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.65),
            ),
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
                  _errorMessage ?? 'An error occurred during transcription.',
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
              onPressed: _startListening,
              icon: const Icon(Icons.mic_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryGreen,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReviewUI(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Transcribed Clinical Note',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: _primaryGreen,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _textController,
          maxLines: 4,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Transcribed symptom text...',
            filled: true,
            fillColor: theme.cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.grey.withValues(alpha: 0.25),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.grey.withValues(alpha: 0.25),
              ),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(
                color: _primaryGreen,
                width: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            IconButton(
              onPressed: _startListening,
              icon: const Icon(Icons.mic_rounded),
              tooltip: 'Re-record',
              style: IconButton.styleFrom(
                backgroundColor: _primaryGreen.withValues(alpha: 0.1),
                foregroundColor: _primaryGreen,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Discard'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _confirmInsert,
              icon: const Icon(Icons.done_rounded, size: 18),
              label: const Text('Insert into Field'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
