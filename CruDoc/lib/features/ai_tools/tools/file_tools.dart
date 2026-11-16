import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';

import '../core/ai_tool.dart';

const _maxItems = 15;

String? _str(Map<String, Object?> a, String k) {
  final v = a[k];
  return v is String && v.trim().isNotEmpty ? v.trim() : null;
}

Map<String, Object?> _fileRow(PatientFile f) => {
  'id': f.id,
  'name': f.name,
  'kind': f.kind.name,
  'patientId': f.patientId,
  'sizeKb': (f.sizeBytes / 1024).round(),
  'added': f.createdAt.toIso8601String(),
  if (f.teeth.isNotEmpty) 'teeth': f.teeth,
};

List<AiTool> fileTools() => [
  AiTool(
    name: 'list_patient_files',
    description:
        "List a patient's files and images, newest first (id, name, kind, "
        'date). Use open_file to show one.',
    group: AiToolGroup.files,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: {
      'patientId': const AiParam.string('Patient id from find_patient.'),
      'kind': AiParam.enumOf(
        [for (final k in FileKind.values) k.name],
        'Only this kind of file.',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final id = _str(args, 'patientId');
      if (id == null) return AiToolResult.error('A patient id is needed.');
      final files = await ctx.read(patientFilesProvider(id).future);
      final kind = _str(args, 'kind');
      final list = [
        for (final f in files)
          if (!f.isDeleted && (kind == null || f.kind.name == kind)) f,
      ];
      return AiToolResult.ok({
        'count': list.length,
        'files': [for (final f in list.take(_maxItems)) _fileRow(f)],
        if (list.length > _maxItems) 'truncated': true,
      });
    },
  ),
  AiTool(
    name: 'list_recent_files',
    description: 'List the most recently added files across all patients.',
    group: AiToolGroup.files,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: const {
      'limit': AiParam.integer(
        'How many (default 10, max 15).',
        required: false,
        min: 1,
        max: _maxItems,
      ),
    },
    run: (ctx, args) async {
      final n = ((args['limit'] as num?)?.toInt() ?? 10).clamp(1, _maxItems);
      final files = await ctx.read(recentFilesProvider.future);
      final list = [
        for (final f in files)
          if (!f.isDeleted) f,
      ];
      return AiToolResult.ok({
        'files': [for (final f in list.take(n)) _fileRow(f)],
      });
    },
  ),
  AiTool(
    name: 'open_file',
    description:
        'Open a file in the viewer on screen. Needs a file id from '
        'list_patient_files or list_recent_files.',
    group: AiToolGroup.files,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: const {'fileId': AiParam.string('File id.')},
    run: (ctx, args) async {
      final id = _str(args, 'fileId');
      if (id == null) return AiToolResult.error('A file id is needed.');
      final nav = ctx.navigate;
      if (nav == null) {
        return AiToolResult.error('Cannot open screens from here.');
      }
      // The caller maps the `file:<id>` target to the Files viewer.
      await nav('file:$id', args: {'fileId': id});
      return AiToolResult.ok({'opened': id}, summary: 'Opened the file');
    },
  ),
  AiTool(
    name: 'list_radiology_studies',
    description:
        'List radiology studies (X-rays, CBCT, DICOM), newest first. '
        'Optionally for one patient.',
    group: AiToolGroup.files,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: const {
      'patientId': AiParam.string('Only this patient.', required: false),
    },
    run: (ctx, args) async {
      final pid = _str(args, 'patientId');
      final all = await ctx.read(radStudiesProvider.future);
      final list = [
        for (final s in all)
          if (pid == null || s.patientId == pid) s,
      ]..sort((a, b) => b.studyDate.compareTo(a.studyDate));
      return AiToolResult.ok({
        'count': list.length,
        'studies': [
          for (final s in list.take(_maxItems))
            {
              'id': s.id,
              'patientId': s.patientId,
              'patientName': s.patientName,
              'modality': s.modality.label,
              'date': s.studyDate.toIso8601String(),
              'status': s.status.label,
              'priority': s.priority.label,
              if (s.description.isNotEmpty) 'description': s.description,
              if (s.critical) 'critical': true,
            },
        ],
        if (list.length > _maxItems) 'truncated': true,
      });
    },
  ),
  AiTool(
    name: 'list_radiology_reports',
    description:
        'List radiology reports (impression and status). Optionally for '
        'one patient or one status.',
    group: AiToolGroup.files,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: {
      'patientId': const AiParam.string('Only this patient.', required: false),
      'status': AiParam.enumOf(
        [for (final s in RadReportStatus.values) s.name],
        'Only reports in this state (finalised = signed off).',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final pid = _str(args, 'patientId');
      final status = _str(args, 'status');
      final all = await ctx.read(radReportsProvider.future);
      final list = [
        for (final r in all)
          if ((pid == null || r.patientId == pid) &&
              (status == null || r.status.name == status))
            r,
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      String clip(String s) => s.length > 200 ? '${s.substring(0, 200)}...' : s;
      return AiToolResult.ok({
        'count': list.length,
        'reports': [
          for (final r in list.take(_maxItems))
            {
              'id': r.id,
              'studyId': r.studyId,
              'patientId': r.patientId,
              if (r.title.isNotEmpty) 'title': r.title,
              'status': r.status.name,
              if (r.impression.isNotEmpty) 'impression': clip(r.impression),
              'updated': r.updatedAt.toIso8601String(),
            },
        ],
        if (list.length > _maxItems) 'truncated': true,
      });
    },
  ),
];
