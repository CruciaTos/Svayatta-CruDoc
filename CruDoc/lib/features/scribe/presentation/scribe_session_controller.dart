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
import 'package:doctor_management_app/features/scribe/services/scribe_processing_service.dart';
import 'package:doctor_management_app/features/voice/presentation/voice_dialog_hook.dart';
import 'package:doctor_management_app/features/voice/services/speech_engine.dart';

/// Where a scribe session is in its lifecycle.
enum ScribeSessionPhase {
  /// Consent + start screen.
  ready,
  recording,
  paused,

  /// The session notes are being written.
  processing,

  /// Writing the notes failed; the conversation is kept so the doctor can
  /// retry or save the transcript.
  failed,

  /// [ScribeSessionController.note] has been saved to the patient's record.
  done,
}

/// Listens to a consultation and turns it into a session note. Shared by
/// the mobile sheet and the desktop scribe screen, so both behave
/// identically and only differ in layout.
///
/// While the doctor and the patient talk, the conversation is transcribed
/// on the device ([transcript]). Finishing hands that transcript to
/// [ScribeProcessingService] to write the session notes, which are saved
/// straight into the patient's session history ([note]).
class ScribeSessionController extends ChangeNotifier {
  ScribeSessionController({
    required this.visit,
    required ScribeProcessingService processingService,
    required ConsultationNoteRepository repository,
    this.specialty = SessionSpecialty.none,
    this.queueEntryId,
    AudioRecorder? recorder,
  }) : _processingService = processingService,
       _repository = repository,
       _recorder = recorder ?? AudioRecorder();

  /// Number of bars the live waveform shows.
  static const levelCount = 48;

  /// Mono 16 kHz AAC at a speech bitrate. The recording only drives the
  /// level meter and the silence check; it is deleted as soon as recording
  /// stops and never leaves the device.
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

  /// [SessionSpecialty] stamped on the note this session produces.
  final String specialty;

  /// The queue token being seen, when the session was started from the queue.
  final String? queueEntryId;

  final ScribeProcessingService _processingService;
  final ConsultationNoteRepository _repository;
  final AudioRecorder _recorder;

  /// One note per session, so a retry never saves a second copy.
  final String _noteId = const Uuid().v4();

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
      transcript.value.trim().isNotEmpty &&
      (_failureKind?.isRetryable ?? false);

  /// Notes couldn't be written, but there is a transcript worth keeping.
  bool get canSaveTranscript =>
      _phase == ScribeSessionPhase.failed &&
      transcript.value.trim().isNotEmpty;

  ConsultationNote? _note;

  /// The session note, once it has been written and saved to the patient's
  /// record.
  ConsultationNote? get note => _note;

  /// Elapsed recording time (excludes pauses). Separate notifier so the
  /// timer can tick without rebuilding the whole screen.
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  /// Recent normalised mic levels (0–1), newest last.
  final ValueNotifier<List<double>> levels = ValueNotifier(
    List<double>.filled(levelCount, 0),
  );

  /// Seconds spent processing so far — drives the progress copy.
  final ValueNotifier<int> processingSeconds = ValueNotifier(0);

  /// The conversation as heard so far: the sentences transcribed in full,
  /// then the one being spoken.
  final ValueNotifier<String> transcript = ValueNotifier('');

  bool get isBusy =>
      _phase == ScribeSessionPhase.recording ||
      _phase == ScribeSessionPhase.paused ||
      _phase == ScribeSessionPhase.processing;

  /// True when closing now would lose the conversation.
  bool get hasUnsavedConversation =>
      isBusy || _phase == ScribeSessionPhase.failed;

  /// Sentences already transcribed in full, and the one being spoken.
  String _heard = '';
  String _speaking = '';
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
  bool _saving = false;
  bool _disposed = false;

  // ---- Setup ----

  void setConsent(bool value) {
    if (_phase != ScribeSessionPhase.ready) return;
    _consentGiven = value;
    _error = null;
    _notify();
  }

  // ---- Recording ----

  /// Records the patient's consent and starts recording in one step — the
  /// single tap the consultation launcher asks for.
  Future<void> consentAndStart() async {
    setConsent(true);
    await start();
  }

