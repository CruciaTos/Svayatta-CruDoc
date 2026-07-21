import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/services/firestore_sync_service.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/services/visits_local_service.dart';
import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/repo/revenue_repo.dart';

/// Standard fee recorded when an appointment ([VisitType.clinic]) is
/// marked [VisitStatus.completed] — see [VisitRepository.updateStatus].
/// Visitations ([VisitType.home]) don't use this yet; their payment
/// handling isn't built out.
const double kAppointmentCompletionFee = 500.0;

/// Clean API the presentation layer talks to for anything visit-related.
///
/// Reads and writes go through SQLite. Writes are marked pending locally and
/// the central sync engine is triggered in the background. This is also where
/// every appointment business rule lives: patient existence/active checks,
/// the scheduled/completed/cancelled/missed status enum, soft delete, and
/// overlap detection with its max-4 hard limit.
class VisitRepository {
  VisitRepository({
    VisitLocalService? localService,
    FirestoreSyncService? syncService,
    PatientRepository? patientRepository,
    RevenueRepository? revenueRepository,
  }) : _localService = localService ?? VisitLocalService(),
       _syncService = syncService ?? FirestoreSyncService.instance,
       _patientRepository = patientRepository ?? PatientRepository(),
       _revenueRepository = revenueRepository ?? RevenueRepository();

  final VisitLocalService _localService;
  final FirestoreSyncService _syncService;
  final PatientRepository _patientRepository;
  final RevenueRepository _revenueRepository;

  /// Creates a new visit for an existing patient.
  ///
  /// Always pass a [visit] whose `patientId` refers to a patient that
  /// already exists — create the patient first (via [PatientRepository])
  /// and use the id it returns here. This method never creates a
  /// patient, and never should.
  ///
  /// TEMPORARY (functional-verification phase): the patient-existence
  /// check and the overlap check below are disabled for now — both were
  /// pre-create Firestore reads, and the patient-existence read in
  /// particular was crashing the app when adding a new visitation.
  /// [acknowledgeOverlap] is kept as a no-op parameter so the call site
  /// doesn't need to change. Restore both `_checkPatient` and
  /// `_checkOverlap` calls (and remove the `unused_element` ignore on
  /// `_checkPatient`) once this is revisited — likely alongside the
  /// planned Local-First/SQLite refactor.
  ///
  /// Throws:
  /// - [VisitValidationException] for missing/invalid fields.
  /// - [PatientNotFoundException] if `visit.patientId` doesn't exist. —
  ///   currently disabled, see above.
  /// - [InactivePatientException] if that patient is archived. —
  ///   currently disabled, see above.
  /// - [SamePatientDoubleBookingException] if the same patient already
  ///   has an overlapping visit — never bypassable. — currently
  ///   disabled, see above.
  /// - [VisitOverlapWarning] if a *different* patient has an overlapping
  ///   visit and [acknowledgeOverlap] is false. Catch this, show the
  ///   doctor the conflicting visits, and call again with
  ///   `acknowledgeOverlap: true` if they confirm. — currently disabled,
  ///   see above.
  /// - [VisitOverlapLimitExceededException] if saving would exceed
  ///   [kMaxOverlappingVisits] simultaneous active visits — never
  ///   bypassable, regardless of [acknowledgeOverlap]. — currently
  ///   disabled, see above.
  ///
  /// Note: geocoding the address is best-effort and never throws — see
  /// [_resolveCoords]. A visit always saves successfully regardless of
  /// whether the address is blank, unresolvable, or the Maps API key
  /// isn't configured yet.
  Future<String> createVisit(
    Visit visit, {
    bool acknowledgeOverlap = false,
  }) async {
    _validate(visit);
    // await _checkPatient(visit.patientId);
    // await _checkOverlap(
    //   patientId: visit.patientId,
    //   start: visit.scheduledStart,
    //   end: visit.scheduledEnd,
    //   acknowledgeOverlap: acknowledgeOverlap,
    // );

    // Geocoding is a nice-to-have (map preview / tap-to-navigate), not a
    // requirement for saving a visit — the address field is optional.
    // If the caller already supplied coordinates, use those. Otherwise,
    // only attempt to geocode when an address was actually entered, and
    // never let a geocoding failure (bad address, no network, or no
    // real Google Maps API key configured yet — see kGoogleMapsApiKey)
    // block the visit from being saved. On failure the visit is simply
    // saved without coordinates; the map preview falls back to a
    // placeholder image until a real address/API key is in place.
    final coords = await _resolveCoords(
      existingLatitude: visit.latitude,
      existingLongitude: visit.longitude,
      address: visit.address,
    );

    final now = DateTime.now();
    final id = visit.id.trim().isEmpty ? const Uuid().v4() : visit.id;
    final visitWithId = Visit(
      id: id,
      patientId: visit.patientId,
      scheduledStart: visit.scheduledStart,
      durationMinutes: visit.durationMinutes,
      address: visit.address,
      latitude: coords?.latitude,
      longitude: coords?.longitude,
      mapsLink: visit.mapsLink,
      visitType: visit.visitType,
      status: visit.status,
      isPaid: visit.isPaid,
      amountCharged: visit.amountCharged,
      isDeleted: visit.isDeleted,
      invoiceId: visit.invoiceId,
      packageId: visit.packageId,
      treatmentType: visit.treatmentType,
      therapistNotes: visit.therapistNotes,
      reminderStatus: visit.reminderStatus,
      calendarEventId: visit.calendarEventId,
      createdAt: now,
      updatedAt: now,
    );

    await _localService.upsertVisit(visitWithId);
    unawaited(_syncService.triggerPostWriteSync());
    return id;
  }

