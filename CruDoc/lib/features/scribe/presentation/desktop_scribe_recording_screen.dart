// desktop_scribe_recording_screen.dart
//
// Desktop-native replacement for [ScribeRecordingSheet]. Same underlying
// flow and the exact same service/repo/provider layer — only the shell
// changes: a centered, fixed-width dialog that matches the rest of the
// desktop app (see desktop_patient_details_screen.dart's colour tokens)
// instead of a full-width bottom sheet.
//
// Flow (identical to the mobile version):
//   1. Consent checkbox + explainer → doctor must check before recording
//   2. Tap "Start Recording" → mic permission prompt → recording starts
//   3. Animated waveform + elapsed timer shown during recording
//   4. Tap "Stop" → audio written to local storage → processing begins
//   5. On processing complete → the desktop draft review dialog opens
//      automatically, replacing this one.
//
// Nothing is written to the patient record here. That only happens if
// the doctor taps Confirm on the review dialog.
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/scribe/presentation/desktop_scribe_draft_review_screen.dart';

// ---------- Desktop dashboard palette (matches desktop_patient_details_screen.dart) ----------
const Color _kTextPrimary = Color(0xFF1F2937);
const Color _kTextSecondary = Color(0xFF6B7280);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kAccentBlue = Color(0xFF2563EB);
const Color _kAccentBlueBg = Color(0xFFEFF6FF);
const Color _kRed = Color(0xFFDC2626);
const Color _kRedBg = Color(0xFFFEF2F2);

/// Opens the desktop AI Voice Scribe flow for [visit] / [patient].
///
/// Returns `true` if a note was ultimately reviewed and confirmed into
/// the patient record (via the chained draft review dialog), `false`
/// if the doctor cancelled or discarded at any point.
Future<bool> showDesktopScribeRecordingDialog(
  BuildContext context, {
  required Visit visit,
  required Patient? patient,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DesktopScribeRecordingDialog(visit: visit, patient: patient),
  );
  return result ?? false;
}

class _DesktopScribeRecordingDialog extends ConsumerStatefulWidget {
  final Visit visit;
  final Patient? patient;

  const _DesktopScribeRecordingDialog({
    required this.visit,
    required this.patient,
  });

  @override
  ConsumerState<_DesktopScribeRecordingDialog> createState() =>
      _DesktopScribeRecordingDialogState();
}

class _DesktopScribeRecordingDialogState
    extends ConsumerState<_DesktopScribeRecordingDialog>
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

  final List<double> _waveHeights = List.filled(24, 0.3);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.16).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  String get _timerLabel {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _patientName => widget.patient?.fullName ?? 'Unknown Patient';

  // ---- Recording logic (identical to the mobile sheet) ----

  Future<void> _startRecording() async {
    if (!_consentGiven) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Microphone permission denied. Please grant it in system settings.';
        });
      }
      return;
    }

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
        for (var i = 0; i < _waveHeights.length; i++) {
          _waveHeights[i] = 0.2 + 0.8 * (((_elapsedSeconds * 7 + i * 13) % 10) / 10.0);
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

      final draft = await processingService.processAudio(
        localAudioPath: audioPath,
        audioStoragePath: null,
        noteId: noteId,
        doctorId: user.uid,
        patientId: widget.visit.patientId,
        visitId: widget.visit.id,
        consentAt: _consentAt ?? DateTime.now(),
      );

      try {
        await File(audioPath).delete();
      } catch (_) {}

      await repo.saveNote(draft);

      if (!mounted) return;

      // Close this dialog and immediately open the draft review dialog —
      // the doctor never leaves dialog-space, and the shell/sidebar stay
      // visible behind the scrim the whole time.
      Navigator.of(context).pop(false);
      final confirmed = await showDesktopScribeDraftReviewDialog(
        context,
        note: draft,
        patient: widget.patient,
      );
      if (context.mounted && confirmed == true) {
        // Nothing further to do here — the caller of
        // showDesktopScribeRecordingDialog already awaits this whole
        // chain and gets `true` back via the outer wrapper.
      }
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
    Navigator.of(context).pop(false);
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
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
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kAccentBlueBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.mic_rounded, color: _kAccentBlue, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI Voice Scribe',
                    style: TextStyle(
                      color: _kTextPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _patientName,
                    style: const TextStyle(color: _kTextSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (!_isRecording)
              IconButton(
                icon: const Icon(Icons.close_rounded, color: _kTextSecondary),
                onPressed: _cancel,
                tooltip: 'Close',
              ),
          ],
        ),
        const SizedBox(height: 22),
        if (!_isRecording) ...[
          _buildConsentCard(),
          const SizedBox(height: 18),
        ],
        if (_errorMessage != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: 14),
        ],
        if (_isRecording) ...[
          _buildRecordingView(),
          const SizedBox(height: 22),
        ],
        _buildActions(),
      ],
    );
  }

  Widget _buildConsentCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _consentGiven ? _kAccentBlue.withValues(alpha: 0.4) : _kBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Patient Consent',
            style: TextStyle(
              color: _kTextPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Recording a clinical consultation requires the patient\'s '
            'knowledge and agreement. By starting this recording, you '
            'confirm the patient has been informed and has agreed.',
            style: TextStyle(color: _kTextSecondary, fontSize: 12.5, height: 1.5),
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
                    color: _consentGiven ? _kAccentBlue : Colors.transparent,
                    border: Border.all(
                      color: _consentGiven ? _kAccentBlue : const Color(0xFFCBD5E1),
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
                    style: TextStyle(color: _kTextPrimary, fontSize: 13),
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
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kRed.withValues(alpha: 0.1),
                  border: Border.all(color: _kRed.withValues(alpha: 0.4), width: 2),
                ),
                child: const Icon(Icons.mic, color: _kRed, size: 32),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _timerLabel,
            style: const TextStyle(
              color: _kTextPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w300,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Recording in progress…',
            style: TextStyle(color: _kTextSecondary, fontSize: 12),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 38,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_waveHeights.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 3,
                  height: 8 + 30 * _waveHeights[i],
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _kRed.withValues(alpha: 0.35 + 0.55 * _waveHeights[i]),
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
        color: _kRedBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _kRed, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: const TextStyle(color: _kRed, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kAccentBlueBg,
            ),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(strokeWidth: 3, color: _kAccentBlue),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Analysing consultation…',
            style: TextStyle(
              color: _kTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The AI is reviewing the recording and extracting the clinical '
            'note. This usually takes 15–30 seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kTextSecondary, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    if (_isRecording) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: _stopRecording,
          icon: const Icon(Icons.stop_rounded, size: 18),
          label: const Text('Stop Recording',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kRed,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _cancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: _kTextSecondary,
              side: const BorderSide(color: _kBorder),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 14)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _consentGiven ? _startRecording : null,
            icon: const Icon(Icons.mic_rounded, size: 18),
            label: const Text('Start Recording',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccentBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE2E8F0),
              disabledForegroundColor: const Color(0xFF94A3B8),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}
