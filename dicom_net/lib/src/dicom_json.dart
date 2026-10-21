import 'dataset.dart';

/// Builds one DICOM JSON object (PS3.18 F.2) from attribute strings.
/// Multiple values are separated by "\" as in DICOM.
Map<String, Object> dicomJson(Map<DicomAttr, String?> attrs) {
  final out = <String, Object>{};
  for (final e in attrs.entries) {
    final a = e.key;
    final raw = e.value;
    if (raw == null || raw.isEmpty) {
      out[a.hex] = {'vr': a.vr};
      continue;
    }
    final parts = raw.split('\\');
    final Object value = switch (a.vr) {
      'PN' => [
        for (final p in parts) {'Alphabetic': p},
      ],
      'IS' || 'US' || 'UL' || 'SL' || 'SS' => [
        for (final p in parts) int.tryParse(p.trim()) ?? 0,
      ],
      'DS' || 'FL' || 'FD' => [
        for (final p in parts) num.tryParse(p.trim()) ?? 0,
      ],
      _ => parts,
    };
    out[a.hex] = {'vr': a.vr, 'Value': value};
  }
  return out;
}

/// Reads one attribute of a DICOM JSON object as a string ("" if absent).
/// Person names come back as "Doe^Jane"; multiple values joined by "\".
String dicomJsonString(Map<String, dynamic> obj, DicomAttr a) {
  final el = obj[a.hex];
  if (el is! Map) return '';
  final v = el['Value'];
  if (v is! List || v.isEmpty) return '';
  return v
      .map((x) => x is Map ? (x['Alphabetic'] ?? '').toString() : '$x')
      .join('\\');
}

/// One study as a PACS lists it.
class DicomStudySummary {
  const DicomStudySummary({
    required this.studyUid,
    this.patientName = '',
    this.patientId = '',
    this.patientSex = '',
    this.patientBirthDate,
    this.studyDate,
    this.accession = '',
    this.description = '',
    this.modalities = const [],
    this.seriesCount = 0,
    this.instanceCount = 0,
    this.referringPhysician = '',
  });

  final String studyUid;

  /// "Doe^Jane".
  final String patientName;
  final String patientId;
  final String patientSex;
  final DateTime? patientBirthDate;
  final DateTime? studyDate;
  final String accession;
  final String description;
  final List<String> modalities;
  final int seriesCount;
  final int instanceCount;
  final String referringPhysician;

  /// "Jane Doe" from "Doe^Jane".
  String get displayName {
    final parts = patientName.split('=').first.split('^');
    if (parts.length >= 2 && parts[1].trim().isNotEmpty) {
      return '${parts[1].trim()} ${parts[0].trim()}'.trim();
    }
    return parts.first.trim();
  }

  factory DicomStudySummary.fromJson(Map<String, dynamic> j) {
    String s(DicomAttr a) => dicomJsonString(j, a);
    return DicomStudySummary(
      studyUid: s(DicomAttr.studyInstanceUid),
      patientName: s(DicomAttr.patientName),
      patientId: s(DicomAttr.patientId),
      patientSex: s(DicomAttr.patientSex),
      patientBirthDate: parseDicomDate(s(DicomAttr.patientBirthDate)),
      studyDate: parseDicomDate(
        s(DicomAttr.studyDate),
        s(DicomAttr.studyTime),
      ),
      accession: s(DicomAttr.accessionNumber),
      description: s(DicomAttr.studyDescription),
      modalities: [
        for (final m in s(DicomAttr.modalitiesInStudy).split('\\'))
          if (m.trim().isNotEmpty) m.trim(),
      ],
      seriesCount: int.tryParse(s(DicomAttr.numberOfStudyRelatedSeries)) ?? 0,
      instanceCount:
          int.tryParse(s(DicomAttr.numberOfStudyRelatedInstances)) ?? 0,
      referringPhysician: s(DicomAttr.referringPhysicianName),
    );
  }
}

/// "20261021" (+ "143005.123") → DateTime.
DateTime? parseDicomDate(String da, [String tm = '']) {
  final d = da.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length < 8) return null;
  final y = int.tryParse(d.substring(0, 4));
  final m = int.tryParse(d.substring(4, 6));
  final day = int.tryParse(d.substring(6, 8));
  if (y == null || m == null || day == null) return null;
  final t = tm.replaceAll(RegExp(r'[^0-9]'), '');
  int part(int i) =>
      t.length >= i + 2 ? int.tryParse(t.substring(i, i + 2)) ?? 0 : 0;
  return DateTime(y, m, day, part(0), part(2), part(4));
}

/// DateTime → "20261021".
String dicomDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

/// DateTime → "143005".
String dicomTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}'
    '${d.minute.toString().padLeft(2, '0')}'
    '${d.second.toString().padLeft(2, '0')}';
