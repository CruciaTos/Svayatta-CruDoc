import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/data/repo/homeopathy_repository.dart';
import 'package:doctor_management_app/features/homeopathy/data/services/homeopathy_local_service.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_session_note.dart';
import 'package:doctor_management_app/features/homeopathy/data/repo/homeopathy_session_notes_repository.dart';
import 'package:doctor_management_app/features/homeopathy/services/homeopathy_session_scribe_service.dart';

final homeopathyLocalServiceProvider = Provider<HomeopathyLocalService>((ref) {
  return HomeopathyLocalService.instance;
});

final homeopathyRepositoryProvider = Provider<HomeopathyRepository>((ref) {
  final localService = ref.watch(homeopathyLocalServiceProvider);
  return HomeopathyRepository(localService: localService);
});

final homeopathyCaseSheetProvider =
    StreamProvider.family<HomeopathyCaseSheet?, String>((ref, patientId) {
      final repo = ref.watch(homeopathyRepositoryProvider);
      return repo.watchCaseSheetForPatient(patientId);
    });

final homeopathySessionNotesRepositoryProvider =
    Provider<HomeopathySessionNotesRepository>((ref) {
      return HomeopathySessionNotesRepository();
    });

final homeopathySessionScribeServiceProvider =
    Provider<HomeopathySessionScribeService>((ref) {
      return HomeopathySessionScribeService();
    });

/// A patient's session history, most recent visit first.
final homeopathySessionHistoryProvider =
    StreamProvider.family<List<HomeopathySessionNote>, String>((
      ref,
      patientId,
    ) {
      final repo = ref.watch(homeopathySessionNotesRepositoryProvider);
      return repo.watchSessionHistory(patientId);
    });