  /// Updates arbitrary fields on an existing visit. Prefer
  /// [rescheduleVisit], [updateStatus], [cancelVisit], or
  /// [softDeleteVisit] for those specific operations — they carry the
  /// right guardrails. `updatedAt` is stamped automatically by the
  /// service layer regardless of what's passed here.
  ///
  /// If [data] contains an `address` key, it's compared against the
  /// visit's current stored address. Only a genuine change triggers a
  /// fresh Geocoding API call — re-saving the same address never
  /// re-geocodes. Geocoding is best-effort: a blank new address or a
  /// failed geocode never blocks the save — see [_resolveCoords]. On a
  /// genuine address change that can't be geocoded, coordinates are
  /// cleared (rather than left pointing at the old address) so the map
  /// preview honestly falls back to a placeholder.
  ///
  /// Throws [VisitValidationException] if [data] contains a `status`
  /// key that isn't one of the predefined [VisitStatus] values — this
  /// is the backstop that keeps free-text statuses out even if a
  /// caller bypasses [updateStatus].
  Future<void> updateVisit(String visitId, Map<String, dynamic> data) async {
    if (data.containsKey('status')) {
      final raw = data['status'];
      final validValues = VisitStatus.values.map((s) => s.value).toSet();
      if (raw is! String || !validValues.contains(raw)) {
        throw VisitValidationException(
          'Invalid status "$raw". Must be one of: ${validValues.join(', ')}.',
        );
      }
    }

    if (data.containsKey('visitType')) {
      final raw = data['visitType'];
      final validValues = VisitType.values.map((t) => t.value).toSet();
      if (raw is! String || !validValues.contains(raw)) {
        throw VisitValidationException(
          'Invalid visitType "$raw". Must be one of: ${validValues.join(', ')}.',
        );
      }
    }

    final localData = Map<String, dynamic>.from(data);

    if (localData.containsKey('address')) {
      final newAddress = (localData['address'] as String?)?.trim() ?? '';
      final existing = await _localService.getVisit(visitId);
      final addressChanged =
          existing == null || existing.address.trim() != newAddress;

      if (addressChanged) {
        final coords = await _resolveCoords(
          existingLatitude: null,
          existingLongitude: null,
          address: newAddress,
        );
        localData['latitude'] = coords?.latitude;
        localData['longitude'] = coords?.longitude;
      }
    }

    localData['updatedAt'] = DateTime.now();

    await _localService.updateVisit(visitId, localData);
    unawaited(_syncService.triggerPostWriteSync());
  }

