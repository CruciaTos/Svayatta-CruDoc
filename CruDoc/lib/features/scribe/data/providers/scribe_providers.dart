import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/repo/consultation_note_repository.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_processing_service.dart';

// ---- Repository provider ----

final consultationNoteRepositoryProvider = Provider<ConsultationNoteRepository>(
  (ref) => ConsultationNoteRepository(),
);

// ---- Processing service provider ----

final scribeProcessingServiceProvider = Provider<ScribeProcessingService>(
  (ref) => ScribeProcessingService(),
);

// ---- Per-visit notes stream ----

/// Streams all consultation notes for a given visit (newest first).
final notesForVisitProvider =
    StreamProvider.family<List<ConsultationNote>, String>(
  (ref, visitId) =>
      ref.watch(consultationNoteRepositoryProvider).watchNotesForVisit(visitId),
);

// ---- Scribe recording state ----

/// Tracks the current recording state for the scribe UI.
enum ScribeState {
  /// No recording in progress.
  idle,

  /// Requesting/waiting for mic permission.
  requestingPermission,

  /// Doctor agreed to consent, mic is actively recording.
  recording,

  /// Recording stopped; audio is being uploaded and processed by Gemini.
  processing,

  /// AI returned its draft; waiting for doctor to review.
  draftReady,

  /// An error occurred (permission denied, AI failure, etc.).
  error,
}

class ScribeStateNotifier extends Notifier<ScribeState> {
  @override
  ScribeState build() => ScribeState.idle;

  void setRecording() => state = ScribeState.recording;
  void setProcessing() => state = ScribeState.processing;
  void setDraftReady() => state = ScribeState.draftReady;
  void setError() => state = ScribeState.error;
  void reset() => state = ScribeState.idle;
}

final scribeStateProvider =
    NotifierProvider.autoDispose<ScribeStateNotifier, ScribeState>(
  ScribeStateNotifier.new,
);

// ---- Current draft note ----

/// Holds the current draft [ConsultationNote] while the doctor is in the
/// recording → review flow. Cleared when the sheet is dismissed.
class _CurrentDraftNotifier extends Notifier<ConsultationNote?> {
  @override
  ConsultationNote? build() => null;

  void set(ConsultationNote note) => state = note;
  void clear() => state = null;
}

final currentDraftNoteProvider =
    NotifierProvider.autoDispose<_CurrentDraftNotifier, ConsultationNote?>(
  _CurrentDraftNotifier.new,
);
