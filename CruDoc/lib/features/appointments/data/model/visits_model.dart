import 'package:cloud_firestore/cloud_firestore.dart';

/// The maximum number of visits allowed to overlap in time.
///
/// A single practice may run more than one simultaneous appointment (e.g.
/// several therapists each seeing a different patient at once), so
/// overlapping visits are allowed — but capped, so a scheduling mistake
/// can't silently pile up an unbounded number of visits on one slot.
const int kMaxOverlappingVisits = 4;

/// Sanity bounds for a visit's duration, in minutes. These exist to catch
/// obvious data-entry mistakes (a duration of 0, or a stray extra digit
/// like 4800) — not to constrain real-world scheduling.
const int kMinVisitDurationMinutes = 5;
const int kMaxVisitDurationMinutes = 480; // 8 hours

/// Google Maps API key used for both the Geocoding API (address ->
/// coordinates) and the Static Maps API (map preview images).
///
/// TODO: move this to a secure secrets/config source before shipping.
/// Kept as a plain constant here — matching this file's existing flat
/// constant style above — to avoid introducing a new config file for a
/// single key.
const String kGoogleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';

/// Builds a Google Static Maps image URL for the given coordinates, or
/// `null` if either coordinate is missing.
///
/// Deliberately parameter-stable (no timestamps, session tokens, or other
/// varying values) so `CachedNetworkImage` derives the same cache key for
/// the same visit across app launches, instead of re-downloading the image
/// every time.
String? staticMapUrlFor({required double? latitude, required double? longitude}) {
  if (latitude == null || longitude == null) return null;
  return 'https://maps.googleapis.com/maps/api/staticmap'
      '?center=$latitude,$longitude'
      '&zoom=15&size=600x300&scale=2'
      '&markers=color:red%7C$latitude,$longitude'
      '&key=$kGoogleMapsApiKey';
}

/// Predefined visit lifecycle states.
///
/// Deliberately an enum rather than a free-text string, so an invalid
/// status can never be written from within the app — see
/// [VisitStatus.fromValue] for how unrecognized Firestore data is
/// handled defensively on the read side.
enum VisitStatus {
  scheduled,
  completed,
  cancelled,
  missed;

  /// The exact string stored in Firestore for this status.
  String get value => name;

  /// Parses a raw Firestore string into a [VisitStatus]. Falls back to
  /// [VisitStatus.scheduled] for anything unrecognized (missing field,
  /// legacy data, a manual Firestore console edit) rather than throwing,
  /// so one corrupted document can't crash an entire visit list.
  static VisitStatus fromValue(String? raw) {
    return VisitStatus.values.firstWhere(
      (status) => status.value == raw,
      orElse: () => VisitStatus.scheduled,
    );
  }
}

/// Core Visit (appointment) data model.
///
/// Represents a single in-person / home-visit appointment stored in the
/// `visits` Firestore collection. Written as a plain, hand-rolled model
/// (no freezed/json_serializable) to match [Patient]'s style.
///
/// A [Visit] deliberately stores only [patientId] — never the patient's
/// name, phone, gender, DOB, or diagnosis. Those live on the Patient
/// document and are looked up by id whenever needed for display, so
/// there is exactly one place they can go stale.
///
/// Scoped to offline/in-person visits only: there is no meeting link,
/// platform, or other video-call field here on purpose. Those belong to
/// the separate online-sessions module, which is a distinct Firestore
/// collection built on its own, not a variant of this one.
class Visit {
  final String id;
  final String patientId;

  /// The moment the visit is scheduled to start.
  final DateTime scheduledStart;

  /// Length of the visit in minutes. [scheduledEnd] is derived from this.
  final int durationMinutes;

  /// Physical location for this specific visit (e.g. the patient's
  /// home). Stored per-visit rather than copied from the patient, since
  /// where a visit happens can change from appointment to appointment.
  final String address;

  /// Coordinates geocoded from [address]. Both are null until a successful
  /// Geocoding API call has resolved this visit's address — never written
  /// as invalid/partial data (see [VisitRepository]'s create/update flow).
  final double? latitude;
  final double? longitude;

  final VisitStatus status;

  /// True once this visit has been soft-deleted (e.g. it was created by
  /// mistake). Distinct from `status == cancelled`, which represents a
  /// real appointment that was legitimately called off. A soft-deleted
  /// visit is hidden from every default query, but the document itself
  /// is never removed from Firestore — history is fully preserved.
  final bool isDeleted;

