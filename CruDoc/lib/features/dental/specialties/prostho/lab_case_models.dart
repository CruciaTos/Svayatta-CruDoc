import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

/// The 9 progressive stages of a lab case.
enum LabCaseStage {
  scanned('Scanned'),
  sent('Sent to lab'),
  design('CAD Design'),
  milling('Milling / Fab'),
  qc('QC / Glaze'),
  shipped('Shipped'),
  received('Received'),
  fitted('Fitted'),
  remake('Remake');

  const LabCaseStage(this.label);
  final String label;

  static LabCaseStage fromName(String? n) =>
      values.firstWhere((s) => s.name == n, orElse: () => scanned);

  /// Whether the case is actively at the lab / in fabrication.
  bool get isAtLab =>
      this == sent || this == design || this == milling || this == qc || this == shipped;

  /// Whether the case is open (not yet fitted).
  bool get isOpen => this != fitted;
}

/// One attachment associated with a lab case (3D scan, photo, CAD design).
class LabCaseFile {
  const LabCaseFile({
    required this.path,
    required this.name,
    this.kind = 'scan',
  });

  final String path;
  final String name;
  final String kind; // 'scan' | 'photo' | 'design' | 'other'

  bool get is3dScan {
    final lower = name.toLowerCase();
    return lower.endsWith('.stl') || lower.endsWith('.ply') || lower.endsWith('.obj');
  }

  factory LabCaseFile.fromJson(Map<String, dynamic> json) => LabCaseFile(
        path: json['path'] as String? ?? '',
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? 'scan',
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'kind': kind,
      };
}

/// One step in the history log of a lab case.
class LabCaseHistoryItem {
  const LabCaseHistoryItem({
    required this.stage,
    required this.at,
    this.note = '',
  });

  final String stage;
  final DateTime at;
  final String note;

  factory LabCaseHistoryItem.fromJson(Map<String, dynamic> json) => LabCaseHistoryItem(
        stage: json['stage'] as String? ?? '',
        at: DateTime.fromMillisecondsSinceEpoch(
          (json['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
        note: json['note'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'stage': stage,
        'at': at.millisecondsSinceEpoch,
        'note': note,
      };
}

/// One prosthodontic lab case for a patient.
class LabCase {
  const LabCase({
    required this.id,
    required this.patientId,
    required this.labContactId,
    required this.labName,
    required this.type,
    required this.teeth,
    required this.material,
    required this.shade,
    required this.shadeSystem,
    required this.margin,
    required this.notes,
    required this.due,
    required this.stage,
    required this.history,
    required this.files,
    required this.recordedAt,
    required this.record,
  });

  final String id;
  final String patientId;
  final String labContactId;
  final String labName;
  final String type;
  final List<String> teeth;
  final String material;
  final String shade;
  final String shadeSystem;
  final String margin;
  final String notes;
  final DateTime due;
  final LabCaseStage stage;
  final List<LabCaseHistoryItem> history;
  final List<LabCaseFile> files;
  final DateTime recordedAt;
  final DentalRecord record;

  bool isOverdue(DateTime now) {
    if (!stage.isOpen) return false;
    final endOfDueDay = DateTime(due.year, due.month, due.day, 23, 59, 59);
    return now.isAfter(endOfDueDay);
  }

  factory LabCase.fromRecord(DentalRecord r) {
    final rawHistory = r.data['history'] as List? ?? const [];
    final hist = rawHistory
        .map((h) => LabCaseHistoryItem.fromJson(Map<String, dynamic>.from(h as Map)))
        .toList();

    final rawFiles = r.data['files'] as List? ?? const [];
    final fls = rawFiles
        .map((f) => LabCaseFile.fromJson(Map<String, dynamic>.from(f as Map)))
        .toList();

    final rawTeeth = r.data['teeth'] as List? ?? const [];

    final dueMs = r.data['due'] as num?;
    final dueDate = dueMs != null
        ? DateTime.fromMillisecondsSinceEpoch(dueMs.toInt())
        : r.recordedAt.add(const Duration(days: 7));

    return LabCase(
      id: r.id,
      patientId: r.patientId,
      labContactId: r.str('labContactId'),
      labName: r.str('labName'),
      type: r.str('type').isNotEmpty ? r.str('type') : 'Crown',
      teeth: rawTeeth.map((e) => '$e').toList(),
      material: r.str('material').isNotEmpty ? r.str('material') : 'Zirconia',
      shade: r.str('shade').isNotEmpty ? r.str('shade') : 'A2',
      shadeSystem: r.str('shadeSystem').isNotEmpty ? r.str('shadeSystem') : 'VITA classical',
      margin: r.str('margin').isNotEmpty ? r.str('margin') : 'Chamfer',
      notes: r.str('notes'),
      due: dueDate,
      stage: LabCaseStage.fromName(r.str('stage')),
      history: hist,
      files: fls,
      recordedAt: r.recordedAt,
      record: r,
    );
  }

  Map<String, dynamic> toData() => {
        'labContactId': labContactId,
        'labName': labName,
        'type': type,
        'teeth': teeth,
        'material': material,
        'shade': shade,
        'shadeSystem': shadeSystem,
        'margin': margin,
        'notes': notes,
        'due': due.millisecondsSinceEpoch,
        'stage': stage.name,
        'history': history.map((h) => h.toJson()).toList(),
        'files': files.map((f) => f.toJson()).toList(),
      };
}

/// Provider for all lab cases clinic-wide.
final allLabCasesProvider = Provider<List<LabCase>>((ref) {
  final records = ref.watch(clinicRecordsProvider(RecKind.labCase)).value ??
      const <DentalRecord>[];
  return records.map(LabCase.fromRecord).toList()
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
});

/// Standard VITA classical shade guide tabs.
const vitaShades = [
  'A1', 'A2', 'A3', 'A3.5', 'A4',
  'B1', 'B2', 'B3', 'B4',
  'C1', 'C2', 'C3', 'C4',
  'D2', 'D3', 'D4',
  'Bleach 1', 'Bleach 2',
];

/// Common lab case restoration types.
const labCaseTypes = [
  'Crown',
  'Bridge',
  'Veneer',
  'Inlay/Onlay',
  'Implant crown',
  'Complete denture',
  'Partial denture',
  'Night guard',
  'Other',
];

/// Common dental laboratory materials.
const labMaterials = [
  'Zirconia',
  'E.max',
  'PFM',
  'Metal',
  'Acrylic',
  'Other',
];

/// Common prep margin designs.
const labMargins = [
  'Chamfer',
  'Shoulder',
  'Feather',
];
