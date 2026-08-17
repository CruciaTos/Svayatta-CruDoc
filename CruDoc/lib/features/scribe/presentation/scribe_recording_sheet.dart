import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_draft_review_screen.dart';

/// Bottom sheet that handles patient consent capture and audio recording
/// for the AI Voice Scribe feature.
///
/// Flow:
///   1. Consent checkbox + explainer → doctor must check before recording
///   2. Tap "Start Recording" → mic permission prompt → recording starts
///   3. Animated waveform + elapsed timer shown during recording
///   4. Tap "Stop" → audio written to local storage → processing begins
///   5. On processing complete → navigate to [ScribeDraftReviewScreen]
///
/// Nothing is written to the patient record here. That only happens if
/// the doctor taps Confirm on the review screen.
class ScribeRecordingSheet extends ConsumerStatefulWidget {
  final Visit visit;
  final Patient? patient;

  const ScribeRecordingSheet({
    super.key,
    required this.visit,
    required this.patient,
  });

  @override
  ConsumerState<ScribeRecordingSheet> createState() =>
      _ScribeRecordingSheetState();
}

class _ScribeRecordingSheetState extends ConsumerState<ScribeRecordingSheet>
    with TickerProviderStateMixin {
  // ---- State ----
  bool _consentGiven = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  String? _errorMessage;

  // ---- Recording ----
  final _recorder = AudioRecorder();
  String? _audioPath;
  DateTime? _consentAt;
  Timer? _timer;
  int _elapsedSeconds = 0;

  // ---- Animations ----
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _waveController;

  // Waveform bar heights (animated)
  final List<double> _waveHeights = List.filled(20, 0.3);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ---- Helpers ----

  String get _timerLabel {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _patientName =>
      widget.patient?.fullName ?? 'Unknown Patient';

  // ---- Recording logic ----

  Future<void> _startRecording() async {
    if (!_consentGiven) return;

    // Check mic permission
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Microphone permission denied. Please grant it in Settings.';
        });
      }
      return;
    }

    // Create output path
    final dir = await getApplicationDocumentsDirectory();
    final id = const Uuid().v4();
    _audioPath = '${dir.path}/scribe_$id.m4a';
    _consentAt = DateTime.now();

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 16000,
      ),
      path: _audioPath!,
    );

    _elapsedSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _elapsedSeconds++;
        // Animate waveform bars with pseudo-random heights
        for (var i = 0; i < _waveHeights.length; i++) {
          _waveHeights[i] = 0.2 +
              0.8 *
                  (((_elapsedSeconds * 7 + i * 13) % 10) / 10.0);
        }
      });
    });

    _pulseController.repeat(reverse: true);

    setState(() {
      _isRecording = true;
      _errorMessage = null;
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _pulseController.stop();
    _pulseController.reset();

    await _recorder.stop();

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });

    await _processAudio();
  }

  Future<void> _processAudio() async {
    final audioPath = _audioPath;
    if (audioPath == null) {
      setState(() {
        _errorMessage = 'Recording path is missing. Please try again.';
        _isProcessing = false;
      });
      return;
    }

    final processingService = ref.read(scribeProcessingServiceProvider);
    final repo = ref.read(consultationNoteRepositoryProvider);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Validate audio length before calling AI
    final validationError = await processingService.validateAudio(audioPath);
    if (validationError != null && mounted) {
      setState(() {
        _errorMessage = validationError;
        _isProcessing = false;
      });
      return;
    }

    try {
      final noteId = const Uuid().v4();

      // Call Gemini directly with the recorded local audio (instant, local-first)
      final draft = await processingService.processAudio(
        localAudioPath: audioPath,
        audioStoragePath: null,
        noteId: noteId,
        doctorId: user.uid,
        patientId: widget.visit.patientId,
        visitId: widget.visit.id,
        consentAt: _consentAt ?? DateTime.now(),
      );

      // Clean up local temp file after processing
      try {
        await File(audioPath).delete();
      } catch (_) {}

      // Save draft locally
      await repo.saveNote(draft);

      if (!mounted) return;

      // Pop the recording sheet and push the draft review screen
      Navigator.pop(context);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScribeDraftReviewScreen(
            note: draft,
            patient: widget.patient,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Processing failed: ${e.toString().replaceAll('Exception:', '').trim()}';
          _isProcessing = false;
        });
      }
    }
  }

  void _cancel() {
    if (_isRecording) {
      _timer?.cancel();
      _pulseController.stop();
      _recorder.stop();
    }
    Navigator.pop(context);
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1B2430),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: _isProcessing ? _buildProcessingView() : _buildMainView(),
        ),
      ),
    );
  }

  Widget _buildMainView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4A90D9).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Color(0xFF4A90D9),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI Voice Scribe',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppColors.headingFontFamily,
                    ),
                  ),
                  Text(
                    _patientName,
                    style: const TextStyle(
                      color: Color(0xFF8A9BB0),
                      fontSize: 13,
                      fontFamily: AppColors.bodyFontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        if (!_isRecording) ...[
          // Consent section
          _buildConsentCard(),
          const SizedBox(height: 20),
        ],

        // Error message
        if (_errorMessage != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: 16),
        ],

        // Recording indicator / waveform
        if (_isRecording) ...[
          _buildRecordingView(),
          const SizedBox(height: 24),
        ],

        // Action buttons
        _buildActions(),
      ],
    );
  }

  Widget _buildConsentCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A313C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _consentGiven
              ? const Color(0xFF4A90D9).withValues(alpha: 0.4)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Patient Consent',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: AppColors.headingFontFamily,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Recording a clinical consultation requires the patient\'s '
            'knowledge and agreement. By starting this recording, you '
            'confirm the patient has been informed and has agreed.',
            style: TextStyle(
              color: Color(0xFF8A9BB0),
              fontSize: 12.5,
              fontFamily: AppColors.bodyFontFamily,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => setState(() => _consentGiven = !_consentGiven),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _consentGiven
                        ? const Color(0xFF4A90D9)
                        : Colors.transparent,
                    border: Border.all(
                      color: _consentGiven
                          ? const Color(0xFF4A90D9)
                          : Colors.white38,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: _consentGiven
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Patient has been informed and consents to this recording',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontFamily: AppColors.bodyFontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingView() {
    return Center(
      child: Column(
        children: [
          // Pulsing mic
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE53935).withValues(alpha: 0.15),
                  border: Border.all(
                    color: const Color(0xFFE53935).withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.mic,
                  color: Color(0xFFE53935),
                  size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Timer
          Text(
            _timerLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w300,
              fontFamily: AppColors.headingFontFamily,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Recording in progress…',
            style: TextStyle(
              color: Color(0xFF8A9BB0),
              fontSize: 12,
              fontFamily: AppColors.bodyFontFamily,
            ),
          ),
          const SizedBox(height: 20),
          // Waveform
          SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_waveHeights.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 3,
                  height: 8 + 32 * _waveHeights[i],
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935).withValues(alpha:
                      0.4 + 0.6 * _waveHeights[i],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFE57373), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: const TextStyle(
                color: Color(0xFFE57373),
                fontSize: 13,
                fontFamily: AppColors.bodyFontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4A90D9).withValues(alpha: 0.12),
              ),
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF4A90D9),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Analysing consultation…',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              fontFamily: AppColors.headingFontFamily,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The AI is reviewing the recording and extracting the '
            'clinical note. This usually takes 15–30 seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8A9BB0),
              fontSize: 13,
              fontFamily: AppColors.bodyFontFamily,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    if (_isRecording) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _stopRecording,
          icon: const Icon(Icons.stop_rounded, size: 20),
          label: const Text(
            'Stop Recording',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: AppColors.bodyFontFamily,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE53935),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _consentGiven ? _startRecording : null,
            icon: const Icon(Icons.mic_rounded, size: 20),
            label: const Text(
              'Start Recording',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: AppColors.bodyFontFamily,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90D9),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white12,
              disabledForegroundColor: Colors.white38,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _cancel,
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: Color(0xFF8A9BB0),
              fontSize: 14,
              fontFamily: AppColors.bodyFontFamily,
            ),
          ),
        ),
      ],
    );
  }
}
