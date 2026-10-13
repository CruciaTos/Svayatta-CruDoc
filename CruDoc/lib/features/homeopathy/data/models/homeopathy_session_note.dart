import 'package:cloud_firestore/cloud_firestore.dart';

/// Direction of the patient's overall symptom picture since the last visit,
/// as reported by the patient at the start of this session.
enum HomeopathySymptomStatus {
  better,
  worse,
  same,
  mixed,
  newProblem,
  unspecified;

  static HomeopathySymptomStatus fromString(String? val) {
    switch (val?.toLowerCase().trim()) {
      case 'better':
      case 'improved':
      case 'improving':
        return HomeopathySymptomStatus.better;
      case 'worse':
      case 'aggravated':
      case 'worsening':
        return HomeopathySymptomStatus.worse;
      case 'same':
      case 'unchanged':
      case 'nochange':
        return HomeopathySymptomStatus.same;
      case 'mixed':
        return HomeopathySymptomStatus.mixed;
      case 'new':
      case 'newproblem':
        return HomeopathySymptomStatus.newProblem;
      default:
        return HomeopathySymptomStatus.unspecified;
    }
  }

  String get label {
    switch (this) {
      case HomeopathySymptomStatus.better:
        return 'Better';
      case HomeopathySymptomStatus.worse:
        return 'Worse';
      case HomeopathySymptomStatus.same:
        return 'No change';
      case HomeopathySymptomStatus.mixed:
        return 'Mixed';
      case HomeopathySymptomStatus.newProblem:
        return 'New problem';
      case HomeopathySymptomStatus.unspecified:
        return 'Not stated';
    }
  }
}

/// How the patient's picture responded to the remedy given at the previous
/// visit. Distinct from [HomeopathySymptomStatus], which is the patient's
/// own overall "better/worse" — this is the clinician's read on the remedy
/// action specifically (it can differ, e.g. an initial aggravation the
/// clinician reads as a good sign).
enum HomeopathyRemedyResponse {
  ameliorated,
  aggravatedThenBetter,
  aggravatedNoRelief,
  noAction,
  tooEarly,
  notApplicable;

  static HomeopathyRemedyResponse fromString(String? val) {
    switch (val?.toLowerCase().trim()) {
      case 'ameliorated':
      case 'improved':
        return HomeopathyRemedyResponse.ameliorated;
      case 'aggravatedthenbetter':
      case 'initialaggravation':
        return HomeopathyRemedyResponse.aggravatedThenBetter;
      case 'aggravatednorelief':
      case 'aggravated':
        return HomeopathyRemedyResponse.aggravatedNoRelief;
      case 'noaction':
      case 'noresponse':
        return HomeopathyRemedyResponse.noAction;
      case 'tooearly':
        return HomeopathyRemedyResponse.tooEarly;
      default:
        return HomeopathyRemedyResponse.notApplicable;
    }
  }

  String get label {
    switch (this) {
      case HomeopathyRemedyResponse.ameliorated:
        return 'Ameliorated';
      case HomeopathyRemedyResponse.aggravatedThenBetter:
        return 'Initial aggravation, then better';
      case HomeopathyRemedyResponse.aggravatedNoRelief:
        return 'Aggravated, no relief';
      case HomeopathyRemedyResponse.noAction:
        return 'No action';
      case HomeopathyRemedyResponse.tooEarly:
        return 'Too early to tell';
      case HomeopathyRemedyResponse.notApplicable:
        return 'Not applicable';
    }
  }
}