  Future<void> start() async {
    if (!_consentGiven || _phase != ScribeSessionPhase.ready) return;
    _error = null;
    _heard = '';
    _speaking = '';
    transcript.value = '';

    // Mark openKind as scribe so VoiceController treats this as dedicated consultation session
    VoiceBus.openKind.value = 'scribe';

    // Dictation: the conversation is cut into sentences at pauses, each
    // transcribed once in full, and push-to-talk can't stop it.
    try {
      _transcriptSub?.cancel();
      _transcriptSub = SpeechEngine.instance.transcripts.listen(
        _onLiveTranscript,
      );
      await SpeechEngine.instance.startDictation();
    } catch (e) {
      debugPrint('[ScribeSession] Live transcription warning: $e');
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
    // Commands spoken with the talk key aren't part of the consultation.
    if (!t.dictation) return;
    // A pause still delivers the sentence that was being spoken.
    if (_phase != ScribeSessionPhase.recording &&
        _phase != ScribeSessionPhase.paused) {
      return;
    }
    final text = t.text.trim();
    if (t.isFinal) {
      // A finished sentence: kept as heard, never re-merged.
      if (text.isNotEmpty) _heard = '$_heard $text'.trim();
      _speaking = '';
    } else {
      // The sentence being spoken: each pass replaces the last.
      _speaking = text;
    }
    transcript.value = _speaking.isEmpty
        ? _heard
        : '$_heard $_speaking'.trim();
  }

  Future<void> pause() async {
    if (_phase != ScribeSessionPhase.recording) return;
    try {
      await _recorder.pause();
    } catch (e) {
      debugPrint('[ScribeSession] Pause failed: $e');
    }
    unawaited(SpeechEngine.instance.stopDictation());
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
    unawaited(SpeechEngine.instance.startDictation());
    _stopwatch.start();
    _phase = ScribeSessionPhase.recording;
    _notify();
  }

  /// Stops recording and writes the session notes. On success the phase
  /// becomes [ScribeSessionPhase.done] with [note] saved to the patient's
  /// record.
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
    await _deleteAudio();

    if (duration < ScribeProcessingService.minRecordingDuration) {
      _resetConversation();
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
      _resetConversation();
      _phase = ScribeSessionPhase.ready;
      _setError(
        'No speech was picked up. Check that the right microphone '
        'is selected and try again.',
      );
      return;
    }

    await _process();
  }

  /// Tries writing the notes again after a failure.
  Future<void> retry() async {
    if (!canRetry) return;
    await _process();
  }

  /// Saves the transcript as the session note when the notes couldn't be
  /// written, so the consultation isn't lost.
  Future<void> saveTranscript() async {
    if (!canSaveTranscript || _saving) return;
    _saving = true;
    try {
      final text = ScribeProcessingService.cleanTranscript(transcript.value);
      final saved = await _repository.saveSessionNote(
        _newNote().copyWith(
          transcript: text,
          notes: text,
          chiefComplaint: 'Consultation transcript',
          confidenceNote:
              "The AI couldn't write notes for this session, so the "
              'transcript of the conversation was saved instead.',
        ),
      );
      if (_disposed) return;
      _note = saved;
      _error = null;
      _phase = ScribeSessionPhase.done;
    } catch (e) {
      debugPrint('[ScribeSession] Could not save the transcript: $e');
      if (_disposed) return;
      _error = "Couldn't save the transcript: $e";
    } finally {
      _saving = false;
    }
    _notify();
  }

  /// Stops and throws away the current conversation without writing notes.
  Future<void> discardRecording() async {
    if (_phase == ScribeSessionPhase.processing) return;
    await _stopRecorder(cancel: true);
    await _deleteAudio();
    _resetConversation();
    _phase = ScribeSessionPhase.ready;
    _error = null;
    _failureKind = null;
    _notify();
  }

  // ---- Internals ----

  Future<void> _process() async {
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
      final written = await _processingService.writeSessionNote(
        session: _newNote(),
        transcript: transcript.value,
      );
      // Saved even if the screen was closed meanwhile: the doctor was told
      // the note would still reach the patient's record.
      final saved = await _repository.saveSessionNote(written);
      if (_disposed) return;
      _note = saved;
      _phase = ScribeSessionPhase.done;
    } on ScribeProcessingException catch (e) {
      if (_disposed) return;
      _failureKind = e.kind;
      _error = e.message;
      _phase = ScribeSessionPhase.failed;
    } catch (e) {
      debugPrint('[ScribeSession] Could not save the session note: $e');
      if (_disposed) return;
      _failureKind = ScribeFailureKind.unknown;
      _error = "The session note couldn't be saved. Try again.";
      _phase = ScribeSessionPhase.failed;
    } finally {
      _processingTicker?.cancel();
      _processingTicker = null;
    }
    _notify();
  }

  /// A blank note for this session, stamped with who, when and consent.
  ConsultationNote _newNote() {
    final doctorId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return ConsultationNote(
      id: _noteId,
      doctorId: doctorId,
      patientId: visit.patientId,
      visitId: visit.id,
      specialty: specialty,
      queueEntryId: queueEntryId,
      authorUid: doctorId,
      consentGiven: _consentAt != null,
      consentAt: _consentAt,
      createdAt: _consentAt ?? DateTime.now(),
    );
  }

  void _resetConversation() {
    _heard = '';
    _speaking = '';
    transcript.value = '';
    elapsed.value = Duration.zero;
    levels.value = List<double>.filled(levelCount, 0);
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
    // The sentence being spoken is transcribed before the transcript
    // closes, so the end of the consultation isn't lost.
    await SpeechEngine.instance.stopDictation(keepLast: !cancel);
    await _transcriptSub?.cancel();
    _transcriptSub = null;
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

  /// Removes recordings orphaned by a crash or force-quit, so consultation
  /// audio never lingers on the device.
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
    unawaited(SpeechEngine.instance.stopDictation(keepLast: false));
    VoiceBus.openKind.value = null;
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
    transcript.dispose();
    super.dispose();
  }
}
