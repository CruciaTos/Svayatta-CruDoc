import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';

/// What a no-show does to a prepaid package.
///
/// Whether a missed session is used up is clinic policy, not something the
/// app should decide: a strict cancellation policy says it is gone, a
/// generous one gives it back, and the same clinic may treat a first offence
/// differently from a third. So the physio is asked, once, at the moment they
/// mark the visit missed, and nothing is deducted unless they say so.
///
/// Sessions are otherwise still ticked off by hand on the sessions screen, so
/// this never deducts on its own and cannot double-count against that.

/// The package a missed visit would draw from.
///
/// The one that is still live — sessions left and not past its validity date
/// — and, where there are several, the most recently started, since that is
/// the one the patient is currently working through. Null when the patient
/// has no live package, which is the common case and means no prompt.
SessionPackage? packageForNoShow(List<SessionPackage> packages) {
  SessionPackage? best;
  for (final p in packages) {
    if (p.completed || p.expired) continue;
    if (best == null || p.date.isAfter(best.date)) best = p;
  }
  return best;
}

/// Asks whether a missed visit used up a session, and deducts it if so.
///
/// Call this after a visit has been marked missed. It does nothing at all
/// when the patient has no live package, so it is safe to call for every
/// patient regardless of specialty.
///
/// [at] is the date of the missed visit, not today: a visit marked missed a
/// week late must draw the session from the day it was missed, or the
/// package history stops matching the diary.
Future<void> askPackageDeduction(
  BuildContext context,
  WidgetRef ref, {
  required String patientId,
  required DateTime at,
}) async {
  if (patientId.isEmpty) return;
  final records = await ref.read(
    patientRecordsProvider((
      patientId: patientId,
      kind: RecKind.physioPackage,
    )).future,
  );
  final pkg = packageForNoShow(sessionPackages(records));
  if (pkg == null || !context.mounted) return;

  final name = pkg.name.trim().isEmpty ? 'the package' : '"${pkg.name.trim()}"';
  final deduct = await confirmDental(
    context,
    title: 'Use up a session?',
    body:
        'This visit was missed. $name has ${pkg.left} of ${pkg.total} '
        'sessions left.\n\nDeducting it follows a strict cancellation '
        'policy. Leaving it returns the session to the patient.',
    action: 'Deduct a session',
  );
  if (!deduct) return;
  await saveDentalRecord(
    ref,
    pkg.record.copyWith(data: pkg.dataWithUse(at)),
  );
}