/// One dated session/follow-up visit note for a homeopathy patient.
///
/// Unlike [HomeopathyCaseSheet] (one growing record per patient, built up
/// over the whole case), a [HomeopathySessionNote] is created fresh for
/// EVERY visit and never overwritten — the full list of a patient's notes,
/// ordered by [sessionDate], is their session history. This is what lets a
/// doctor scroll back and see what was noted at each past visit, not just
/// the latest state.
///
/// PHI fields ([transcript], [problemToday], [symptomDetails],
/// [oldSymptomsReturned], [newSymptoms], [modalitiesToday],
/// [mentalStateToday], [generalsToday], [heringsLawObservation],
/// [clinicalImpression], [adviceGiven]) are encrypted with [FieldCipher]
/// before leaving the device, exactly like [HomeopathyCaseSheet].
class HomeopathySessionNote {
  final String id;
  final String patientId;
  final String doctorId;

  /// Links this note to the clinic's visit/appointment record, if the
  /// session was recorded against a scheduled visit. May be empty for an
  /// ad-hoc dictation.
  final String visitId;

  final DateTime sessionDate;

  // ---- Subjective: what the patient reports today ----

  /// The problem noted for THIS session — may be the original chief
  /// complaint still being treated, a flare of it, or something new the
  /// patient raises today. Always filled; this is the one field every
  /// session note must have.
  final String problemToday;

  final HomeopathySymptomStatus symptomStatus;

  /// Detail behind [symptomStatus]: what specifically changed, by how
  /// much, since the last visit.
  final String symptomDetails;

  /// Old / past symptoms reappearing — significant in homeopathy as a sign
  /// of cure proceeding by Hering's Law (symptoms returning in reverse
  /// chronological order as the case clears).
  final String oldSymptomsReturned;

  final String newSymptoms;
  final String modalitiesToday;
  final String mentalStateToday;

  /// Appetite, thirst, sleep, energy, stool, urine — as reported today.
  final String generalsToday;

  /// Whether the patient took the remedy as prescribed (dose, frequency,
  /// any missed doses or repetitions beyond what was advised).
  final String complianceNotes;

  /// New illness, infection or injury since the last visit, unrelated to
  /// the case being treated.
  final String intercurrentIllness;

  // ---- Assessment: the clinician's read on today's visit ----

  final HomeopathyRemedyResponse responseToRemedy;

  /// The clinician's read on direction of cure today (Hering's Law: moving
  /// from within outward, from above downward, in reverse order of onset),
  /// stated in their own words.
  final String heringsLawObservation;

  /// The clinician's overall clinical impression / summary for this visit.
  final String clinicalImpression;

  // ---- Plan: what was prescribed and what's next ----

  /// Remedy prescribed at this visit. Empty if the plan was to continue
  /// observing without a new prescription.
  final String remedyGiven;
  final String potency;
  final String repetition;
  final String adviceGiven;
  final DateTime? nextFollowUpDate;

  /// Raw transcript of the dictation this note was extracted from.
  final String transcript;

  /// A note from the model about its own confidence (audio quality,
  /// overlapping speech, anything unclear).
  final String confidenceNote;

  final DateTime createdAt;
  final DateTime? updatedAt;

  const HomeopathySessionNote({
    required this.id,
    required this.patientId,
    required this.doctorId,
    this.visitId = '',
    required this.sessionDate,
    this.problemToday = '',
    this.symptomStatus = HomeopathySymptomStatus.unspecified,
    this.symptomDetails = '',
    this.oldSymptomsReturned = '',
    this.newSymptoms = '',
    this.modalitiesToday = '',
    this.mentalStateToday = '',
    this.generalsToday = '',
    this.complianceNotes = '',
    this.intercurrentIllness = '',
    this.responseToRemedy = HomeopathyRemedyResponse.notApplicable,
    this.heringsLawObservation = '',
    this.clinicalImpression = '',
    this.remedyGiven = '',
    this.potency = '',
    this.repetition = '',
    this.adviceGiven = '',
    this.nextFollowUpDate,
    this.transcript = '',
    this.confidenceNote = '',
    required this.createdAt,
    this.updatedAt,
  });

