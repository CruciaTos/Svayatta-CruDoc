import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

/// How much larger text and icons are in chairside mode.
const double largeModeScale = 1.2;

/// Chairside mode (children, reading at a distance): the main area's
/// text and icons 20% larger, the sidebar as it is. Stored as a clinic
/// meta record {'what': 'largeMode', 'value': true}. Off by default.
final largeModeProvider = FutureProvider<bool>((ref) async {
  final records = await ref.watch(clinicRecordsProvider(RecKind.meta).future);
  for (final r in records) {
    if (r.str('what') == 'largeMode') return r.data['value'] == true;
  }
  return false;
});

/// Saves the chairside mode choice (one meta record, updated in place).
Future<void> setLargeMode(WidgetRef ref, bool on) async {
  final records = await ref.read(clinicRecordsProvider(RecKind.meta).future);
  DentalRecord? current;
  for (final r in records) {
    if (r.str('what') == 'largeMode') {
      current = r;
      break;
    }
  }
  final record = current == null
      ? DentalRecord.create('', RecKind.meta, {'what': 'largeMode', 'value': on})
      : current.copyWith(data: {...current.data, 'value': on});
  await saveDentalRecord(ref, record);
}
