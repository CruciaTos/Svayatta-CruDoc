import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';

/// Finding the patients who bought a block of sessions and then stopped
/// coming, while sessions were still left on it.
///
/// Physiotherapy income runs on packages, and a package that stalls halfway
/// is money the clinic has already been paid for but will be asked to refund,
/// alongside treatment the patient never finished. Nothing else in CruDoc
/// notices: a dental treatment due again raises a recall from its rule, and a
/// homeopathy dose plan writes its own recall for the review date, but a

  /// The package ran past its validity date with sessions still on it, so
  /// this is a refund conversation as much as a booking one.
  final bool expired;

  int get sessionsLeft => package.left;

  /// Whole days since [since].
  int daysSince(DateTime now) => now.difference(since).inDays;

  /// The patient-facing phrase for this package, e.g. "knee rehab package,
  /// 4 of 10 sessions left". It is written to the recall's reason, which the
  /// recall list shows and the reminder drops into its sentence, so it has
  /// to read as part of one.
  String get reasonLine {
    final left = '$sessionsLeft of ${package.total} sessions left';
    final name = package.name.trim();
    return name.isEmpty ? 'package, $left' : '$name package, $left';
  }

  /// A short line for the suggestion list, e.g.
  /// "Knee rehab - 4 of 10 sessions left, last seen 34 days ago".
  String summary(DateTime now) {
    final name = package.name.trim();
    final left = '$sessionsLeft of ${package.total} sessions left';
    final when = expired
        ? 'package expired'
        : 'last seen ${daysSince(now)} days ago';
    return name.isEmpty ? '$left, $when' : '$name - $left, $when';
  }
}

/// The stalled packages worth chasing, oldest first.
///
/// A package is stalled when sessions are left on it and either it ran past
/// its validity date, or nothing has been used for [stallDays].
///
/// A patient is left out when they are not in [activePatientIds] (archived,
/// or gone from this device), when they already have a visit booked, or when
/// a recall is already open for them: whoever is chasing them does not need
/// CruDoc suggesting it twice. Only the patient's most stalled package is
/// returned, so one person is one call.
List<PackageDropOff> packageDropOffs({
  required List<SessionPackage> packages,
  required Set<String> activePatientIds,
  required Set<String> patientsWithUpcomingVisit,
  required Set<String> patientsWithOpenRecall,
  required DateTime now,
  int stallDays = kPackageStallDays,
}) {
  final best = <String, PackageDropOff>{};
  for (final p in packages) {
    if (p.completed) continue;
    final patientId = p.record.patientId;
    if (patientId.isEmpty) continue;
    if (!activePatientIds.contains(patientId)) continue;
    if (patientsWithUpcomingVisit.contains(patientId)) continue;
    if (patientsWithOpenRecall.contains(patientId)) continue;

    final since = p.used.isEmpty ? p.date : p.used.last;
    final stalled = now.difference(since).inDays >= stallDays;
    if (!stalled && !p.expired) continue;

    final found = PackageDropOff(
      patientId: patientId,
      package: p,
      since: since,
      expired: p.expired,
    );
    // The longest-stalled package is the one worth the call.
    final had = best[patientId];
    if (had == null || found.since.isBefore(had.since)) {
      best[patientId] = found;
    }
  }
  return best.values.toList()..sort((a, b) => a.since.compareTo(b.since));
}
