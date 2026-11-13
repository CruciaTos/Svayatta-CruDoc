import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

/// How tooth ids (always FDI internally) are shown to the clinic.
enum ToothNumbering {
  fdi('FDI'),
  universal('Universal');

  const ToothNumbering(this.label);

  /// "FDI" / "Universal", used as the segmented-control label.
  final String label;
}

/// Permanent teeth: FDI to Universal (1–32).
///
/// Upper right runs 18→11 as 1→8, upper left 21→28 as 9→16,
/// lower left 38→31 as 17→24, lower right 41→48 as 25→32.
const Map<String, String> _permanentUniversal = {
  '18': '1',
  '17': '2',
  '16': '3',
  '15': '4',
  '14': '5',
  '13': '6',
  '12': '7',
  '11': '8',
  '21': '9',
  '22': '10',
  '23': '11',
  '24': '12',
  '25': '13',
  '26': '14',
  '27': '15',
  '28': '16',
  '38': '17',
  '37': '18',
  '36': '19',
  '35': '20',
  '34': '21',
  '33': '22',
  '32': '23',
  '31': '24',
  '41': '25',
  '42': '26',
  '43': '27',
  '44': '28',
  '45': '29',
  '46': '30',
  '47': '31',
  '48': '32',
};

/// Primary (milk) teeth: FDI to Universal (A–T).
///
/// 55→A … 51→E, 61→F … 65→J, 75→K … 71→O, 81→P … 85→T.
const Map<String, String> _primaryUniversal = {
  '55': 'A',
  '54': 'B',
  '53': 'C',
  '52': 'D',
  '51': 'E',
  '61': 'F',
  '62': 'G',
  '63': 'H',
  '64': 'I',
  '65': 'J',
  '75': 'K',
  '74': 'L',
  '73': 'M',
  '72': 'N',
  '71': 'O',
  '81': 'P',
  '82': 'Q',
  '83': 'R',
  '84': 'S',
  '85': 'T',
};

/// The label to show for an FDI tooth id.
///
/// FDI returns the id unchanged. Universal returns 1–32 for permanent
/// teeth and A–T for primary teeth. Unknown ids fall through unchanged,
/// so nothing is ever hidden.
String toothLabel(String fdi, ToothNumbering n) {
  if (n == ToothNumbering.fdi) return fdi;
  final t = fdi.trim();
  return _permanentUniversal[t] ?? _primaryUniversal[t] ?? t;
}

/// The clinic's choice, stored as a meta record (kind 'meta', data
/// {'what': 'numbering', 'value': 'fdi' | 'universal'}). Default FDI.
final toothNumberingProvider = FutureProvider<ToothNumbering>((ref) async {
  final records = await ref.watch(clinicRecordsProvider(RecKind.meta).future);
  for (final r in records) {
    if (r.str('what') != 'numbering') continue;
    final v = r.str('value').toLowerCase().trim();
    if (v == 'universal') return ToothNumbering.universal;
    if (v == 'fdi') return ToothNumbering.fdi;
  }
  return ToothNumbering.fdi;
});

/// Persists the clinic's tooth numbering choice.
///
/// Uses one meta record for the whole clinic: it is created the first
/// time and updated in place afterwards, so the history stays tidy.
Future<void> setToothNumbering(WidgetRef ref, ToothNumbering n) async {
  final records = await ref.read(clinicRecordsProvider(RecKind.meta).future);
  DentalRecord? current;
  for (final r in records) {
    if (r.str('what') == 'numbering') {
      current = r;
      break;
    }
  }
  final record = current == null
      ? DentalRecord.create('', RecKind.meta, {
          'what': 'numbering',
          'value': n.name,
        })
      : current.copyWith(data: {...current.data, 'value': n.name});
  await saveDentalRecord(ref, record);
}

/// How the 2D tooth chart is laid out.
enum ToothChartView {
  rows('Rows'),
  arches('Arches');

  const ToothChartView(this.label);

  /// "Rows" / "Arches", used as the segmented-control label.
  final String label;
}

/// The clinic's chart view choice, stored as a meta record. Default Rows.
final toothChartViewProvider = FutureProvider<ToothChartView>((ref) async {
  final records = await ref.watch(clinicRecordsProvider(RecKind.meta).future);
  for (final r in records) {
    if (r.str('what') != 'chart_view') continue;
    final v = r.str('value').toLowerCase().trim();
    if (v == 'arches') return ToothChartView.arches;
    if (v == 'rows') return ToothChartView.rows;
  }
  return ToothChartView.rows;
});

/// Persists the clinic's tooth chart view choice.
Future<void> setToothChartView(WidgetRef ref, ToothChartView view) async {
  final records = await ref.read(clinicRecordsProvider(RecKind.meta).future);
  DentalRecord? current;
  for (final r in records) {
    if (r.str('what') == 'chart_view') {
      current = r;
      break;
    }
  }
  final record = current == null
      ? DentalRecord.create('', RecKind.meta, {
          'what': 'chart_view',
          'value': view.name,
        })
      : current.copyWith(data: {...current.data, 'value': view.name});
  await saveDentalRecord(ref, record);
}

/// How the odontogram (arch chart) teeth are drawn.
enum OdontogramStyle {
  flat2d('2D'),
  model3d('3D');

  const OdontogramStyle(this.label);

  /// "2D" / "3D", used as the segmented-control label.
  final String label;
}

/// The odontogram style choice (2D line art or 3D clay) in settings; off: the
/// choice is hidden and the chart is always 2D (a saved model3d value is ignored).
const bool kOdontogram3dEnabled = true;

/// The clinic's odontogram style choice, stored as a meta record. Default 2D.
final odontogramStyleProvider = FutureProvider<OdontogramStyle>((ref) async {
  if (!kOdontogram3dEnabled) return OdontogramStyle.flat2d;
  final records = await ref.watch(clinicRecordsProvider(RecKind.meta).future);
  for (final r in records) {
    if (r.str('what') != 'odontogram_style') continue;
    final v = r.str('value').toLowerCase().trim();
    if (v == 'model3d') return OdontogramStyle.model3d;
    if (v == 'flat2d') return OdontogramStyle.flat2d;
  }
  return OdontogramStyle.flat2d;
});

/// Persists the clinic's odontogram style choice.
Future<void> setOdontogramStyle(WidgetRef ref, OdontogramStyle style) async {
  final records = await ref.read(clinicRecordsProvider(RecKind.meta).future);
  DentalRecord? current;
  for (final r in records) {
    if (r.str('what') == 'odontogram_style') {
      current = r;
      break;
    }
  }
  final record = current == null
      ? DentalRecord.create('', RecKind.meta, {
          'what': 'odontogram_style',
          'value': style.name,
        })
      : current.copyWith(data: {...current.data, 'value': style.name});
  await saveDentalRecord(ref, record);
}
