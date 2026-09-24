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
      (ref, visitId) => ref
          .watch(consultationNoteRepositoryProvider)
          .watchNotesForVisit(visitId),
    );
