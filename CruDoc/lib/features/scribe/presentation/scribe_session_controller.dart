import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/repo/consultation_note_repository.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_draft_form_controller.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_live_extractor.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_processing_service.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_transcript_formatter.dart';
import 'package:doctor_management_app/features/voice/presentation/voice_dialog_hook.dart';
import 'package:doctor_management_app/features/voice/services/speech_engine.dart';

/// Where a scribe session is in its lifecycle.
enum ScribeSessionPhase {
  /// Consent + start screen.
  ready,
  recording,
  paused,

  /// Audio is with the AI.
  processing,

  /// Processing failed; the recording is kept so the doctor can retry.
  failed,

  /// [ScribeSessionController.draft] is ready for review.
  done,
}

/// Recording → processing state machine shared by the mobile sheet and the
/// desktop scribe screen, so both behave identically and only differ in
/// layout.
///
/// Nothing here touches the patient record: a successful run only saves a
/// local draft and exposes it via [draft] for the review UI.
class ScribeSessionController extends ChangeNotifier {
  ScribeSessionController({
    required this.visit,
    required ScribeProcessingService processingService,
    required ConsultationNoteRepository repository,
    AudioRecorder? recorder,
  }) : _processingService = processingService,
       _repository = repository,
       _recorder = recorder ?? AudioRecorder();

  /// Number of bars the live waveform shows.
  static const levelCount = 48;

