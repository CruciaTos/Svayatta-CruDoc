import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

/// Modal dialog for voice input dictation in the AI Chatbot.
///
/// Provides a rich animated listening UI with pulsing mic rings, audio wave
/// animations, live transcript display, and quick voice dictation presets.
class VoiceInputModal extends StatefulWidget {
  final ValueChanged<String> onSpeechRecognized;

  const VoiceInputModal({
    super.key,
    required this.onSpeechRecognized,
  });

  /// Static helper to show the voice input modal sheet.
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
  late AnimationController _pulseController;
  late AnimationController _waveController;
  Timer? _transcriptionTimer;

  String _transcribedText = '';
  bool _isListening = true;
  int _sampleIndex = 0;

  static const List<String> _sampleDictations = [
    'How do I add a new patient to records?',
    'How to create an invoice for a patient?',
    'How to check low stock medicines in inventory?',
    'How do I schedule a visit for today?',
    'How to hide revenue amount on dashboard?',
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _startListeningSimulation();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _transcriptionTimer?.cancel();
    super.dispose();
  }

  void _startListeningSimulation() {
    setState(() {
      _isListening = true;
      _transcribedText = 'Listening to doctor...';
    });

    // Simulate realistic voice speech recognition transcription
    _transcriptionTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _transcribedText = _sampleDictations[_sampleIndex % _sampleDictations.length];
        _sampleIndex++;
        _isListening = false;
      });
    });
  }

  void _confirmAndSend() {
    if (_transcribedText.isNotEmpty &&
        _transcribedText != 'Listening to doctor...') {
      widget.onSpeechRecognized(_transcribedText);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mic_rounded,
                color: _isListening ? const Color(0xFF1E78FF) : AppColors.textPrimary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                _isListening ? 'Listening to Voice Input...' : 'Voice Query Captured',
                style: const TextStyle(
                  fontFamily: AppColors.headingFontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Pulsing Mic Animation Ring
          GestureDetector(
            onTap: () {
              if (!_isListening) {
                _startListeningSimulation();
              }
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer pulsing ring
                if (_isListening)
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) {
                      return Container(
                        width: 100 + (_pulseController.value * 30),
                        height: 100 + (_pulseController.value * 30),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1E78FF)
                              .withValues(alpha: 0.2 * (1 - _pulseController.value)),
                        ),
                      );
                    },
                  ),
                // Inner gradient button
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _isListening
                          ? [const Color(0xFF1E78FF), const Color(0xFF00C6FF)]
                          : [const Color(0xFF22C55E), const Color(0xFF16A34A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isListening
                                ? const Color(0xFF1E78FF)
                                : const Color(0xFF22C55E))
                            .withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.mic_rounded : Icons.check_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Audio Waveform Animation Bars
          if (_isListening)
            AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final heights = [12.0, 24.0, 36.0, 20.0, 14.0];
                    final factor = index % 2 == 0
                        ? _waveController.value
                        : (1 - _waveController.value);
                    return Container(
                      width: 4,
                      height: (heights[index] * (0.5 + factor * 0.8)).clamp(8.0, 40.0),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E78FF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                );
              },
            )
          else
            const Text(
              'Tap mic again to re-record',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),

          const SizedBox(height: 20),

          // Transcribed Text Container
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.record_voice_over_rounded, size: 16, color: AppColors.slateBlue),
                    SizedBox(width: 6),
                    Text(
                      'TRANSCRIPT',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: AppColors.slateBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _transcribedText,
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _isListening
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    fontStyle: _isListening ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Preset Voice Suggestions Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _sampleDictations.map((dictation) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.graphic_eq_rounded, size: 14, color: AppColors.chartBarLight),
                    label: Text(
                      dictation,
                      style: const TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    backgroundColor: const Color(0xFFEFF6FF),
                    side: BorderSide(color: AppColors.chartBarLight.withValues(alpha: 0.3)),
                    onPressed: () {
                      setState(() {
                        _transcribedText = dictation;
                        _isListening = false;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // Action Buttons: Send Voice Query & Cancel
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
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
                      fontSize: 15,
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
                    onPressed: _isListening ? null : _confirmAndSend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    label: const Text(
                      'Send Voice Query',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 15,
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
