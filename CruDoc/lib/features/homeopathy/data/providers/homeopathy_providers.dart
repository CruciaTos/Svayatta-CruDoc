import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/data/repo/homeopathy_repository.dart';
import 'package:doctor_management_app/features/homeopathy/data/services/homeopathy_local_service.dart';

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