  factory HomeopathySessionNote.empty({
    required String id,
    required String patientId,
    required String doctorId,
    String visitId = '',
    DateTime? sessionDate,
  }) {
    final now = DateTime.now();
    return HomeopathySessionNote(
      id: id,
      patientId: patientId,
      doctorId: doctorId,
      visitId: visitId,
      sessionDate: sessionDate ?? now,
      createdAt: now,
    );
  }

  bool get isEmpty =>
      problemToday.trim().isEmpty &&
      symptomDetails.trim().isEmpty &&
      oldSymptomsReturned.trim().isEmpty &&
      newSymptoms.trim().isEmpty &&
      modalitiesToday.trim().isEmpty &&
      mentalStateToday.trim().isEmpty &&
      generalsToday.trim().isEmpty &&
      clinicalImpression.trim().isEmpty &&
      remedyGiven.trim().isEmpty &&
      adviceGiven.trim().isEmpty;

  Map<String, dynamic> toMap() => {
    'id': id,
    'patientId': patientId,
    'doctorId': doctorId,
    'visitId': visitId,
    'sessionDate': Timestamp.fromDate(sessionDate),
    'problemToday': problemToday,
    'symptomStatus': symptomStatus.name,
    'symptomDetails': symptomDetails,
    'oldSymptomsReturned': oldSymptomsReturned,
    'newSymptoms': newSymptoms,
    'modalitiesToday': modalitiesToday,
    'mentalStateToday': mentalStateToday,
    'generalsToday': generalsToday,
    'complianceNotes': complianceNotes,
    'intercurrentIllness': intercurrentIllness,
    'responseToRemedy': responseToRemedy.name,
    'heringsLawObservation': heringsLawObservation,
    'clinicalImpression': clinicalImpression,
    'remedyGiven': remedyGiven,
    'potency': potency,
    'repetition': repetition,
    'adviceGiven': adviceGiven,
    'nextFollowUpDate': nextFollowUpDate != null
        ? Timestamp.fromDate(nextFollowUpDate!)
        : null,
    'transcript': transcript,
    'confidenceNote': confidenceNote,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
  };

  /// Local SQLite representation: millisecond timestamps instead of
  /// [Timestamp], same field names so [toMap]/[fromMap] and
  /// [toLocalMap]/[fromLocalMap] stay easy to cross-reference.
  Map<String, dynamic> toLocalMap() => {
    'id': id,
    'patientId': patientId,
    'doctorId': doctorId,
    'visitId': visitId,
    'sessionDate': sessionDate.millisecondsSinceEpoch,
    'problemToday': problemToday,
    'symptomStatus': symptomStatus.name,
    'symptomDetails': symptomDetails,
    'oldSymptomsReturned': oldSymptomsReturned,
    'newSymptoms': newSymptoms,
    'modalitiesToday': modalitiesToday,
    'mentalStateToday': mentalStateToday,
    'generalsToday': generalsToday,
    'complianceNotes': complianceNotes,
    'intercurrentIllness': intercurrentIllness,
    'responseToRemedy': responseToRemedy.name,
    'heringsLawObservation': heringsLawObservation,
    'clinicalImpression': clinicalImpression,
    'remedyGiven': remedyGiven,
    'potency': potency,
    'repetition': repetition,
    'adviceGiven': adviceGiven,
    'nextFollowUpDate': nextFollowUpDate?.millisecondsSinceEpoch,
    'transcript': transcript,
    'confidenceNote': confidenceNote,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt?.millisecondsSinceEpoch,
  };

