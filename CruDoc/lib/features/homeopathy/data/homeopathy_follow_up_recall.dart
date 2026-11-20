import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';

/// Turning a homeopathy follow-up date into a recall, so somebody is actually
/// reminded to bring the patient back.
///
/// A dose plan already writes its own recall for the review date. The follow-up
/// date on the case sheet and on a session note did not: it was saved, shown on
/// the patient's page and handed to the AI tools, but nothing swept it, so a
/// homeopath who set a follow-up without a dose plan was never reminded of it.
/// Homeopathy is long-term relationship care and the whole case depends on the
/// patient coming back, so that date is the one worth chasing.

/// Marks the recalls this file owns, so it only ever rewrites its own.
const String kHomeoFollowUpSource = 'homeoFollowUp';

/// The reason written on the recall. It is shown in the recall list and drops
/// into the reminder's sentence ("your {reason} is due on {date}"), so it is
/// phrased to read as part of one.
/// Capitalised for the recall list, which shows it as written; the reminder
/// lower-cases it on its way into the sentence.
const String kHomeoFollowUpReason = 'Homeopathy follow-up';

/// Whether [r] is a follow-up recall this file wrote and may rewrite.
///
/// A recall the doctor has already acted on is not one of ours to touch, even
/// when we wrote it: they have booked the patient or called it off, and the
/// reminder has done its job.
bool isOursToReplace(DentalRecord r) =>
    r.str('source') == kHomeoFollowUpSource && recallStatusOf(r).isOpen;

/// The record data for a follow-up recall.
///
/// Pulled out so the shape the recall list and the reminder both read
/// 'reason' for, and the status they filter on, can be pinned by a test.
Map<String, dynamic> homeoFollowUpRecallData({
  required String patientName,
  String notes = '',
}) => {
  'patientName': patientName,
  'reason': kHomeoFollowUpReason,
  // No rule behind it, so the reminder falls back to the default wording,
  // which reads correctly for a follow-up on a date.
  'ruleId': '',
  'notes': notes.trim(),
  'status': RecallStatus.pending.name,
  'source': kHomeoFollowUpSource,
};

/// Makes the patient's follow-up recall match [date].
///
/// Deliberately keyed on [kHomeoFollowUpSource] rather than on an id stored
/// against the case sheet: the date can be changed from the case sheet or from
/// a session note, and neither knows what the other wrote. Rewriting whatever
/// this file left last time keeps one open follow-up recall per patient
/// however many places set it, and needs no new field on either model.
///
/// A null [date] clears it: the follow-up was removed, so the reminder goes
/// with it. A date the patient has already been seen for is cleared the same
/// way by the next save that moves it on.
///
/// Recalls the doctor has already acted on (booked, cancelled) are left alone;
/// only an open one is replaced. Failure is swallowed: a reminder that could
/// not be written must never cost the doctor the case notes they just saved.
Future<void> syncHomeoFollowUpRecall(
  WidgetRef ref, {
  required String patientId,
  required String patientName,
  required DateTime? date,
  String notes = '',
}) async {
  if (patientId.isEmpty) return;
  try {
    final existing =
        await ref.read(
          patientRecordsProvider((
            patientId: patientId,
            kind: RecKind.recall,
          )).future,
        );
    for (final r in existing) {
      if (!isOursToReplace(r)) continue;
      await deleteDentalRecord(ref, r);
    }
    if (date == null) return;
    await saveDentalRecord(
      ref,
      DentalRecord.create(
        patientId,
        RecKind.recall,
        homeoFollowUpRecallData(patientName: patientName, notes: notes),
        at: date,
      ),
    );
  } catch (_) {
    // The case notes are already saved; the recall is a convenience on top.
  }
}
