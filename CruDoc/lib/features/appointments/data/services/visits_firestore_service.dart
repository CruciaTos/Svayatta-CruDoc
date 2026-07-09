import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';

/// Talks directly to the `visits` Firestore collection.
///
/// Like [PatientFirestoreService], this is the only layer in the feature
/// that knows about `cloud_firestore` types — the repository and UI work
/// with plain [Visit] objects. This service does not enforce business
/// rules (patient existence, overlap limits, status transitions, etc.)
/// — that lives one layer up in `VisitRepository`, which is the layer
/// the UI should actually call. It does, however, always stamp
/// `createdAt`/`updatedAt` itself, so those timestamps are maintained
/// automatically rather than depending on every caller remembering to
/// set them.
class VisitFirestoreService {
  VisitFirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _visitsRef =>
      _firestore.collection('visits');

  /// Creates a new visit document and returns the generated document id.
  ///
  /// The id is generated client-side (like [PatientFirestoreService]),
  /// so a retried call can safely reuse the same id instead of risking
  /// a duplicate visit. `createdAt`/`updatedAt` on [visit] are ignored
  /// in favor of the current time, so they're always correct regardless
  /// of what the caller passed in.
  Future<String> createVisit(Visit visit) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    final data = visit.copyWith(createdAt: now, updatedAt: now).toMap();
    await _visitsRef.doc(id).set(data);
    return id;
  }

  /// Updates an existing visit document with the given fields.
  ///
  /// `updatedAt` is always stamped with the current time here,
  /// overriding anything the caller passed in — timestamps in
  /// [data] other than that are written as-is, with any raw [DateTime]
  /// values converted to Firestore [Timestamp]s automatically so
  /// callers above this layer never need to import `cloud_firestore`.
  Future<void> updateVisit(String visitId, Map<String, dynamic> data) async {
    final sanitized = <String, dynamic>{
      for (final entry in data.entries)
        entry.key: entry.value is DateTime
            ? Timestamp.fromDate(entry.value as DateTime)
            : entry.value,
    };
    await _visitsRef.doc(visitId).update({
      ...sanitized,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Fetches a single visit by id. Returns null if it doesn't exist.
  Future<Visit?> getVisit(String visitId) async {
    final snapshot = await _visitsRef.doc(visitId).get();
    if (!snapshot.exists) return null;
    return Visit.fromFirestore(snapshot);
  }

  /// Streams active (not soft-deleted, status == scheduled) visits from
  /// [from] onward, ordered by start time ascending. Defaults [from] to
  /// "now" so past visits fall off the list automatically.
  ///
  /// Requires a composite index on
  /// `(isDeleted ASC, status ASC, scheduledStart ASC)`. Firestore prints
  /// a console link to create it the first time this query runs against
  /// real data.
  Stream<List<Visit>> watchUpcomingVisits({DateTime? from}) {
    final start = from ?? DateTime.now();
    return _visitsRef
        .where('isDeleted', isEqualTo: false)
        .where('status', isEqualTo: VisitStatus.scheduled.value)
        .where('scheduledStart',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .orderBy('scheduledStart')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Visit.fromFirestore).toList());
  }

  /// Streams every visit belonging to [patientId], most recent first —
  /// the "session history" for a single patient. Soft-deleted visits
  /// are excluded unless [includeDeleted] is true.
  ///
  /// Requires a composite index on
  /// `(patientId ASC, isDeleted ASC, scheduledStart DESC)`.
  Stream<List<Visit>> watchVisitsForPatient(
    String patientId, {
    bool includeDeleted = false,
  }) {
    Query<Map<String, dynamic>> query =
        _visitsRef.where('patientId', isEqualTo: patientId);
    if (!includeDeleted) {
      query = query.where('isDeleted', isEqualTo: false);
    }
    return query
        .orderBy('scheduledStart', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Visit.fromFirestore).toList());
  }

  /// Finds active (not deleted, status == scheduled) visits whose time
  /// range could overlap `[start, end)`. Backs both the pre-save
  /// overlap warning and the hard max-overlap enforcement in
  /// `VisitRepository`.
  ///
  /// This only needs a single-field range query on `scheduledStart`
  /// (Firestore auto-indexes single fields), so — unlike the two watch*
  /// methods above — it needs no manual composite index.
  Future<List<Visit>> findOverlapping({
    required DateTime start,
    required DateTime end,
    String? excludeVisitId,
  }) async {
    // Any visit that could overlap [start, end) must have started
    // before `end`. The lower bound looks back by the maximum allowed
    // visit duration so a long visit that started earlier, but is
    // still running when the new one begins, isn't missed.
    final lookbackStart =
        start.subtract(const Duration(minutes: kMaxVisitDurationMinutes));

    final snapshot = await _visitsRef
        .where('scheduledStart',
            isGreaterThanOrEqualTo: Timestamp.fromDate(lookbackStart))
        .where('scheduledStart', isLessThan: Timestamp.fromDate(end))
        .get();

    final overlapping = snapshot.docs
        .map(Visit.fromFirestore)
        .where((visit) {
          if (visit.id == excludeVisitId) return false;
          if (visit.isDeleted) return false;
          if (visit.status != VisitStatus.scheduled) return false;
          return visit.scheduledStart.isBefore(end) &&
              start.isBefore(visit.scheduledEnd);
        })
        .toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));

    return overlapping;
  }
}