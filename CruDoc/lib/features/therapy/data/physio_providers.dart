import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

const _perPatientPhysioKinds = [
  RecKind.physioPhotoSet,
  RecKind.muscleChart,
  RecKind.physioHep,
  RecKind.physioGoal,
  RecKind.physioScreening,
  RecKind.physioProgress,
  RecKind.physioRom,
  RecKind.physioPackage,
  RecKind.physioTestResult,
  RecKind.physioScaleScore,
  RecKind.physioModality,
];

/// True when [patientId] has at least one saved physiotherapy record.
final patientHasPhysioProvider = Provider.autoDispose.family<bool, String>((
  ref,
  patientId,
) {
  for (final kind in _perPatientPhysioKinds) {
    final list = ref
        .watch(patientRecordsProvider((patientId: patientId, kind: kind)))
        .value;
    if (list != null && list.isNotEmpty) return true;
  }
  return false;
});