  /// Mono 16 kHz AAC at a speech bitrate (~4 KB/s): plenty for transcription
  /// and keeps long consultations under the inline upload limit.
  static const recordConfig = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 32000,
    sampleRate: 16000,
    numChannels: 1,
    autoGain: true,
  );

  static const _staleRecordingAge = Duration(days: 1);

  /// Peak level (dBFS) a recording must reach to count as containing speech.
  static const _silenceThresholdDb = -50.0;

  final Visit visit;
  final ScribeProcessingService _processingService;
  final ConsultationNoteRepository _repository;
  final AudioRecorder _recorder;

  ScribeSessionPhase _phase = ScribeSessionPhase.ready;
  ScribeSessionPhase get phase => _phase;

  bool _consentGiven = false;
  bool get consentGiven => _consentGiven;

  String? _error;

  /// Message for the current problem (permission, too short, AI failure…).
  String? get error => _error;

  ScribeFailureKind? _failureKind;
  bool get canRetry =>
      _phase == ScribeSessionPhase.failed &&
      _audioPath != null &&
      (_failureKind?.isRetryable ?? false);

  ConsultationNote? _draft;
  ConsultationNote? get draft => _draft;

  ConsultationNote? _pendingDraft;

  /// An unreviewed draft saved earlier for this visit, if any.
  ConsultationNote? get pendingDraft => _pendingDraft;

  /// Elapsed recording time (excludes pauses). Separate notifier so the
  /// timer can tick without rebuilding the whole screen.
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  /// Recent normalised mic levels (0–1), newest last.
  final ValueNotifier<List<double>> levels = ValueNotifier(
    List<double>.filled(levelCount, 0),
  );

  /// Seconds spent processing so far — drives the progress copy.
  final ValueNotifier<int> processingSeconds = ValueNotifier(0);

  bool get isBusy =>
      _phase == ScribeSessionPhase.recording ||
      _phase == ScribeSessionPhase.paused ||
      _phase == ScribeSessionPhase.processing;

  /// True when closing now would lose a recording.
  bool get hasUnsavedAudio =>
      _audioPath != null && _phase != ScribeSessionPhase.done;

  ScribeDraftFormController? activeDraftForm;

  /// Hands over ownership of the [activeDraftForm] to the review UI,
  /// clearing the local reference so disposing the session won't dispose it.
  ScribeDraftFormController? takeActiveDraftForm() {
    final form = activeDraftForm;
    activeDraftForm = null;
    return form;
  }

  final ScribeLiveExtractor _extractor = const ScribeLiveExtractor();
  String _accumulatedTranscript = '';
  String get accumulatedTranscript => _accumulatedTranscript;
  StreamSubscription<VoiceTranscript>? _transcriptSub;

  String? _audioPath;
  DateTime? _consentAt;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  Timer? _processingTicker;
  StreamSubscription<Amplitude>? _amplitudeSub;
  double _peakDb = -160;
  double? _firstDb;
  bool _levelsVaried = false;
  bool _finishing = false;
  bool _disposed = false;

  // ---- Setup ----

  /// Looks up an unreviewed draft for this visit so it can be resumed.
  Future<void> loadPendingDraft() async {
    try {
      final pending = await _repository.getDraftForVisit(visit.id);
      if (_disposed) return;
      _pendingDraft = pending;
      _notify();
    } catch (e) {
      debugPrint('[ScribeSession] Could not load pending draft: $e');
    }
  }

  void setConsent(bool value) {
    if (_phase != ScribeSessionPhase.ready) return;
    _consentGiven = value;
    _error = null;
    _notify();
  }

  // ---- Recording ----

  Future<void> start() async {
    if (!_consentGiven || _phase != ScribeSessionPhase.ready) return;
    _error = null;

    final doctorId = FirebaseAuth.instance.currentUser?.uid ?? 'local_doctor';
    final initialNote =
        _pendingDraft ??
        ConsultationNote(
          id: const Uuid().v4(),
          doctorId: doctorId,
          patientId: visit.patientId,
          visitId: visit.id,
          consentGiven: true,
          consentAt: DateTime.now(),
          status: ConsultationNoteStatus.draft,
          createdAt: DateTime.now(),
        );
    activeDraftForm ??= ScribeDraftFormController(initialNote);
    _accumulatedTranscript = '';

    // Mark openKind as scribe so VoiceController treats this as dedicated consultation session
    VoiceBus.openKind.value = 'scribe';

    // Start live speech engine transcription
    try {
      await SpeechEngine.instance.init();
      await SpeechEngine.instance.start();
      _transcriptSub?.cancel();
      _transcriptSub = SpeechEngine.instance.transcripts.listen(
        _onLiveTranscript,
      );
    } catch (e) {
      debugPrint(
        '[ScribeSession] Live speech engine transcription warning: $e',
      );
    }

    if (!kIsWeb) {
      try {
        final path = await _newRecordingPath();
        await _recorder.start(recordConfig, path: path);
        _audioPath = path;
      } catch (e) {
        debugPrint('[ScribeSession] File recorder warning: $e');
      }
    }

    _consentAt = DateTime.now();
    _peakDb = -160;
    _firstDb = null;
    _levelsVaried = false;
    levels.value = List<double>.filled(levelCount, 0);
    elapsed.value = Duration.zero;
    _stopwatch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 90))
        .listen(_onAmplitude, onError: (_) {});
    _phase = ScribeSessionPhase.recording;
    _notify();
  }

  void _onLiveTranscript(VoiceTranscript t) {
    if (_phase != ScribeSessionPhase.recording) return;

    if (t.source == 'fast') {
      // 1. Fast stream cue detection: immediately dissolve relevant fields
      final cues = _extractor.detectFieldCues(t.text);
      for (final field in cues) {
        activeDraftForm?.setFieldPending(field, true);
      }
    } else {
      // 2. Accurate stream: extract clinical entities and merge into active draft
      if (t.text.trim().isNotEmpty) {
        _accumulatedTranscript = ScribeTranscriptFormatter.mergeLiveChunk(
          _accumulatedTranscript,
          t.text,
        );
      }
      final ext = _extractor.extract(
        _accumulatedTranscript.isNotEmpty ? _accumulatedTranscript : t.text,
      );
      activeDraftForm?.mergeLiveExtraction(ext);
    }
  }

  /// Manually simulates a speech utterance for testing live consultation scribing
  void simulateSpeechTurn(String text) {
    _onLiveTranscript(VoiceTranscript(text, isFinal: false, source: 'fast'));
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!_disposed) {
        _onLiveTranscript(
          VoiceTranscript(text, isFinal: true, source: 'accurate'),
        );
      }
    });
  }

  Future<void> pause() async {
    if (_phase != ScribeSessionPhase.recording) return;
    try {
      await _recorder.pause();
    } catch (e) {
      debugPrint('[ScribeSession] Pause failed: $e');
    }
    unawaited(SpeechEngine.instance.stop());
    _stopwatch.stop();
    levels.value = List<double>.filled(levelCount, 0);
    _phase = ScribeSessionPhase.paused;
    _notify();
  }

  Future<void> resume() async {
    if (_phase != ScribeSessionPhase.paused) return;
    try {
      await _recorder.resume();
    } catch (e) {
      debugPrint('[ScribeSession] Resume failed: $e');
    }
    unawaited(SpeechEngine.instance.start());
    _stopwatch.start();
    _phase = ScribeSessionPhase.recording;
    _notify();
  }

  /// Stops recording and sends the audio for processing. On success the
  /// phase becomes [ScribeSessionPhase.done] with [draft] set.
  Future<void> finish() async {
    if (_finishing ||
        (_phase != ScribeSessionPhase.recording &&
            _phase != ScribeSessionPhase.paused)) {
      return;
    }
    _finishing = true;
    try {
      await _finishRecording();
    } finally {
      _finishing = false;
    }
  }

  Future<void> _finishRecording() async {
    final duration = _stopwatch.elapsed;
    await _stopRecorder();

    if (duration < ScribeProcessingService.minRecordingDuration) {
      await _deleteAudio();
      _phase = ScribeSessionPhase.ready;
      _setError(
        'That recording was too short. Record at least '
        '${ScribeProcessingService.minRecordingDuration.inSeconds} seconds '
        'of the consultation.',
      );
      return;
    }

    // Only trust silence detection on platforms that actually reported
    // changing levels — a constant reading means levels are unsupported.
    if (_levelsVaried && _peakDb < _silenceThresholdDb) {
      await _deleteAudio();
      _phase = ScribeSessionPhase.ready;
      _setError(
        'No speech was picked up. Check that the right microphone '
        'is selected and try again.',
      );
      return;
    }

    await _process();
  }

  /// Re-sends the kept recording after a failure.
  Future<void> retry() async {
    if (!canRetry) return;
    await _process();
  }

  /// Stops and throws away the current recording without processing it.
  Future<void> discardRecording() async {
    if (_phase == ScribeSessionPhase.processing) return;
    await _stopRecorder(cancel: true);
    await _deleteAudio();
    activeDraftForm?.dispose();
    activeDraftForm = null;
    _accumulatedTranscript = '';
    _phase = ScribeSessionPhase.ready;
    _error = null;
    _failureKind = null;
    elapsed.value = Duration.zero;
    levels.value = List<double>.filled(levelCount, 0);
    _notify();
  }

  /// Skips the AI and opens an empty note for the doctor to fill in —
  /// used when the mic or AI is unavailable. Any kept recording is deleted.
  Future<void> startManualNote() async {
    if (_phase == ScribeSessionPhase.processing) return;
    final doctorId = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _stopRecorder(cancel: true);
    await _deleteAudio();
    activeDraftForm?.dispose();
    activeDraftForm = null;
    _draft = ConsultationNote(
      id: const Uuid().v4(),
      doctorId: doctorId,
      patientId: visit.patientId,
      visitId: visit.id,
      consentGiven: _consentAt != null,
      consentAt: _consentAt,
      status: ConsultationNoteStatus.draft,
      createdAt: DateTime.now(),
    );
    _error = null;
    _phase = ScribeSessionPhase.done;
    _notify();
  }

  /// Re-opens [pendingDraft] for review.
  void resumePendingDraft() {
    final pending = _pendingDraft;
    if (pending == null || isBusy) return;
    _draft = pending;
    _phase = ScribeSessionPhase.done;
    _notify();
  }

  // ---- Internals ----

  Future<void> _process() async {
    final doctorId = FirebaseAuth.instance.currentUser?.uid ?? 'local_doctor';

    _error = null;
    _failureKind = null;
    _phase = ScribeSessionPhase.processing;
    processingSeconds.value = 0;
    _processingTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => processingSeconds.value++,
    );
    _notify();

    try {
      // Process locally: uses live transcribed consultation and active draft fields
      final draft = _processingService.processLocally(
        transcript: _accumulatedTranscript,
        noteId: const Uuid().v4(),
        doctorId: doctorId,
        patientId: visit.patientId,
        visitId: visit.id,
        consentAt: _consentAt ?? DateTime.now(),
        existingDraft: activeDraftForm?.toNote(),
      );

      await _repository.saveNote(draft);
      await _deleteAudio();
      if (_disposed) return;
      _draft = draft;
      _phase = ScribeSessionPhase.done;
    } catch (e) {
      debugPrint('[ScribeSession] Local processing error: $e');
      if (_disposed) return;
      _failureKind = ScribeFailureKind.unknown;
      _error =
          'Something went wrong while processing the note locally. Try '
          'again, or write the note manually.';
      _phase = ScribeSessionPhase.failed;
    } finally {
      _processingTicker?.cancel();
      _processingTicker = null;
    }
    _notify();
  }

  void _tick() {
    elapsed.value = _stopwatch.elapsed;
    if (_stopwatch.elapsed >= ScribeProcessingService.maxRecordingDuration) {
      unawaited(finish());
    }
  }

  void _onAmplitude(Amplitude amp) {
    if (_phase != ScribeSessionPhase.recording) return;
    final db = amp.current.isFinite ? amp.current : -160.0;
    _firstDb ??= db;
    if ((db - _firstDb!).abs() > 1) _levelsVaried = true;
    _peakDb = math.max(_peakDb, db);

    // Map roughly -55 dBFS (room noise) … -5 dBFS (close speech) to 0…1.
    final normalised = ((db + 55) / 50).clamp(0.0, 1.0);
    final next = List<double>.of(levels.value)
      ..removeAt(0)
      ..add(normalised);
    levels.value = next;
  }

  Future<void> _stopRecorder({bool cancel = false}) async {
    _ticker?.cancel();
    _ticker = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _transcriptSub?.cancel();
    _transcriptSub = null;
    unawaited(SpeechEngine.instance.stop());
    VoiceBus.openKind.value = null;
    _stopwatch.stop();
    try {
      if (await _recorder.isRecording() || await _recorder.isPaused()) {
        if (cancel) {
          await _recorder.cancel();
        } else {
          await _recorder.stop();
        }
      }
    } catch (e) {
      debugPrint('[ScribeSession] Recorder stop failed: $e');
    }
  }

  Future<String> _newRecordingPath() async {
    // App-support storage is private to CruDoc on every platform — unlike
    // the documents directory, which is the user's Documents on Windows.
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}scribe');
    await dir.create(recursive: true);
    unawaited(_purgeStaleRecordings(dir));
    return '${dir.path}${Platform.pathSeparator}scribe_${const Uuid().v4()}.m4a';
  }

  /// Removes recordings orphaned by a crash or force-quit (§10: unreviewed
  /// audio shouldn't linger on the device).
  Future<void> _purgeStaleRecordings(Directory dir) async {
    try {
      final cutoff = DateTime.now().subtract(_staleRecordingAge);
      await for (final entity in dir.list()) {
        if (entity is File &&
            entity.path.endsWith('.m4a') &&
            (await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } catch (e) {
      debugPrint('[ScribeSession] Stale recording cleanup failed: $e');
    }
  }

  Future<void> _deleteAudio() async {
    final path = _audioPath;
    _audioPath = null;
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[ScribeSession] Could not delete recording: $e');
    }
  }

  void _setError(String message) {
    _error = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _processingTicker?.cancel();
    _amplitudeSub?.cancel();
    _transcriptSub?.cancel();
    _transcriptSub = null;
    unawaited(SpeechEngine.instance.stop());
    VoiceBus.openKind.value = null;
    activeDraftForm?.dispose();
    activeDraftForm = null;
    final path = _audioPath;
    _audioPath = null;
    // Recorder must be released before its file can be deleted on Windows.
    unawaited(() async {
      try {
        if (await _recorder.isRecording() || await _recorder.isPaused()) {
          await _recorder.cancel();
        }
      } catch (_) {}
      await _recorder.dispose();
      if (path != null) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }());
    elapsed.dispose();
    levels.dispose();
    processingSeconds.dispose();
    super.dispose();
  }
}
