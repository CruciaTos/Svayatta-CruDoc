// desktop_scribe_screen.dart
//
// Full-panel AI Voice Scribe screen for the desktop shell.
//
// Rendered as a SizedBox.expand content-area widget (same structure as
// DesktopEventsScreen, DesktopInventoryScreen, etc.) so the sidebar stays
// visible throughout the entire recording → review flow.
//
// Internal navigation:
//   _ScribePhase.idle    → visit picker / start page
//   _ScribePhase.recording → recording + waveform view
//   _ScribePhase.processing → spinner while AI works
//   _ScribePhase.review    → editable draft review panel
//
// Nothing is written to the patient record here. That only happens when the
// doctor taps "Confirm & Save" in the review phase.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';

// ---------- Palette (matches the rest of the desktop UI) ----------
const Color _kTextPrimary   = Color(0xFF0F172A);
const Color _kTextSecondary = Color(0xFF64748B);
const Color _kBorder        = Color(0xFFE2E8F0);
const Color _kAccentBlue    = Color(0xFF0284C7);
const Color _kAccentBlueBg  = Color(0xFFF0F9FF);
const Color _kRed           = Color(0xFFF43F5E);
const Color _kRedBg         = Color(0xFFFFF1F2);
const Color _kGreen         = Color(0xFF10B981);
const Color _kGreenBg       = Color(0xFFECFDF5);
const Color _kSurface       = Color(0xFFF8FAFC);
const Color _kAmber         = Color(0xFFF59E0B);
const Color _kAmberBg       = Color(0xFFFFFBEB);

// ---------- Phase enum ----------
enum _ScribePhase { idle, recording, processing, review }

// ===========================================================================

class DesktopScribeScreen extends ConsumerStatefulWidget {
  const DesktopScribeScreen({super.key});

  @override
  ConsumerState<DesktopScribeScreen> createState() =>
      _DesktopScribeScreenState();
}

