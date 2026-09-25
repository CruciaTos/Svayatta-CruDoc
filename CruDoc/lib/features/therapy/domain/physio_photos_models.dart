import 'dart:io';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

/// The 8 standard clinical posture, joint, and movement photo slots for Physiotherapy.
enum PhysioPhotoSlot {
  anterior(
    'Anterior Posture',
    'Frontal alignment, shoulder & pelvic levels, knee symmetry',
    'M12 2a4 4 0 1 0 0 8 4 4 0 0 0 0-8zm-6 19v-4a5 5 0 0 1 10 0v4',
  ),
  posterior(
    'Posterior Posture',
    'Spine alignment, scapular winging/symmetry, gluteal folds',
    'M12 2a4 4 0 1 0 0 8 4 4 0 0 0 0-8zm0 10v9m-4-7h8m-3-4h-2',
  ),
  lateralLeft(
    'Lateral Left',
    'Left sagittal plumb line, cervical lordosis, thoracic kyphosis',
    'M9 2a4 4 0 1 1 3 3.8v4.2l3 4v6h-3v-5l-2-3-1 8H7v-9l2-3V2z',
  ),
  lateralRight(
    'Lateral Right',
    'Right sagittal plumb line, head carriage, pelvic tilt',
    'M15 2a4 4 0 1 0-3 3.8v4.2l-3 4v6h3v-5l2-3 1 8h2v-9l-2-3V2z',
  ),
  targetJoint(
    'Target Joint / Region',
    'Close-up of affected joint, edema, incision scar, or atrophy',
    'M12 2a10 10 0 1 0 10 10A10 10 0 0 0 12 2zm0 5a5 5 0 1 1-5 5 5 5 0 0 1 5-5zm0 3a2 2 0 1 0 2 2 2 2 0 0 0-2-2z',
  ),
  activeRom(
    'Active Movement / ROM',
    'Peak range of motion, flexion/abduction end-range test',
    'M12 4V1L8 5l4 4V6a6 6 0 1 1-6 6H4a8 8 0 1 0 8-8z',
  ),
  functional(
    'Functional Assessment',
    'Squat depth, single-leg stance, gait cycle, or functional task',
    'M13 3a2.5 2.5 0 1 0-2.5 2.5A2.5 2.5 0 0 0 13 3zm-2.5 6.5l-3 3.5 1.5 1.5 2.5-3v5.5l-3 4.5 1.7 1.1 3.3-4.9V14l2.5 2.2 1.3-1.5-2.8-2.5-1-2.7z',
  ),
  dynamic(
    'Treatment / Exercise',
    'Taping application, manual technique, or corrective exercise form',
    'M19 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm-7 3a2 2 0 1 1-2 2 2 2 0 0 1 2-2zm4 12H8v-2h8v2zm2-4H6v-2h12v2z',
  );

  final String title;
  final String subtitle;
  final String svgPath;
  const PhysioPhotoSlot(this.title, this.subtitle, this.svgPath);
}

/// In-memory model representing a per-session physiotherapy photo series record.
class PhysioPhotoSet {
  final String id;
  final String patientId;
  final int sessionNumber;
  final String? visitId;
  final String label;
  final DateTime date;
  final String notes;
  final Map<String, String> photos;
  final DentalRecord record;

  const PhysioPhotoSet({
    required this.id,
    required this.patientId,
    required this.sessionNumber,
    this.visitId,
    required this.label,
    required this.date,
    required this.notes,
    required this.photos,
    required this.record,
  });

  factory PhysioPhotoSet.fromRecord(DentalRecord r) {
    final d = r.data;
    final photosMap = <String, String>{};
    if (d['photos'] is Map) {
      (d['photos'] as Map).forEach((k, v) {
        if (k != null && v != null) {
          photosMap[k.toString()] = v.toString();
        }
      });
    }

    final rawSession = d['sessionNumber'];
    final sessionNum = (rawSession is num) ? rawSession.toInt() : 1;

    return PhysioPhotoSet(
      id: r.id,
      patientId: r.patientId,
      sessionNumber: sessionNum,
      visitId: d['visitId'] as String?,
      label: (d['label'] as String?)?.isNotEmpty == true
          ? d['label'] as String
          : 'Session $sessionNum',
      date: r.recordedAt,
      notes: (d['notes'] as String?) ?? '',
      photos: photosMap,
      record: r,
    );
  }

  int get filledCount {
    var count = 0;
    for (final slot in PhysioPhotoSlot.values) {
      final path = photos[slot.name];
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        count++;
      }
    }
    return count;
  }

  String? photoFor(PhysioPhotoSlot slot) {
    final path = photos[slot.name];
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return path;
    }
    return null;
  }
}