  // ---- Future-proofing fields ----
  // All nullable and unused today. They exist so invoicing, packages,
  // treatment tracking, therapist notes, reminders, and calendar sync
  // can be wired up later without a schema migration or a breaking
  // model change.
  final String? invoiceId;
  final String? packageId;
  final String? treatmentType;
  final String? therapistNotes;
  final String? reminderStatus;
  final String? calendarEventId;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Visit({
    required this.id,
    required this.patientId,
    required this.scheduledStart,
    required this.durationMinutes,
    required this.address,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.latitude,
    this.longitude,
    this.isDeleted = false,
    this.invoiceId,
    this.packageId,
    this.treatmentType,
    this.therapistNotes,
    this.reminderStatus,
    this.calendarEventId,
  });

  /// The moment the visit is scheduled to end, derived from
  /// [scheduledStart] + [durationMinutes].
  DateTime get scheduledEnd =>
      scheduledStart.add(Duration(minutes: durationMinutes));

  /// Google Static Maps image URL for this visit's stored coordinates, or
  /// null if it hasn't been geocoded yet.
  String? get staticMapUrl =>
      staticMapUrlFor(latitude: latitude, longitude: longitude);

  /// True if this visit's time range intersects [other]'s. Two visits
  /// with abutting edges (one ends exactly when the other starts) do
  /// NOT count as overlapping.
  bool overlapsWith(Visit other) {
    return scheduledStart.isBefore(other.scheduledEnd) &&
        other.scheduledStart.isBefore(scheduledEnd);
  }

  /// Builds a [Visit] from a Firestore document snapshot.
  factory Visit.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Visit.fromMap(data, id: doc.id);
  }

  /// Builds a [Visit] from a raw map (e.g. Firestore data payload).
  factory Visit.fromMap(Map<String, dynamic> map, {required String id}) {
    return Visit(
      id: id,
      patientId: map['patientId'] as String? ?? '',
      scheduledStart: _timestampToDate(map['scheduledStart']),
      durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 30,
      address: map['address'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      status: VisitStatus.fromValue(map['status'] as String?),
      isDeleted: map['isDeleted'] as bool? ?? false,
      invoiceId: map['invoiceId'] as String?,
      packageId: map['packageId'] as String?,
      treatmentType: map['treatmentType'] as String?,
      therapistNotes: map['therapistNotes'] as String?,
      reminderStatus: map['reminderStatus'] as String?,
      calendarEventId: map['calendarEventId'] as String?,
      createdAt: _timestampToDate(map['createdAt']),
      updatedAt: _timestampToDate(map['updatedAt']),
    );
  }

  /// Converts this [Visit] into a Firestore-writable map. The document
  /// id is not included, since it is the document key.
  Map<String, dynamic> toMap() {
    return {
      'patientId': patientId,
      'scheduledStart': Timestamp.fromDate(scheduledStart),
      'durationMinutes': durationMinutes,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'status': status.value,
      'isDeleted': isDeleted,
      'invoiceId': invoiceId,
      'packageId': packageId,
      'treatmentType': treatmentType,
      'therapistNotes': therapistNotes,
      'reminderStatus': reminderStatus,
      'calendarEventId': calendarEventId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Visit copyWith({
    String? patientId,
    DateTime? scheduledStart,
    int? durationMinutes,
    String? address,
    double? latitude,
    double? longitude,
    VisitStatus? status,
    bool? isDeleted,
    String? invoiceId,
    String? packageId,
    String? treatmentType,
    String? therapistNotes,
    String? reminderStatus,
    String? calendarEventId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Visit(
      id: id,
      patientId: patientId ?? this.patientId,
      scheduledStart: scheduledStart ?? this.scheduledStart,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      status: status ?? this.status,
      isDeleted: isDeleted ?? this.isDeleted,
      invoiceId: invoiceId ?? this.invoiceId,
      packageId: packageId ?? this.packageId,
      treatmentType: treatmentType ?? this.treatmentType,
      therapistNotes: therapistNotes ?? this.therapistNotes,
      reminderStatus: reminderStatus ?? this.reminderStatus,
      calendarEventId: calendarEventId ?? this.calendarEventId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _timestampToDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }
}