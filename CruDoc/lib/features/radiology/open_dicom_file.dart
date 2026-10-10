import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_cloud_sync.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_import.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_screen.dart';

/// The study `extras` key naming the Files entry a study was made from.
const String kRadSourceFileKey = 'sourceFileId';

/// Opens a DICOM file from Files in CruDoc's X-ray viewer.
///
/// The viewer works on studies, so the first open turns the file into one
/// of the patient's X-rays & scans (the file stays in Files as well).
/// Later opens find that study again by the file's id rather than making
/// another. Returns false when the file holds no image CruDoc can read,
/// so the caller can fall back to the computer's own app.
Future<bool> openDicomFileInViewer(
  BuildContext context, {
  required PatientFile file,
  required File local,
  required String patientName,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final navigator = Navigator.of(context, rootNavigator: true);
  final ctrl = container.read(radiologyProvider);

  RadStudy? study;
  for (final s in await container.read(radStudiesProvider.future)) {
    if (s.extras[kRadSourceFileKey] == file.id) {
      study = s;
      break;
    }
  }
  study ??= await _studyFromFile(ctrl, file, local, patientName);
  if (study == null) return false;

  unawaited(ctrl.openedStudy(study));
  await navigator.push(
    radRoute<void>(RadViewerScreen(studyId: study.id, initialStudy: study)),
  );
  return true;
}

/// Reads the file's DICOM tags and pixels into a new study for the file's
/// patient, the same way an import does, minus the referral form: the
/// patient is already known and nothing else is required.
Future<RadStudy?> _studyFromFile(
  RadiologyController ctrl,
  PatientFile file,
  File local,
  String patientName,
) async {
  final temp = await getTemporaryDirectory();
  final work = p.join(
    temp.path,
    'crudoc_file_${DateTime.now().millisecondsSinceEpoch}',
  );
  try {
    final scan = await scanForImport([local.path], tempDir: work);
    if (scan.isEmpty) return null;
    final g = scan.groups.first;

    final id = radId('study_');
    final dir = await ctrl.studyDir(id);
    final images = await copyIntoStudy(g, dir.path);
    final now = DateTime.now();
    final name = patientName.isNotEmpty ? patientName : g.patientName;
    final study = RadStudy(
      id: id,
      patientId: file.patientId,
      patientName: name,
      patientSex: g.patientSex,
      patientDob: g.patientDob,
      patientExternalId: g.patientExternalId,
      modality: g.modality,
      studyDate: g.studyDate ?? file.createdAt,
      receivedAt: now,
      description: g.description.isNotEmpty ? g.description : file.name,
      dueAt: await ctrl.dueFor(RadPriority.routine, now),
      images: images,
      dose: g.dose,
      studyUid: g.studyUid,
      accession: g.accession,
      institution: g.institution,
      equipment: g.equipment,
      bodyPart: g.bodyPart,
      extras: {kRadSourceFileKey: file.id},
      createdAt: now,
      updatedAt: now,
    );
    await ctrl.saveStudy(
      study,
      auditAction: 'Imported from Files',
      detail: '$name · ${g.modality.short} · ${RadFormat.images(images.length)}',
    );
    await RadiologyCloudSync.enqueueStudyImages(
      ctrl: ctrl,
      study: study,
      studyDir: dir.path,
    );
    return study;
  } finally {
    try {
      await Directory(work).delete(recursive: true);
    } catch (_) {}
  }
}