  factory HomeopathySessionNote.fromMap(
    Map<String, dynamic> map, {
    String? id,
  }) {
    return HomeopathySessionNote(
      id: id ?? (map['id'] as String? ?? ''),
      patientId: map['patientId'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      visitId: map['visitId'] as String? ?? '',
      sessionDate: _parseDate(map['sessionDate']) ?? DateTime.now(),
      problemToday: map['problemToday'] as String? ?? '',
      symptomStatus: HomeopathySymptomStatus.fromString(
        map['symptomStatus'] as String?,
      ),
      symptomDetails: map['symptomDetails'] as String? ?? '',
      oldSymptomsReturned: map['oldSymptomsReturned'] as String? ?? '',
      newSymptoms: map['newSymptoms'] as String? ?? '',
      modalitiesToday: map['modalitiesToday'] as String? ?? '',
      mentalStateToday: map['mentalStateToday'] as String? ?? '',
      generalsToday: map['generalsToday'] as String? ?? '',
      complianceNotes: map['complianceNotes'] as String? ?? '',
      intercurrentIllness: map['intercurrentIllness'] as String? ?? '',
      responseToRemedy: HomeopathyRemedyResponse.fromString(
        map['responseToRemedy'] as String?,
      ),
      heringsLawObservation: map['heringsLawObservation'] as String? ?? '',
      clinicalImpression: map['clinicalImpression'] as String? ?? '',
      remedyGiven: map['remedyGiven'] as String? ?? '',
      potency: map['potency'] as String? ?? '',
      repetition: map['repetition'] as String? ?? '',
      adviceGiven: map['adviceGiven'] as String? ?? '',
      nextFollowUpDate: _parseDate(map['nextFollowUpDate']),
      transcript: map['transcript'] as String? ?? '',
      confidenceNote: map['confidenceNote'] as String? ?? '',
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  factory HomeopathySessionNote.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return HomeopathySessionNote.fromMap(doc.data() ?? const {}, id: doc.id);
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  HomeopathySessionNote copyWith({
    String? doctorId,
    String? visitId,
    DateTime? sessionDate,
    String? problemToday,
    HomeopathySymptomStatus? symptomStatus,
    String? symptomDetails,
    String? oldSymptomsReturned,
    String? newSymptoms,
    String? modalitiesToday,
    String? mentalStateToday,
    String? generalsToday,
    String? complianceNotes,
    String? intercurrentIllness,
    HomeopathyRemedyResponse? responseToRemedy,
    String? heringsLawObservation,
    String? clinicalImpression,
    String? remedyGiven,
    String? potency,
    String? repetition,
    String? adviceGiven,
    DateTime? nextFollowUpDate,
    bool clearNextFollowUpDate = false,
    String? transcript,
    String? confidenceNote,
    DateTime? updatedAt,
  }) {
    return HomeopathySessionNote(
      id: id,
      patientId: patientId,
      doctorId: doctorId ?? this.doctorId,
      visitId: visitId ?? this.visitId,
      sessionDate: sessionDate ?? this.sessionDate,
      problemToday: problemToday ?? this.problemToday,
      symptomStatus: symptomStatus ?? this.symptomStatus,
      symptomDetails: symptomDetails ?? this.symptomDetails,
      oldSymptomsReturned: oldSymptomsReturned ?? this.oldSymptomsReturned,
      newSymptoms: newSymptoms ?? this.newSymptoms,
      modalitiesToday: modalitiesToday ?? this.modalitiesToday,
      mentalStateToday: mentalStateToday ?? this.mentalStateToday,
      generalsToday: generalsToday ?? this.generalsToday,
      complianceNotes: complianceNotes ?? this.complianceNotes,
      intercurrentIllness: intercurrentIllness ?? this.intercurrentIllness,
      responseToRemedy: responseToRemedy ?? this.responseToRemedy,
      heringsLawObservation:
          heringsLawObservation ?? this.heringsLawObservation,
      clinicalImpression: clinicalImpression ?? this.clinicalImpression,
      remedyGiven: remedyGiven ?? this.remedyGiven,
      potency: potency ?? this.potency,
      repetition: repetition ?? this.repetition,
      adviceGiven: adviceGiven ?? this.adviceGiven,
      nextFollowUpDate: clearNextFollowUpDate
          ? null
          : (nextFollowUpDate ?? this.nextFollowUpDate),
      transcript: transcript ?? this.transcript,
      confidenceNote: confidenceNote ?? this.confidenceNote,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