class _DesktopScribeScreenState extends ConsumerState<DesktopScribeScreen>
    with TickerProviderStateMixin {
  // ---- Phase ----
  _ScribePhase _phase = _ScribePhase.idle;

  // ---- Selected visit / patient ----
  Visit?   _visit;
  Patient? _patient;

  // ---- Consent ----
  bool _consentGiven = false;

  // ---- Recording ----
  final _recorder    = AudioRecorder();
  String? _audioPath;
  DateTime? _consentAt;
  Timer? _timer;
  int   _elapsedSeconds = 0;
  String? _errorMessage;
  final List<double> _waveHeights = List.filled(32, 0.3);

  // ---- Pulse animation ----
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ---- Draft review state ----
  ConsultationNote? _draft;

  // Draft review form controllers (created on demand)
  TextEditingController? _chiefComplaintCtrl;
  TextEditingController? _adviceCtrl;
  TextEditingController? _confidenceCtrl;
  TextEditingController? _bpCtrl;
  TextEditingController? _tempCtrl;
  TextEditingController? _pulseCtrl2;
  TextEditingController? _symptomAddCtrl;
  TextEditingController? _diagnosisAddCtrl;

  List<String>?        _symptoms;
  List<String>?        _diagnoses;
  List<NotedMedicine>? _medicines;
  DateTime?            _followUpDate;

  bool _isBusy        = false;
  bool _hasInteracted = false;
  final _reviewScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.16).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _reviewScrollCtrl.addListener(() {
      if (_reviewScrollCtrl.offset > 120 && !_hasInteracted) {
        setState(() => _hasInteracted = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseCtrl.dispose();
    _recorder.dispose();
    _disposeReviewControllers();
    _reviewScrollCtrl.dispose();
    super.dispose();
  }

  void _disposeReviewControllers() {
    _chiefComplaintCtrl?.dispose();
    _adviceCtrl?.dispose();
    _confidenceCtrl?.dispose();
    _bpCtrl?.dispose();
    _tempCtrl?.dispose();
    _pulseCtrl2?.dispose();
    _symptomAddCtrl?.dispose();
    _diagnosisAddCtrl?.dispose();
  }

  void _initReviewControllers(ConsultationNote n) {
    _disposeReviewControllers();
    _chiefComplaintCtrl = TextEditingController(text: n.chiefComplaint);
    _adviceCtrl         = TextEditingController(text: n.advice);
    _confidenceCtrl     = TextEditingController(text: n.confidenceNote);
    _bpCtrl             = TextEditingController(text: n.vitals['bp']    ?? '');
    _tempCtrl           = TextEditingController(text: n.vitals['temp']  ?? '');
    _pulseCtrl2         = TextEditingController(text: n.vitals['pulse'] ?? '');
    _symptomAddCtrl     = TextEditingController();
    _diagnosisAddCtrl   = TextEditingController();
    _symptoms           = List<String>.from(n.symptoms);
    _diagnoses          = List<String>.from(n.diagnosisSuggestions);
    _medicines          = List<NotedMedicine>.from(n.medicines);
    _followUpDate       = n.followUpDate;
    _hasInteracted      = false;
  }

  // ---- Timer label ----
  String get _timerLabel {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ---- Recording flow ----

  Future<void> _startRecording() async {
    if (!_consentGiven || _visit == null) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      setState(() {
        _errorMessage =
            'Microphone permission denied. Please grant it in system settings.';
      });
      return;
    }

    final dir  = await getApplicationDocumentsDirectory();
    final id   = const Uuid().v4();
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
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _elapsedSeconds++;
        for (var i = 0; i < _waveHeights.length; i++) {
          _waveHeights[i] =
              0.2 + 0.8 * (((_elapsedSeconds * 7 + i * 13) % 10) / 10.0);
        }
      });
    });

    _pulseCtrl.repeat(reverse: true);
    setState(() {
      _phase        = _ScribePhase.recording;
      _errorMessage = null;
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    await _recorder.stop();
    if (!mounted) return;
    setState(() => _phase = _ScribePhase.processing);
    await _processAudio();
  }

  Future<void> _processAudio() async {
    final audioPath = _audioPath;
    if (audioPath == null) {
      setState(() {
        _errorMessage = 'Recording path is missing. Please try again.';
        _phase        = _ScribePhase.recording;
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
        _phase        = _ScribePhase.recording;
      });
      return;
    }

    try {
      final noteId = const Uuid().v4();
      final draft  = await processingService.processAudio(
        localAudioPath:    audioPath,
        audioStoragePath:  null,
        noteId:            noteId,
        doctorId:          user.uid,
        patientId:         _visit!.patientId,
        visitId:           _visit!.id,
        consentAt:         _consentAt ?? DateTime.now(),
      );

      try { await File(audioPath).delete(); } catch (_) {}
      await repo.saveNote(draft);

      if (!mounted) return;
      _initReviewControllers(draft);
      setState(() {
        _draft = draft;
        _phase = _ScribePhase.review;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Processing failed: ${e.toString().replaceAll('Exception:', '').trim()}';
          _phase = _ScribePhase.recording;
        });
      }
    }
  }

  void _cancelRecording() {
    _timer?.cancel();
    _pulseCtrl.stop();
    _recorder.stop();
    setState(() {
      _phase        = _ScribePhase.idle;
      _errorMessage = null;
      _consentGiven = false;
    });
  }

  // ---- Review actions ----

  ConsultationNote _buildCurrentNote() {
    return _draft!.copyWith(
      chiefComplaint:       _chiefComplaintCtrl!.text.trim(),
      symptoms:             _symptoms!.where((s) => s.trim().isNotEmpty).toList(),
      diagnosisSuggestions: _diagnoses!.where((d) => d.trim().isNotEmpty).toList(),
      medicines:            _medicines!.where((m) => m.name.trim().isNotEmpty).toList(),
      advice:               _adviceCtrl!.text.trim(),
      followUpDate:         _followUpDate,
      clearFollowUpDate:    _followUpDate == null,
      vitals: {
        'bp':    _bpCtrl!.text.trim().isEmpty    ? null : _bpCtrl!.text.trim(),
        'temp':  _tempCtrl!.text.trim().isEmpty   ? null : _tempCtrl!.text.trim(),
        'pulse': _pulseCtrl2!.text.trim().isEmpty ? null : _pulseCtrl2!.text.trim(),
      },
      confidenceNote: _confidenceCtrl!.text.trim(),
    );
  }

  Future<void> _confirmNote() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final repo = ref.read(consultationNoteRepositoryProvider);
    try {
      final updated = _buildCurrentNote();
      await repo.saveNote(updated);
      await repo.confirmNote(updated);
      if (!mounted) return;
      _showSuccess('Clinical note confirmed and saved to patient record.');
      _resetToIdle();
    } catch (e) {
      if (mounted) {
        _showError('Failed to confirm note: $e');
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _discardNote() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Discard this draft?',
            style: TextStyle(color: _kTextPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          'The AI draft will be deleted and no changes will be made to the patient record.',
          style: TextStyle(color: _kTextSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep reviewing',
                style: TextStyle(color: _kAccentBlue)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard',
                style: TextStyle(
                    color: _kRed, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isBusy = true);
    final repo = ref.read(consultationNoteRepositoryProvider);
    try {
      await repo.discardNote(_draft!);
      _resetToIdle();
    } catch (_) {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _resetToIdle() {
    setState(() {
      _phase        = _ScribePhase.idle;
      _visit        = null;
      _patient      = null;
      _consentGiven = false;
      _draft        = null;
      _errorMessage = null;
      _isBusy       = false;
    });
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _kGreen),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _kRed),
    );
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  Widget _buildPhase() {
    switch (_phase) {
      case _ScribePhase.idle:
        return _buildIdleView();
      case _ScribePhase.recording:
        return _buildRecordingView();
      case _ScribePhase.processing:
        return _buildProcessingView();
      case _ScribePhase.review:
        return _buildReviewView();
    }
  }

  // =========================================================================
  // IDLE VIEW — visit picker
  // =========================================================================

  Widget _buildIdleView() {
    final visitsAsync = ref.watch(todaysVisitsWithPatientsProvider);

    return Column(
      children: [
        _buildPageHeader(
          icon: Icons.mic_rounded,
          title: 'AI Voice Scribe',
          subtitle: 'Select a visit to start recording',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info banner
                _buildInfoBanner(),
                const SizedBox(height: 24),
                const Text(
                  'SELECT A VISIT',
                  style: TextStyle(
                    color: _kTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                visitsAsync.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e',
                      style:
                          const TextStyle(color: _kRed)),
                  data: (visits) => visits.isEmpty
                      ? _buildNoVisitsCard()
                      : Column(
                          children: visits
                              .map((vwp) => _buildVisitCard(
                                    vwp.visit,
                                    vwp.patient,
                                  ))
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kAccentBlueBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kAccentBlue.withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.auto_awesome_rounded,
              color: _kAccentBlue, size: 20),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI-powered clinical note generation',
                  style: TextStyle(
                    color: _kAccentBlue,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Record your consultation and the AI will extract a structured '
                  'draft note. You must review and confirm before anything is '
                  'saved to the patient record.',
                  style: TextStyle(
                    color: _kAccentBlue,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoVisitsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: const Center(
        child: Column(
          children: [
            Icon(Icons.event_busy_rounded,
                color: _kTextSecondary, size: 40),
            SizedBox(height: 12),
            Text(
              'No visits today',
              style: TextStyle(
                color: _kTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              "Schedule a visit first, then come back to record.",
              style: TextStyle(color: _kTextSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitCard(Visit visit, Patient? patient) {
    final isSelected = _visit?.id == visit.id;
    return GestureDetector(
      onTap: () => setState(() {
        _visit   = visit;
        _patient = patient;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? _kAccentBlueBg : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? _kAccentBlue
                : _kBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? _kAccentBlue
                    : _kSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_rounded,
                color: isSelected
                    ? Colors.white
                    : _kTextSecondary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient?.fullName ?? 'Unknown Patient',
                    style: TextStyle(
                      color: isSelected
                          ? _kAccentBlue
                          : _kTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${visit.visitType == VisitType.home ? 'Home visit' : 'Clinic'}'
                    ' · ${DateFormat('h:mm a').format(visit.scheduledStart)}',
                    style: const TextStyle(
                        color: _kTextSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded,
                  color: _kAccentBlue, size: 22),
          ],
        ),
      ),
    );
  }

  // ---- Idle bottom: Consent + Start ----

  Widget _buildIdleBottom() {
    if (_visit == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Consent checkbox
          InkWell(
            onTap: () =>
                setState(() => _consentGiven = !_consentGiven),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _consentGiven
                        ? _kAccentBlue
                        : Colors.transparent,
                    border: Border.all(
                      color: _consentGiven
                          ? _kAccentBlue
                          : const Color(0xFFCBD5E1),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: _consentGiven
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 14)
                      : null,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Patient has been informed and consents to this recording',
                    style: TextStyle(
                        color: _kTextPrimary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_errorMessage != null) ...[
            _buildErrorBanner(_errorMessage!),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _consentGiven ? _startRecording : null,
              icon: const Icon(Icons.mic_rounded, size: 18),
              label: const Text('Start Recording',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccentBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE2E8F0),
                disabledForegroundColor: const Color(0xFF94A3B8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // RECORDING VIEW
  // =========================================================================

  Widget _buildRecordingView() {
    return Column(
      children: [
        _buildPageHeader(
          icon: Icons.mic_rounded,
          title: 'AI Voice Scribe',
          subtitle: _patient?.fullName ?? 'Recording…',
          trailing: TextButton.icon(
            onPressed: _cancelRecording,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(
                foregroundColor: _kTextSecondary),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing mic orb
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, child) => Transform.scale(
                    scale: _pulseAnim.value,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kRed.withValues(alpha: 0.10),
                        border: Border.all(
                            color: _kRed.withValues(alpha: 0.4),
                            width: 2.5),
                      ),
                      child: const Icon(Icons.mic,
                          color: _kRed, size: 40),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _timerLabel,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 36,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 6),
                const Text('Recording in progress…',
                    style: TextStyle(
                        color: _kTextSecondary, fontSize: 13)),
                const SizedBox(height: 24),
                // Waveform
                SizedBox(
                  height: 48,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _waveHeights.length,
                      (i) => AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 150),
                        width: 3.5,
                        height: 8 + 40 * _waveHeights[i],
                        margin: const EdgeInsets.symmetric(
                            horizontal: 2),
                        decoration: BoxDecoration(
                          color: _kRed.withValues(
                              alpha: 0.35 +
                                  0.55 * _waveHeights[i]),
                          borderRadius:
                              BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                if (_errorMessage != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40),
                    child: _buildErrorBanner(_errorMessage!),
                  ),
                  const SizedBox(height: 20),
                ],
                SizedBox(
                  width: 220,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _stopRecording,
                    icon: const Icon(Icons.stop_rounded,
                        size: 20),
                    label: const Text('Stop Recording',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // PROCESSING VIEW
  // =========================================================================

  Widget _buildProcessingView() {
    return Column(
      children: [
        _buildPageHeader(
          icon: Icons.mic_rounded,
          title: 'AI Voice Scribe',
          subtitle: 'Analysing…',
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kAccentBlueBg,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: _kAccentBlue),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Analysing consultation…',
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The AI is reviewing the recording and extracting the '
                  'clinical note.\nThis usually takes 15–30 seconds.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _kTextSecondary,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // REVIEW VIEW
  // =========================================================================

  Widget _buildReviewView() {
    if (_draft == null ||
        _chiefComplaintCtrl == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        _buildPageHeader(
          icon: Icons.description_outlined,
          title: 'Review Clinical Note',
          subtitle: _patient?.fullName ?? 'Unknown Patient',
          trailing: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kAmberBg,
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: _kAmber.withValues(alpha: 0.4)),
            ),
            child: const Text(
              'DRAFT',
              style: TextStyle(
                color: _kAmber,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        // AI banner
        Container(
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kAccentBlueBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _kAccentBlue.withValues(alpha: 0.25)),
          ),
          child: const Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  color: _kAccentBlue, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'AI-generated draft — review and edit every field before '
                  'confirming. Only you can approve what goes into the patient record.',
                  style: TextStyle(
                    color: _kAccentBlue,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Scrollable form
        Expanded(
          child: ListView(
            controller: _reviewScrollCtrl,
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
            children: [
              _reviewSection(
                'CHIEF COMPLAINT',
                _buildTextField(_chiefComplaintCtrl!,
                    hint: 'e.g. Headache for 3 days'),
              ),
              const SizedBox(height: 12),
              _reviewSection(
                'SYMPTOMS',
                _buildChipEditor(
                  items: _symptoms!,
                  addCtrl: _symptomAddCtrl!,
                  hint: 'Add symptom…',
                  chipColor: const Color(0xFF0EA5E9),
                  onUpdate: (v) => setState(() {
                    _symptoms = v;
                    _markInteracted();
                  }),
                ),
              ),
              const SizedBox(height: 12),
              _reviewSection(
                'DIAGNOSIS SUGGESTIONS',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_patient != null &&
                        _patient!.diagnosis.isNotEmpty)
                      _buildExistingDiagnosesChip(),
                    const SizedBox(height: 8),
                    _buildChipEditor(
                      items: _diagnoses!,
                      addCtrl: _diagnosisAddCtrl!,
                      hint: 'Add diagnosis…',
                      chipColor: const Color(0xFF7C3AED),
                      onUpdate: (v) => setState(() {
                        _diagnoses = v;
                        _markInteracted();
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _reviewSection(
                  'MEDICINES', _buildMedicinesEditor()),
              const SizedBox(height: 12),
              _reviewSection(
                'ADVICE / PLAN',
                _buildTextField(_adviceCtrl!,
                    hint: 'e.g. Rest, stay hydrated…',
                    maxLines: 4),
              ),
              const SizedBox(height: 12),
              _reviewSection(
                  'VITALS (if mentioned)', _buildVitalsRow()),
              const SizedBox(height: 12),
              _reviewSection(
                  'FOLLOW-UP DATE', _buildFollowUpPicker()),
              if (_confidenceCtrl!.text.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildConfidenceNote(),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
        // Bottom bar
        _buildReviewBottomBar(),
      ],
    );
  }

  void _markInteracted() {
    if (!_hasInteracted) setState(() => _hasInteracted = true);
  }

  Widget _reviewSection(String label, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _kTextSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl,
      {String hint = '', int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      minLines: 1,
      onChanged: (_) => _markInteracted(),
      style: const TextStyle(color: _kTextPrimary, fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: _kTextSecondary, fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: _kAccentBlue, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildChipEditor({
    required List<String> items,
    required TextEditingController addCtrl,
    required String hint,
    required Color chipColor,
    required ValueChanged<List<String>> onUpdate,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.asMap().entries.map((e) => Chip(
                  label: Text(e.value,
                      style: TextStyle(
                          color: chipColor, fontSize: 12.5)),
                  backgroundColor:
                      chipColor.withValues(alpha: 0.08),
                  side: BorderSide(
                      color: chipColor.withValues(alpha: 0.3)),
                  deleteIconColor:
                      chipColor.withValues(alpha: 0.7),
                  onDeleted: () {
                    final updated = List<String>.from(items)
                      ..removeAt(e.key);
                    onUpdate(updated);
                  },
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                )).toList(),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: addCtrl,
                style: const TextStyle(
                    color: _kTextPrimary, fontSize: 13),
                decoration: _fieldDeco(hint),
                onSubmitted: (val) {
                  if (val.trim().isEmpty) return;
                  onUpdate([...items, val.trim()]);
                  addCtrl.clear();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle_outline,
                  color: _kAccentBlue, size: 22),
              onPressed: () {
                final val = addCtrl.text.trim();
                if (val.isEmpty) return;
                onUpdate([...items, val]);
                addCtrl.clear();
              },
              tooltip: 'Add',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExistingDiagnosesChip() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kGreenBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Existing diagnoses on record:',
              style:
                  TextStyle(color: _kTextSecondary, fontSize: 11)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _patient!.diagnosis.map((d) => Chip(
                  label: Text(d,
                      style: const TextStyle(
                          color: _kGreen, fontSize: 12)),
                  backgroundColor:
                      _kGreen.withValues(alpha: 0.08),
                  side: BorderSide(
                      color: _kGreen.withValues(alpha: 0.3)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicinesEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._medicines!.asMap().entries.map(
            (e) => _buildMedicineRow(e.key, e.value)),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => setState(() {
            _medicines!.add(const NotedMedicine(name: ''));
            _markInteracted();
          }),
          icon: const Icon(Icons.add, size: 16, color: _kAccentBlue),
          label: const Text('Add medicine',
              style: TextStyle(
                  color: _kAccentBlue, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildMedicineRow(int index, NotedMedicine med) {
    final nameCtrl   = TextEditingController(text: med.name);
    final dosageCtrl = TextEditingController(text: med.dosage);
    final instrCtrl  = TextEditingController(text: med.instructions);

    void update() => setState(() {
          _medicines![index] = NotedMedicine(
            name: nameCtrl.text,
            dosage: dosageCtrl.text,
            instructions: instrCtrl.text,
          );
          _markInteracted();
        });

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nameCtrl,
                  onChanged: (_) => update(),
                  style: const TextStyle(
                      color: _kTextPrimary, fontSize: 13),
                  decoration: _fieldDeco('Medicine name'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: _kRed, size: 20),
                onPressed: () =>
                    setState(() => _medicines!.removeAt(index)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: dosageCtrl,
                  onChanged: (_) => update(),
                  style: const TextStyle(
                      color: _kTextPrimary, fontSize: 12.5),
                  decoration: _fieldDeco('Dosage'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: instrCtrl,
                  onChanged: (_) => update(),
                  style: const TextStyle(
                      color: _kTextPrimary, fontSize: 12.5),
                  decoration: _fieldDeco('Instructions'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: _kTextSecondary, fontSize: 12),
        filled: true,
        fillColor: _kSurface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: _kAccentBlue, width: 1.5),
        ),
      );

  Widget _buildVitalsRow() => Row(
        children: [
          Expanded(child: _buildVitalField(_bpCtrl!, 'BP (mmHg)')),
          const SizedBox(width: 8),
          Expanded(
              child: _buildVitalField(_tempCtrl!, 'Temp (°F/°C)')),
          const SizedBox(width: 8),
          Expanded(
              child: _buildVitalField(_pulseCtrl2!, 'Pulse (bpm)')),
        ],
      );

  Widget _buildVitalField(TextEditingController ctrl, String hint) =>
      TextField(
        controller: ctrl,
        onChanged: (_) => _markInteracted(),
        style: const TextStyle(color: _kTextPrimary, fontSize: 13),
        decoration: _fieldDeco(hint),
      );

  Widget _buildFollowUpPicker() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _followUpDate ??
              DateTime.now().add(const Duration(days: 7)),
          firstDate: DateTime.now(),
          lastDate:
              DateTime.now().add(const Duration(days: 365 * 2)),
        );
        if (picked != null) {
          setState(() {
            _followUpDate  = picked;
            _hasInteracted = true;
          });
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                color: _kTextSecondary, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _followUpDate != null
                    ? DateFormat('d MMM yyyy')
                        .format(_followUpDate!)
                    : 'No follow-up date (click to set)',
                style: TextStyle(
                  color: _followUpDate != null
                      ? _kTextPrimary
                      : _kTextSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            if (_followUpDate != null)
              GestureDetector(
                onTap: () =>
                    setState(() => _followUpDate = null),
                child: const Icon(Icons.close,
                    color: _kTextSecondary, size: 16),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfidenceNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kAmberBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _kAmber.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: _kAmber, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Confidence Note',
                  style: TextStyle(
                    color: _kAmber,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _confidenceCtrl!.text,
                  style: const TextStyle(
                    color: _kTextSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_hasInteracted)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Scroll through or edit a field to enable Confirm',
                style: TextStyle(
                    color: _kTextSecondary, fontSize: 11.5),
                textAlign: TextAlign.center,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isBusy ? null : _discardNote,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kRed,
                    side: BorderSide(
                        color: _kRed.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Discard',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: (_isBusy || !_hasInteracted)
                      ? null
                      : _confirmNote,
                  icon: _isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white),
                        )
                      : const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18),
                  label: const Text('Confirm & Save',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFFE2E8F0),
                    disabledForegroundColor:
                        const Color(0xFF94A3B8),
                    padding: const EdgeInsets.symmetric(
                        vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // SHARED HELPERS
  // =========================================================================

  Widget _buildPageHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kAccentBlueBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _kAccentBlue, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                      color: _kTextSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[trailing],
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kRedBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: _kRed, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: const TextStyle(
                    color: _kRed, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // Idle view override: the body + bottom bar need to be stitched together
  @override
  Widget build(BuildContext context) {
    // Override build to stitch the idle bottom bar in
    if (_phase == _ScribePhase.idle) {
      return SizedBox.expand(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFCBD5E1),
                  width: 0.5,
                ),
              ),
              child: Column(
                children: [
                  _buildPageHeader(
                    icon: Icons.mic_rounded,
                    title: 'AI Voice Scribe',
                    subtitle: 'Select a visit to start recording',
                  ),
                  Expanded(child: _buildIdleBody()),
                  _buildIdleBottom(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFCBD5E1),
                width: 0.5,
              ),
            ),
            child: _buildPhase(),
          ),
        ),
      ),
    );
  }

  Widget _buildIdleBody() {
    final visitsAsync = ref.watch(todaysVisitsWithPatientsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoBanner(),
          const SizedBox(height: 24),
          const Text(
            'SELECT A VISIT',
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          visitsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e',
                style: const TextStyle(color: _kRed)),
            data: (visits) => visits.isEmpty
                ? _buildNoVisitsCard()
                : Column(
                    children: visits
                        .map((vwp) =>
                            _buildVisitCard(vwp.visit, vwp.patient))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