  /// Moves an existing visit to a new start time and/or duration,
  /// re-running the same patient/overlap checks as [createVisit]
  /// (excluding the visit's own current slot from the conflict search).
  Future<void> rescheduleVisit(
    String visitId, {
    required DateTime newStart,
    int? newDurationMinutes,
    bool acknowledgeOverlap = false,
  }) async {
    final existing = await _localService.getVisit(visitId);
    if (existing == null) {
      throw VisitValidationException('No visit found with id "$visitId".');
    }

    final duration = newDurationMinutes ?? existing.durationMinutes;
    if (duration < kMinVisitDurationMinutes ||
        duration > kMaxVisitDurationMinutes) {
      throw VisitValidationException(
        'Visit duration must be between $kMinVisitDurationMinutes and '
        '$kMaxVisitDurationMinutes minutes.',
      );
    }

    final newEnd = newStart.add(Duration(minutes: duration));

    await _checkOverlap(
      patientId: existing.patientId,
      start: newStart,
      end: newEnd,
      excludeVisitId: visitId,
      acknowledgeOverlap: acknowledgeOverlap,
    );

    await updateVisit(visitId, {
      'scheduledStart': newStart,
      'durationMinutes': duration,
    });
  }

  /// Updates only the [VisitStatus] — the enum is the only way to move
  /// a visit between states, so a free-text status can never slip in.
  ///
  /// Marking a visit [VisitStatus.completed] also runs that type's
  /// completion workflow:
  /// - Appointments ([VisitType.clinic]): stamped [Visit.isPaid] at the
  ///   standard [kAppointmentCompletionFee] rate and a matching
  ///   [RevenueEntry] ([RevenueType.visit], income) is created in the
  ///   same step — same "flip the flag + create the ledger entry
  ///   together" shape as [recordPayment]. Skipped if the visit is
  ///   already paid, so re-completing a visit (e.g. Completed ->
  ///   Reopen -> Completed again) never creates a duplicate revenue
  ///   entry.
  /// - Visitations ([VisitType.home]): left exactly as-is — no payment
  ///   handling yet, so the visit stays unpaid ("Payment Pending" in
  ///   the UI) until that's built.
  ///
  /// No separate write is needed to add this to the patient's Session
  /// History — that section renders live from this patient's [Visit]
  /// documents, so the completed visit (and its payment status) shows
  /// up there automatically.
  Future<void> updateStatus(String visitId, VisitStatus status) async {
    final before = await _localService.getVisit(visitId);

    await updateVisit(visitId, {'status': status.value});

    if (status != VisitStatus.completed) return;
    if (before == null) return;
    if (before.visitType != VisitType.clinic) return;
    if (before.isPaid) return;

    await updateVisit(visitId, {
      'isPaid': true,
      'amountCharged': kAppointmentCompletionFee,
    });

    final patient = await _patientRepository.getPatient(before.patientId);
    final now = DateTime.now();

    await _revenueRepository.createRevenueEntry(
      RevenueEntry(
        id: '',
        date: before.scheduledStart,
        description: 'Payment received for Appointment',
        amount: kAppointmentCompletionFee,
        type: RevenueType.visit,
        kind: TransactionKind.income,
        payer: patient?.fullName,
        patientId: before.patientId,
        visitId: before.id,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Updates only the [VisitType] — lets a booking be reclassified
  /// between clinic and home visitation after the fact without touching
  /// any other field.
  Future<void> updateVisitType(String visitId, VisitType visitType) {
    return updateVisit(visitId, {'visitType': visitType.value});
  }

  /// Marks a visit as cancelled. A real, legitimate cancellation
  /// (distinct from [softDeleteVisit]) — it stays visible in the
  /// patient's history as a cancelled appointment, and immediately
  /// frees up its slot for overlap purposes.
  Future<void> cancelVisit(String visitId) {
    return updateStatus(visitId, VisitStatus.cancelled);
  }

  /// Soft-deletes a visit (e.g. it was created by mistake). The
  /// document is never removed from Firestore — it's only excluded from
  /// every default query — so history is fully preserved.
  Future<void> softDeleteVisit(String visitId) {
    return updateVisit(visitId, {'isDeleted': true});
  }

  /// Records payment for a session: stamps `Visit.isPaid`/
  /// `Visit.amountCharged`, then creates the matching [RevenueEntry]
  /// ([RevenueType.visit], linked back via `patientId`/`visitId`) in the
  /// same step. Mirrors `RevenueRepository.markPendingPaymentAsPaid`'s
  /// "flip the flag + create the ledger entry together" shape, so a
  /// visit is never left paid-on-the-visit-record but missing from the
  /// revenue list, or vice versa.
  ///
  /// Looks up the patient's name for [RevenueEntry.payer] so the
  /// revenue list reads naturally without a separate join at read time.
  /// Falls back to a generic description if the patient record is
  /// missing (e.g. deleted after the visit) rather than blocking the
  /// payment from being recorded.
  ///
  /// Deliberately independent of [VisitStatus] — a session can be paid
  /// in advance while still [VisitStatus.scheduled], or marked
  /// completed and settled later, so this never requires the visit to
  /// already be completed.
  ///
  /// Throws [VisitValidationException] if [visitId] doesn't resolve to
  /// an existing visit, if it's already marked paid (call
  /// `RevenueRepository.softDeleteRevenueEntry` on the linked entry and
  /// revisit this method if a correction is genuinely needed — there is
  /// no bypass here), or if [amount] isn't greater than zero.
  Future<String> recordPayment(String visitId, {required double amount}) async {
    final visit = await _localService.getVisit(visitId);
    if (visit == null) {
      throw VisitValidationException('No visit found with id "$visitId".');
    }
    if (visit.isPaid) {
      throw const VisitValidationException(
        'This visit is already marked as paid.',
      );
    }
    if (amount <= 0) {
      throw const VisitValidationException(
        'Payment amount must be greater than zero.',
      );
    }

    final patient = await _patientRepository.getPatient(visit.patientId);
    final now = DateTime.now();

    await updateVisit(visitId, {
      'isPaid': true,
      'amountCharged': amount,
    });

    return _revenueRepository.createRevenueEntry(
      RevenueEntry(
        id: '',
        date: now,
        description: patient != null
            ? 'Session with ${patient.fullName}'
            : 'Session payment',
        amount: amount,
        type: RevenueType.visit,
        payer: patient?.fullName,
        patientId: visit.patientId,
        visitId: visit.id,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Fetches a single visit by id, or null if it doesn't exist.
  Future<Visit?> getVisit(String visitId) => _localService.getVisit(visitId);

  /// Streams active upcoming visits from [from] (defaults to now)
  /// onward, ordered by start time ascending.
  Stream<List<Visit>> watchUpcomingVisits({DateTime? from}) {
    return _localService.watchUpcomingVisits(from: from);
  }

  /// Streams today's scheduled visits — both clinic appointments and
  /// home visitations combined, chronological order. Powers the
  /// dashboard's "Today's Visits" card.
  Stream<List<Visit>> watchTodaysVisits() {
    return _localService.watchTodaysVisits();
  }

  /// Streams a single patient's visit history, most recent first.
  Stream<List<Visit>> watchVisitsForPatient(
    String patientId, {
    bool includeDeleted = false,
  }) {
    return _localService.watchVisitsForPatient(
      patientId,
      includeDeleted: includeDeleted,
    );
  }

  /// Streams patientId -> their most recent visit that has already
  /// occurred, refreshed automatically after every visit write. Powers
  /// the "Last Patient" summary card without querying per-patient.
  Stream<Map<String, Visit>> watchLastVisitPerPatient() {
    return _localService.watchLastVisitPerPatient();
  }

  /// Read-only overlap check for the UI to call live — e.g. as soon as
  /// the doctor picks a time — so it can show a warning *before* they
  /// even tap save. [createVisit] and [rescheduleVisit] re-run this
  /// check themselves regardless, so this is a courtesy for a
  /// responsive UI, never the only line of defense.
  Future<List<Visit>> findOverlapping({
    required DateTime start,
    required DateTime end,
    String? excludeVisitId,
  }) {
    return _localService.findOverlapping(
      start: start,
      end: end,
      excludeVisitId: excludeVisitId,
    );
  }

  // ---------------- internal helpers ----------------

  void _validate(Visit visit) {
    if (visit.patientId.trim().isEmpty) {
      throw const VisitValidationException('A visit must have a patientId.');
    }
    // Address is intentionally optional (matching _AddVisitDialog's
    // "Address (optional)" field) — this app is still offline/in-person
    // only, but a visit can be created before the address is nailed
    // down, or with maps support not yet configured. Geocoding is
    // handled separately as best-effort — see _resolveCoords.
    if (visit.durationMinutes < kMinVisitDurationMinutes ||
        visit.durationMinutes > kMaxVisitDurationMinutes) {
      throw VisitValidationException(
        'Visit duration must be between $kMinVisitDurationMinutes and '
        '$kMaxVisitDurationMinutes minutes.',
      );
    }
    if (!visit.scheduledStart.isBefore(visit.scheduledEnd)) {
      throw const VisitValidationException(
        'A visit must have a positive duration.',
      );
    }
  }

  // ignore: unused_element
  Future<void> _checkPatient(String patientId) async {
    final patient = await _patientRepository.getPatient(patientId);
    if (patient == null) {
      throw PatientNotFoundException(patientId);
    }
    if (patient.isArchived) {
      throw InactivePatientException(patientId);
    }
  }

  Future<void> _checkOverlap({
    required String patientId,
    required DateTime start,
    required DateTime end,
    String? excludeVisitId,
    required bool acknowledgeOverlap,
  }) async {
    final conflicts = await _localService.findOverlapping(
      start: start,
      end: end,
      excludeVisitId: excludeVisitId,
    );

    if (conflicts.isEmpty) return;

    // The same patient can never legitimately be at two visits at
    // once — that's never something to "acknowledge", it's just wrong,
    // regardless of how much headroom is left under the max-overlap cap.
    final samePatientConflicts = conflicts.where(
      (v) => v.patientId == patientId,
    );
    if (samePatientConflicts.isNotEmpty) {
      throw SamePatientDoubleBookingException(samePatientConflicts.first);
    }

    if (conflicts.length >= kMaxOverlappingVisits) {
      throw VisitOverlapLimitExceededException(conflicts);
    }

    if (!acknowledgeOverlap) {
      throw VisitOverlapWarning(conflicts);
    }
  }

  /// Resolves the coordinates to save for a visit, without ever blocking
  /// the save itself:
  /// - If [existingLatitude]/[existingLongitude] are both already
  ///   present, reuse them as-is (no network call).
  /// - If [address] is blank (it's an optional field), there's nothing
  ///   to geocode — returns `null`.
  /// - Otherwise attempts [_geocodeAddress]. If that fails for any
  ///   reason — bad/unrecognized address, no network, or no real Google
  ///   Maps API key configured yet (`kGoogleMapsApiKey` still the
  ///   placeholder) — the failure is swallowed and `null` is returned
  ///   instead of propagating [GeocodingException]. The visit still
  ///   saves; the map preview just falls back to a placeholder image
  ///   until a resolvable address (and a real API key) are in place.
  Future<({double latitude, double longitude})?> _resolveCoords({
    required double? existingLatitude,
    required double? existingLongitude,
    required String address,
  }) async {
    if (existingLatitude != null && existingLongitude != null) {
      return (latitude: existingLatitude, longitude: existingLongitude);
    }
    if (address.trim().isEmpty) return null;
    try {
      return await _geocodeAddress(address);
    } on GeocodingException {
      return null;
    }
  }

  /// Calls the Google Geocoding API to resolve [address] into
  /// coordinates. Never returns partial/invalid data — any failure
  /// (network error, non-200 response, unparseable body, "not found"
  /// status, or a missing lat/lng in the result) surfaces as a
  /// [GeocodingException] instead. Callers that want a save to succeed
  /// regardless of geocoding outcome should go through [_resolveCoords]
  /// rather than calling this directly.
  Future<({double latitude, double longitude})> _geocodeAddress(
    String address,
  ) async {
    final trimmed = address.trim();
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': trimmed,
      'key': kGoogleMapsApiKey,
    });

    final http.Response response;
    try {
      response = await http.get(uri);
    } catch (_) {
      throw const GeocodingException(
        'Could not reach the geocoding service. Check your connection '
        'and try again.',
      );
    }

    if (response.statusCode != 200) {
      throw GeocodingException(
        'Geocoding request failed (HTTP ${response.statusCode}). '
        'Please try again.',
      );
    }

    late final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const GeocodingException(
        'Received an unexpected response while locating this address.',
      );
    }

    final status = body['status'] as String?;
    final results = body['results'] as List<dynamic>?;
    if (status != 'OK' || results == null || results.isEmpty) {
      throw GeocodingException(
        'Could not find a location for "$trimmed". Please check the '
        'address and try again.',
      );
    }

    double? lat;
    double? lng;
    try {
      final location =
          (results.first as Map<String, dynamic>)['geometry']
              as Map<String, dynamic>?;
      final coords = location?['location'] as Map<String, dynamic>?;
      lat = (coords?['lat'] as num?)?.toDouble();
      lng = (coords?['lng'] as num?)?.toDouble();
    } catch (_) {
      // Fall through — handled by the null check below.
    }
    if (lat == null || lng == null) {
      throw GeocodingException(
        'Could not determine coordinates for "$trimmed".',
      );
    }

    return (latitude: lat, longitude: lng);
  }
}