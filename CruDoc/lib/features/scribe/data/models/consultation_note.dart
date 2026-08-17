import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Status lifecycle of a consultation note produced by the AI Scribe.
enum ConsultationNoteStatus {
  /// AI has produced a draft; doctor has not yet reviewed it.
  draft,

  /// Doctor reviewed and confirmed the draft into the patient record.
  confirmed,

  /// Doctor dismissed the draft; no patient-record changes were made.
  discarded;

  String get value => name;

  static ConsultationNoteStatus fromValue(String? raw) {
    return ConsultationNoteStatus.values.firstWhere(
      (s) => s.value == raw,
      orElse: () => ConsultationNoteStatus.draft,
    );
  }
}

/// A medicine mentioned during a consultation, extracted by the AI.
///
/// Stored as JSON inside the `medicines` column/field — same approach
/// as [Patient.diagnosis] using JSON-in-TEXT to avoid a schema change.
class NotedMedicine {
  final String name;
  final String dosage;
  final String instructions;

  const NotedMedicine({
    required this.name,
    this.dosage = '',
    this.instructions = '',
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'dosage': dosage,
    'instructions': instructions,
  };

  factory NotedMedicine.fromMap(Map<String, dynamic> map) => NotedMedicine(
    name: map['name'] as String? ?? '',
    dosage: map['dosage'] as String? ?? '',
    instructions: map['instructions'] as String? ?? '',
  );

  static String listToStored(List<NotedMedicine> medicines) =>
      jsonEncode(medicines.map((m) => m.toMap()).toList());

  static List<NotedMedicine> listFromStored(Object? value) {
    if (value == null || (value is String && value.isEmpty)) {
      return const [];
    }
    try {
      final decoded = jsonDecode(value as String);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(NotedMedicine.fromMap)
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}

/// Clinical consultation note produced by the AI Scribe.
///
/// Created as [ConsultationNoteStatus.draft] immediately after the
/// AI returns its structured output. Only promoted to
/// [ConsultationNoteStatus.confirmed] when the doctor explicitly taps
/// Confirm — never auto-saved into the patient record.
///
/// PHI fields ([transcript], [chiefComplaint], [symptoms],
/// [diagnosisSuggestions], [advice], [medicines]) are encrypted with
/// [FieldCipher] before leaving the device, exactly like
/// [Patient.notes] and [Patient.diagnosis].
class ConsultationNote {
  final String id;
  final String doctorId;
  final String patientId;
  final String visitId;

  /// Raw transcript text as returned by the model. May be the full
  /// transcript or a summary — depends on audio length and the model's
  /// output for that call.
  final String transcript;

  final String chiefComplaint;
  final List<String> symptoms;
  final List<String> diagnosisSuggestions;
  final List<NotedMedicine> medicines;
  final String advice;

  /// Follow-up date suggested by the doctor during the consultation,
  /// if the model extracted one.
  final DateTime? followUpDate;

  /// Vitals mentioned during the consultation (bp / temp / pulse).
  /// Only populated if the doctor actually stated them during the visit.
  final Map<String, String?> vitals;

  /// A brief note from the model about its own confidence in the
  /// transcription (e.g. audio quality issues, overlapping speech).
  final String confidenceNote;

  /// Whether the patient gave consent before the recording started.
  /// Always true by the time this note is created (the UI gate prevents
  /// recording without consent) — stored so the consent event is auditable.
  final bool consentGiven;
  final DateTime? consentAt;

  /// Firebase Storage path for the raw audio file, or null once the
  /// audio has been deleted per the retention policy (after confirm/discard).
  final String? audioStoragePath;

  final ConsultationNoteStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final DateTime? updatedAt;

  const ConsultationNote({
    required this.id,
    required this.doctorId,
    required this.patientId,
    required this.visitId,
    this.transcript = '',
    this.chiefComplaint = '',
    this.symptoms = const [],
    this.diagnosisSuggestions = const [],
    this.medicines = const [],
    this.advice = '',
    this.followUpDate,
    this.vitals = const {},
    this.confidenceNote = '',
    this.consentGiven = true,
    this.consentAt,
    this.audioStoragePath,
    this.status = ConsultationNoteStatus.draft,
    required this.createdAt,
    this.confirmedAt,
    this.updatedAt,
  });

  /// Serializes this note to a Firestore-writable map.
  /// Callers in [ConsultationNoteRepository] must run PHI fields through
  /// [FieldCipher] before writing to Firestore — they are stored plain here.
  Map<String, dynamic> toMap() {
    return {
      'doctorId': doctorId,
      'patientId': patientId,
      'visitId': visitId,
      'transcript': transcript,
      'chiefComplaint': chiefComplaint,
      'symptoms': jsonEncode(symptoms),
      'diagnosisSuggestions': jsonEncode(diagnosisSuggestions),
      'medicines': NotedMedicine.listToStored(medicines),
      'advice': advice,
      'followUpDate':
          followUpDate != null ? Timestamp.fromDate(followUpDate!) : null,
      'vitals': jsonEncode(vitals),
      'confidenceNote': confidenceNote,
      'consentGiven': consentGiven,
      'consentAt': consentAt != null ? Timestamp.fromDate(consentAt!) : null,
      'audioStoragePath': audioStoragePath,
      'status': status.value,
      'createdAt': Timestamp.fromDate(createdAt),
      'confirmedAt':
          confirmedAt != null ? Timestamp.fromDate(confirmedAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  /// Serializes this note for local SQLite storage (integers for timestamps,
  /// JSON strings for lists/maps).
  Map<String, dynamic> toLocalMap() {
    return {
      'id': id,
      'doctorId': doctorId,
      'patientId': patientId,
      'visitId': visitId,
      'transcript': transcript,
      'chiefComplaint': chiefComplaint,
      'symptoms': jsonEncode(symptoms),
      'diagnosisSuggestions': jsonEncode(diagnosisSuggestions),
      'medicines': NotedMedicine.listToStored(medicines),
      'advice': advice,
      'followUpDate': followUpDate?.millisecondsSinceEpoch,
      'vitals': jsonEncode(vitals),
      'confidenceNote': confidenceNote,
      'consentGiven': consentGiven ? 1 : 0,
      'consentAt': consentAt?.millisecondsSinceEpoch,
      'audioStoragePath': audioStoragePath,
      'status': status.value,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'confirmedAt': confirmedAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
    };
  }

  factory ConsultationNote.fromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    return ConsultationNote(
      id: id,
      doctorId: map['doctorId'] as String? ?? '',
      patientId: map['patientId'] as String? ?? '',
      visitId: map['visitId'] as String? ?? '',
      transcript: map['transcript'] as String? ?? '',
      chiefComplaint: map['chiefComplaint'] as String? ?? '',
      symptoms: _parseStringList(map['symptoms']),
      diagnosisSuggestions: _parseStringList(map['diagnosisSuggestions']),
      medicines: NotedMedicine.listFromStored(map['medicines']),
      advice: map['advice'] as String? ?? '',
      followUpDate: _parseNullableDate(map['followUpDate']),
      vitals: _parseVitals(map['vitals']),
      confidenceNote: map['confidenceNote'] as String? ?? '',
      consentGiven: (map['consentGiven'] is bool)
          ? map['consentGiven'] as bool
          : (map['consentGiven'] as int? ?? 0) == 1,
      consentAt: _parseNullableDate(map['consentAt']),
      audioStoragePath: map['audioStoragePath'] as String?,
      status: ConsultationNoteStatus.fromValue(map['status'] as String?),
      createdAt: _parseDate(map['createdAt']),
      confirmedAt: _parseNullableDate(map['confirmedAt']),
      updatedAt: _parseNullableDate(map['updatedAt']),
    );
  }

  factory ConsultationNote.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ConsultationNote.fromMap(data, id: doc.id);
  }

  ConsultationNote copyWith({
    String? transcript,
    String? chiefComplaint,
    List<String>? symptoms,
    List<String>? diagnosisSuggestions,
    List<NotedMedicine>? medicines,
    String? advice,
    DateTime? followUpDate,
    bool clearFollowUpDate = false,
    Map<String, String?>? vitals,
    String? confidenceNote,
    String? audioStoragePath,
    bool clearAudioStoragePath = false,
    ConsultationNoteStatus? status,
    DateTime? confirmedAt,
    DateTime? updatedAt,
  }) {
    return ConsultationNote(
      id: id,
      doctorId: doctorId,
      patientId: patientId,
      visitId: visitId,
      transcript: transcript ?? this.transcript,
      chiefComplaint: chiefComplaint ?? this.chiefComplaint,
      symptoms: symptoms ?? this.symptoms,
      diagnosisSuggestions: diagnosisSuggestions ?? this.diagnosisSuggestions,
      medicines: medicines ?? this.medicines,
      advice: advice ?? this.advice,
      followUpDate: clearFollowUpDate ? null : (followUpDate ?? this.followUpDate),
      vitals: vitals ?? this.vitals,
      confidenceNote: confidenceNote ?? this.confidenceNote,
      consentGiven: consentGiven,
      consentAt: consentAt,
      audioStoragePath: clearAudioStoragePath
          ? null
          : (audioStoragePath ?? this.audioStoragePath),
      status: status ?? this.status,
      createdAt: createdAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ---- Parsing helpers ----

  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  static List<String> _parseStringList(Object? value) {
    if (value == null) return const [];
    if (value is List) {
      return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  static Map<String, String?> _parseVitals(Object? value) {
    if (value == null) return const {};
    try {
      final decoded = jsonDecode(value as String);
      if (decoded is Map) {
        return decoded.map(
          (k, v) => MapEntry(k.toString(), v?.toString()),
        );
      }
    } catch (_) {}
    return const {};
  }
}
