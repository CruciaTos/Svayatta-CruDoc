import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/chatbot/services/voice_transcription_service.dart';

/// Production-grade Voice Input modal dialog for the CruDoc Mobile AI Chatbot.
///
/// Features:
/// - Real microphone audio capture via [VoiceTranscriptionService].
/// - Dynamic audio amplitude visualizer driven by live microphone levels.
/// - Live recording timer.
/// - Fast speech-to-text processing using Gemini 2.0 Flash multimodal audio.
/// - Review & edit transcribed query before sending.
/// - WhatsApp & ChatGPT-style UX states (Listening / Transcribing / Review / Error).
class VoiceInputModal extends StatefulWidget {
  final ValueChanged<String> onSpeechRecognized;

  const VoiceInputModal({
    super.key,
    required this.onSpeechRecognized,
  });

  /// Helper to present the voice input modal sheet on mobile.
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onSpeechRecognized,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VoiceInputModal(
        onSpeechRecognized: onSpeechRecognized,
      ),
    );
  }

  @override
  State<VoiceInputModal> createState() => _VoiceInputModalState();
}

class _VoiceInputModalState extends State<VoiceInputModal>
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

  static const List<String> _quickSuggestions = [
    'How do I add a new patient?',
    'How to create an invoice?',
    'How to check low stock medicines?',
    'How do I schedule a visit today?',
    'How to hide revenue on dashboard?',
  ];

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

      // Timer to track duration
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _secondsRecorded++;
        });
        // Auto-stop after 30 seconds of speech
        if (_secondsRecorded >= 30) {
          _stopAndTranscribe();
        }
      });

      // Amplitude polling timer for real waveform animation
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
        if (!mounted || !_isListening) return;
        final amp = await _transcriptionService.getAmplitude();
        // Convert current dBFS (-160 to 0) to normalized factor (0.1 to 1.0)
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
    _pulseController.reset();

    setState(() {
      _isListening = false;
      _isTranscribing = true;
      _errorMessage = null;
    });

    try {
      final text = await _transcriptionService.stopAndTranscribe();
      if (!mounted) return;
      setState(() {
        _isTranscribing = false;
        _textController.text = text;
      });
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
        _errorMessage = 'Voice transcription error: $e';
      });
    }
  }

  Future<void> _cancelRecording() async {
    _stopTimers();
    _pulseController.stop();
    await _transcriptionService.cancelRecording();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _sendQuery() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      widget.onSpeechRecognized(text);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.mic_rounded,
                      color: _isListening ? const Color(0xFF1E78FF) : AppColors.slateBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isListening
                        ? 'Listening to Doctor...'
                        : (_isTranscribing
                            ? 'Processing Speech...'
                            : (_textController.text.isNotEmpty
                                ? 'Query Ready'
                                : 'Voice Dictation')),
                    style: const TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (_isListening)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _formattedTimer,
                        style: TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Core Interactive Center: Mic button / Transcribing spinner / Waveform
          if (_isListening) ...[
            GestureDetector(
              onTap: _stopAndTranscribe,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) {
                      return Container(
                        width: 86 + (_pulseController.value * 28),
                        height: 86 + (_pulseController.value * 28),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1E78FF)
                              .withValues(alpha: 0.18 * (1 - _pulseController.value)),
                        ),
                      );
                    },
                  ),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E78FF), Color(0xFF00C6FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1E78FF).withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.stop_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Speak your question naturally • Tap stop when finished',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),

            // Live Audio Waveform Bars
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_amplitudeBars.length, (index) {
                final barHeight = (_amplitudeBars[index] * 38).clamp(8.0, 38.0);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  width: 4.5,
                  height: barHeight,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E78FF),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ] else if (_isTranscribing) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E78FF)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Transcribing voice with Gemini AI...',
                    style: TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Converting your clinical voice query to text',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.mic_off_rounded, color: Colors.red.shade700, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 13,
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _startListening,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Try Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E78FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Transcribed Text review box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _textController,
                maxLines: 3,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Edit or type your query...',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _startListening,
                  icon: const Icon(Icons.mic_rounded, size: 16, color: Color(0xFF1E78FF)),
                  label: const Text(
                    'Re-record Voice',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E78FF),
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // Preset Quick Suggestions
          if (!_isListening && !_isTranscribing) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Or choose a common question:',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _quickSuggestions.map((suggestion) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.chat_bubble_outline_rounded,
                          size: 13, color: AppColors.chartBarLight),
                      label: Text(
                        suggestion,
                        style: const TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      backgroundColor: const Color(0xFFEFF6FF),
                      side: BorderSide(
                        color: AppColors.chartBarLight.withValues(alpha: 0.25),
                      ),
                      onPressed: () {
                        setState(() {
                          _textController.text = suggestion;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Footer Action Buttons
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _cancelRecording,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E78FF), Color(0xFF00C6FF)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E78FF).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _isListening
                        ? _stopAndTranscribe
                        : (_isTranscribing || _textController.text.trim().isEmpty
                            ? null
                            : _sendQuery),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: Icon(
                      _isListening ? Icons.stop_rounded : Icons.send_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: Text(
                      _isListening ? 'Done Speaking' : 'Send to Assistant',
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
