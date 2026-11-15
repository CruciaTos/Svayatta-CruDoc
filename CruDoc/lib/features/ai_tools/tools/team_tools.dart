import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';

import '../core/ai_tool.dart';

const _maxItems = 15;

const _reportTypes = [
  'clinical_summary',
  'investigation_report',
  'fitness_note',
  'follow_up_summary',
  'referral_report',
];

List<AiTool> teamTools() => [
  AiTool(
    name: 'list_team_members',
    description:
        'List the people in this clinic: name, doctor or staff, role and '
        'whether active. No contact details.',
    group: AiToolGroup.team,
    risk: AiToolRisk.read,
    permission: ClinicPermission.team,
    run: (ctx, args) async {
      final members = await ctx.read(clinicMembersProvider.future);
      return AiToolResult.ok({
        'count': members.length,
        'members': [
          for (final m in members.take(_maxItems))
            {
              'id': m.uid,
              'name': m.name,
              'kind': m.kind.value,
              'role': m.roleName,
              'active': m.active,
              if (m.isOwner) 'owner': true,
              if (m.specialty.isNotEmpty) 'specialty': m.specialty,
            },
        ],
        if (members.length > _maxItems) 'truncated': true,
      });
    },
  ),
  AiTool(
    name: 'generate_medical_report',
    description:
        'Open the medical report sheet for a patient so the user can review '
        'and generate the PDF. The report text is written on screen; this '
        'tool does not create the PDF itself.',
    group: AiToolGroup.team,
    risk: AiToolRisk.confirm,
    permission: ClinicPermission.clinicalView,
    params: {
      'patientId': const AiParam.string('Patient id from find_patient.'),
      'patientName': const AiParam.string(
        'Patient name, shown on the confirm card.',
        required: false,
      ),
      'type': AiParam.enumOf(_reportTypes, 'Kind of report.'),
    },
    confirmText: (a) {
      final name = a['patientName'];
      final who = name is String && name.trim().isNotEmpty
          ? name.trim()
          : 'the patient';
      return 'Open the medical report for $who?';
    },
    run: (ctx, args) async {
      final id = args['patientId'];
      final type = args['type'];
      if (id is! String || id.isEmpty) {
        return AiToolResult.error('A patient id is needed.');
      }
      final nav = ctx.navigate;
      if (nav == null) {
        return AiToolResult.error('Cannot open screens from here.');
      }
      // The report sheet needs the screen (letterhead, preview), so the
      // caller maps `report:<type>` to MedicalReportGenerationSheet.
      await nav(
        'report:${type is String ? type : 'clinical_summary'}',
        args: {'patientId': id},
      );
      return AiToolResult.ok({
        'opened': true,
        'note': 'The report sheet is open for the user to finish.',
      }, summary: 'Opened the report sheet');
    },
  ),
];
