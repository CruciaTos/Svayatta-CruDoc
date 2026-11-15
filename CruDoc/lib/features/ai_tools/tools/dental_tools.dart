import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/features/ai_tools/core/ai_tool.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_catalog_model.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/sterilization_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/chart_timeline.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/chart_session_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/perio_chart_screen.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_models.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_network.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_models.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';

const _uuid = Uuid();

const int _maxItems = 25;

const _adultTeeth = [
  '11', '12', '13', '14', '15', '16', '17', '18', //
  '21', '22', '23', '24', '25', '26', '27', '28',
  '31', '32', '33', '34', '35', '36', '37', '38',
  '41', '42', '43', '44', '45', '46', '47', '48',
];

const _allTeeth = [
  ..._adultTeeth,
  '51', '52', '53', '54', '55', //
  '61', '62', '63', '64', '65',
  '71', '72', '73', '74', '75',
  '81', '82', '83', '84', '85',
];

const _surfaceNames = [
  'mesial',
  'distal',
  'occlusal',
  'buccal',
  'lingual',
  'incisal',
  'cervical',
];

const _conditionNames = [
  'caries',
  'fractured',
  'missing',
  'unerupted',
  'impacted',
  'restored',
  'rootCanal',
  'boneLoss',
  'periapicalLesion',
];

const _perioSites = ['MB', 'B', 'DB', 'ML', 'L', 'DL'];

const _labStatuses = [
  'open',
  'overdue',
  'scanned',
  'sent',
  'design',
  'milling',
  'qc',
  'shipped',
  'received',
  'fitted',
  'remake',
];

String? _s(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _dateStr(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _cut(String s, [int max = 100]) =>
    s.length <= max ? s : '${s.substring(0, max)}...';

Future<String?> _patientName(AiToolContext ctx, String patientId) async {
  try {
    final p = await ctx.read(patientRepositoryProvider).getPatient(patientId);
    return p?.fullName.trim();
  } catch (_) {
    return null;
  }
}

List<Visit> _visitsOf(AiToolContext ctx, String patientId) =>
    ctx.read(patientSummaryProvider(patientId)).value?.visits ??
    const <Visit>[];

/// The visit a new chart change is saved in: the session the Charting screen
/// has loaded, else today's visit, else none (saved by date). Same rule as
/// `chartWriteVisit`, which needs a WidgetRef.
Visit? _writeVisit(
  AiToolContext ctx,
  String patientId,
  ChartTimeline timeline,
  List<Visit> visits,
) {
  final loaded = timeline.sessionOf(ctx.read(chartSessionProvider(patientId)));
  if (loaded != null) return loaded;
  final now = DateTime.now();
  for (final v in visits) {
    if (v.status == VisitStatus.cancelled) continue;
    if (_sameDay(v.scheduledStart, now)) return v;
  }
  return null;
}

Map<String, Object?> _entryJson(ToothChartEntryModel e) => {
  'entryId': e.id,
  'tooth': e.toothNumber,
  'finding': DentalChart.findingText(e),
  if (e.condition != null) 'condition': e.condition,
  if (e.treatment != null) 'treatment': e.treatment,
  if (DentalChart.surfaces(e.surface).isNotEmpty)
    'surfaces': [for (final s in DentalChart.surfaces(e.surface)) s.name],
  if (e.notes.trim().isNotEmpty) 'note': _cut(e.notes.trim()),
  'date': _dateStr(e.recordedAt),
};

Map<String, Object?> _planJson(TreatmentPlanLineItemModel i) => {
  'itemId': i.id,
  'procedure': i.procedureName,
  if (i.toothNumbers.isNotEmpty) 'teeth': i.toothNumbers,
  'fee': i.estimatedPrice,
  'status': i.status,
};

Future<DentalProcedureCatalogModel?> _catalogItem(
  AiToolContext ctx,
  String procedureId,
) async {
  final items = await ctx
      .read(dentalRepositoryProvider)
      .getProcedureCatalog(
        ctx.read(dentalDoctorIdProvider),
        includeArchived: true,
      );
  for (final c in items) {
    if (c.id == procedureId) return c;
  }
  return null;
}

void _refreshChart(AiToolContext ctx, String patientId) =>
    ctx.refresh(patientToothChartProvider(patientId));

void _refreshPlan(AiToolContext ctx, String patientId) {
  ctx.refresh(patientTreatmentPlanProvider(patientId));
  ctx.refresh(clinicTreatmentPlansProvider);
}

void _refreshProcedures(AiToolContext ctx, String patientId) =>
    ctx.refresh(patientProcedureLogProvider(patientId));

List<AiTool> dentalTools() => [
  AiTool(
    name: 'get_tooth_chart',
    description:
        'Reads a patient\'s tooth chart: the current finding on each charted '
        'tooth (FDI numbers), with entryIds. Pass tooth to also get that '
        'tooth\'s recent history.',
    group: AiToolGroup.dental,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: const {
      'patientId': AiParam.string('Patient ID from find_patient'),
      'tooth': AiParam.enumOf(
        _allTeeth,
        'One tooth (FDI) for its history',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final patientId = args['patientId'] as String;
      final tooth = _s(args['tooth']);
      final entries = await ctx
          .read(dentalRepositoryProvider)
          .getToothChartForPatient(patientId);
      if (tooth != null) {
        final history = entries.where((e) => e.toothNumber == tooth).toList();
        return AiToolResult.ok({
          'tooth': tooth,
          'name': DentalChart.name(tooth),
          'history': [for (final e in history.take(10)) _entryJson(e)],
          'count': history.length,
        });
      }
      final timeline = ChartTimeline(
        _visitsOf(ctx, patientId),
        entries,
        now: DateTime.now(),
      );
      final rows = timeline.latestAt(null).values.toList()
        ..sort((a, b) => a.toothNumber.compareTo(b.toothNumber));
      return AiToolResult.ok({
        'teethWithFindings': rows.length,
        'teeth': [for (final e in rows) _entryJson(e)],
      });
    },
  ),
  AiTool(
    name: 'add_tooth_finding',
    description:
        'Charts a finding on one tooth (FDI number): a condition, optionally '
        'with surfaces and a note. Saved in the patient\'s current visit.',
    group: AiToolGroup.dental,
    risk: AiToolRisk.write,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'patientId': AiParam.string('Patient ID from find_patient'),
      'tooth': AiParam.enumOf(_allTeeth, 'Tooth, FDI number'),
      'condition': AiParam.enumOf(_conditionNames, 'The finding'),
      'surfaces': AiParam.list(
        AiParam.enumOf(_surfaceNames, 'Surface'),
        'Surfaces involved',
        required: false,
      ),
      'note': AiParam.string('Free-text note', required: false),
    },
    run: (ctx, args) async {
      final patientId = args['patientId'] as String;
      final tooth = args['tooth'] as String;
      final condition = ToothCondition.fromString(args['condition'] as String?);
      if (condition == null) return AiToolResult.error('Unknown condition');
      final surfaces = [
        for (final s in (args['surfaces'] as List?) ?? const [])
          ?ToothSurface.fromString(s as String?),
      ];
      final repo = ctx.read(dentalRepositoryProvider);
      final entries = await repo.getToothChartForPatient(patientId);
      final visits = _visitsOf(ctx, patientId);
      final timeline = ChartTimeline(visits, entries, now: DateTime.now());
      final visit = _writeVisit(ctx, patientId, timeline, visits);
      final now = DateTime.now();
      final entry = ToothChartEntryModel(
        id: _uuid.v4(),
        doctorId: ctx.read(dentalDoctorIdProvider),
        patientId: patientId,
        toothNumber: tooth,
        condition: condition.name,
        surface: DentalChart.storeSurfaces(surfaces),
        visitId: visit?.id,
        baseEntryId: timeline.latestAt(visit?.id)[tooth]?.id ?? '',
        notes: _s(args['note']) ?? '',
        recordedAt: visit?.scheduledStart ?? now,
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pending',
      );
      await repo.saveToothChartEntry(entry);
      _refreshChart(ctx, patientId);
      final who = await _patientName(ctx, patientId);
      return AiToolResult.ok(
        {'entryId': entry.id, 'tooth': tooth, 'finding': DentalChart.findingText(entry)},
        summary:
            'Charted ${DentalChart.findingText(entry)} on tooth $tooth'
            '${who == null ? '' : ' for $who'}',
        undo: () async {
          await repo.deleteToothChartEntry(entry.id);
          _refreshChart(ctx, patientId);
        },
      );
    },
  ),
  AiTool(
    name: 'remove_tooth_finding',
    description:
        'Removes one tooth-chart finding (soft delete). Needs the entryId '
        'from get_tooth_chart and the patientId.',
    group: AiToolGroup.dental,
    risk: AiToolRisk.confirm,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'entryId': AiParam.string('Entry ID from get_tooth_chart'),
      'patientId': AiParam.string('Patient ID the entry belongs to'),
    },
    confirmText: (_) => 'Remove a finding from this patient\'s tooth chart?',
    run: (ctx, args) async {
      final repo = ctx.read(dentalRepositoryProvider);
      final entryId = args['entryId'] as String;
      final entries = await repo.getToothChartForPatient(
        args['patientId'] as String,
      );
      ToothChartEntryModel? entry;
      for (final e in entries) {
        if (e.id == entryId) entry = e;
      }
      if (entry == null) {
        return AiToolResult.error('No such chart entry for this patient');
      }
      await repo.deleteToothChartEntry(entryId);
      _refreshChart(ctx, args['patientId'] as String);
      return AiToolResult.ok(
        {'removed': _entryJson(entry)},
        summary:
            'Removed ${DentalChart.findingText(entry)} from tooth '
            '${entry.toothNumber}',
      );
    },
  ),
  AiTool(
    name: 'list_procedure_catalog',
    description:
        'Lists the clinic\'s dental procedures with IDs and default fees. '
        'Use to find the procedureId for log_procedure or '
        'add_treatment_plan_item.',
    group: AiToolGroup.dental,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: const {
      'query': AiParam.string(
        'Part of a name, code or category',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final q = _s(args['query'])?.toLowerCase();
      final all = await ctx
          .read(dentalRepositoryProvider)
          .getProcedureCatalog(ctx.read(dentalDoctorIdProvider));
      final hits = [
        for (final c in all)
          if (q == null ||
              c.name.toLowerCase().contains(q) ||
              c.code.toLowerCase().contains(q) ||
              c.category.toLowerCase().contains(q))
            c,
      ];
      return AiToolResult.ok({
        'count': hits.length,
        'procedures': [
          for (final c in hits.take(_maxItems))
            {
              'procedureId': c.id,
              'code': c.code,
              'name': c.name,
              'category': c.category,
              if (c.defaultPrice != null) 'defaultFee': c.defaultPrice,
              'needsTooth': c.requiresToothSelection,
            },
        ],
      });
    },
  ),
  AiTool(
    name: 'get_treatment_plan',
    description:
        'Reads a patient\'s treatment plan: each item with its teeth, fee '
        'and status (proposed, accepted, declined, invoiced).',
    group: AiToolGroup.dental,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: const {'patientId': AiParam.string('Patient ID from find_patient')},
    run: (ctx, args) async {
      final items = await ctx
          .read(dentalRepositoryProvider)
          .getTreatmentPlanLineItems(args['patientId'] as String);
      final open = items.where((i) => i.status != 'declined');
      final total = open.fold<double>(0, (s, i) => s + i.estimatedPrice);
      return AiToolResult.ok({
        'count': items.length,
        'totalExcludingDeclined': total,
        'items': [for (final i in items.take(_maxItems)) _planJson(i)],
      });
    },
  ),
  AiTool(
    name: 'add_treatment_plan_item',
    description:
        'Adds a procedure to a patient\'s treatment plan as "proposed". Take '
        'procedureId from list_procedure_catalog. Fee defaults to the '
        'catalog fee.',
    group: AiToolGroup.dental,
    risk: AiToolRisk.write,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'patientId': AiParam.string('Patient ID from find_patient'),
      'procedureId': AiParam.string('Procedure ID from list_procedure_catalog'),
      'tooth': AiParam.enumOf(_allTeeth, 'Tooth, FDI', required: false),
      'fee': AiParam.number('Fee in rupees', required: false, min: 0),
    },
    run: (ctx, args) async {
      final patientId = args['patientId'] as String;
      final cat = await _catalogItem(ctx, args['procedureId'] as String);
      if (cat == null) return AiToolResult.error('No such procedure');
      final tooth = _s(args['tooth']);
      if (cat.requiresToothSelection && tooth == null) {
        return AiToolResult.error('${cat.name} needs a tooth number');
      }
      final repo = ctx.read(dentalRepositoryProvider);
      final existing = await repo.getTreatmentPlanLineItems(patientId);
      final planId = existing.isEmpty
          ? _uuid.v4()
          : existing.first.treatmentPlanId;
      final nextSeq = existing.isEmpty
          ? 1
          : existing.map((i) => i.sequence).reduce((a, b) => a > b ? a : b) + 1;
      final now = DateTime.now();
      final item = TreatmentPlanLineItemModel(
        id: _uuid.v4(),
        doctorId: ctx.read(dentalDoctorIdProvider),
        patientId: patientId,
        treatmentPlanId: planId,
        procedureCatalogId: cat.id,
        procedureName: cat.name,
        toothNumbers: tooth == null ? const [] : [tooth],
        estimatedPrice: (args['fee'] as num?)?.toDouble() ?? cat.defaultPrice ?? 0,
        sequence: nextSeq,
        status: TreatmentPlanItemStatus.proposed.code,
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pending',
      );
      await repo.saveTreatmentPlanLineItem(item);
      _refreshPlan(ctx, patientId);
      final who = await _patientName(ctx, patientId);
      return AiToolResult.ok(
        _planJson(item),
        summary:
            'Added ${cat.name}${tooth == null ? '' : ' on tooth $tooth'} to '
            '${who ?? 'the'} treatment plan',
        undo: () async {
          await repo.deleteTreatmentPlanLineItem(item.id);
          _refreshPlan(ctx, patientId);
        },
      );
    },
  ),
  AiTool(
    name: 'set_treatment_item_status',
    description:
        'Changes a treatment plan item to proposed, accepted or declined '
        '(e.g. the patient agreed or refused). Items already invoiced cannot '
        'be changed here. Take itemId from get_treatment_plan.',
    group: AiToolGroup.dental,
    risk: AiToolRisk.write,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'itemId': AiParam.string('Plan item ID from get_treatment_plan'),
      'status': AiParam.enumOf(['proposed', 'accepted', 'declined'], 'New status'),
    },
    run: (ctx, args) async {
      final repo = ctx.read(dentalRepositoryProvider);
      final itemId = args['itemId'] as String;
      final status = args['status'] as String;
      final all = await repo.getAllTreatmentPlanLineItems(
        ctx.read(dentalDoctorIdProvider),
      );
      TreatmentPlanLineItemModel? item;
      for (final i in all) {
        if (i.id == itemId) item = i;
      }
      if (item == null) return AiToolResult.error('No such plan item');
      final previous = item.status;
      if (previous == TreatmentPlanItemStatus.invoiced.code) {
        return AiToolResult.error('That item is already invoiced');
      }
      await repo.updateTreatmentPlanLineItemStatus(itemId, status);
      final planPatientId = item.patientId;
      _refreshPlan(ctx, planPatientId);
      return AiToolResult.ok(
        {'itemId': itemId, 'status': status, 'previousStatus': previous},
        summary: '${item.procedureName} marked $status',
        undo: () async {
          await repo.updateTreatmentPlanLineItemStatus(itemId, previous);
          _refreshPlan(ctx, planPatientId);
        },
      );
    },
  ),
  AiTool(
    name: 'log_procedure',
    description:
        'Records that a procedure was COMPLETED today for a patient (and puts '
        'its result on the tooth chart). Only use when the doctor says it was '
        'done. Take procedureId from list_procedure_catalog.',
    group: AiToolGroup.dental,
    risk: AiToolRisk.write,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'patientId': AiParam.string('Patient ID from find_patient'),
      'procedureId': AiParam.string('Procedure ID from list_procedure_catalog'),
      'tooth': AiParam.enumOf(_allTeeth, 'Tooth, FDI', required: false),
      'note': AiParam.string('Free-text note', required: false),
    },
    run: (ctx, args) async {
      final patientId = args['patientId'] as String;
      final cat = await _catalogItem(ctx, args['procedureId'] as String);
      if (cat == null) return AiToolResult.error('No such procedure');
      final tooth = _s(args['tooth']);
      if (cat.requiresToothSelection && tooth == null) {
        return AiToolResult.error('${cat.name} needs a tooth number');
      }
      final repo = ctx.read(dentalRepositoryProvider);
      final doctorId = ctx.read(dentalDoctorIdProvider);
      final entries = await repo.getToothChartForPatient(patientId);
      final visits = _visitsOf(ctx, patientId);
      final timeline = ChartTimeline(visits, entries, now: DateTime.now());
      final visit = _writeVisit(ctx, patientId, timeline, visits);
      final now = DateTime.now();
      final log = DentalProcedureLogModel(
        id: _uuid.v4(),
        doctorId: doctorId,
        patientId: patientId,
        visitId: visit?.id,
        procedureCatalogId: cat.id,
        procedureName: cat.name,
        toothNumbers: tooth == null ? const [] : [tooth],
        status: DentalProcedureStatus.completed.code,
        notes: _s(args['note']) ?? '',
        performedAt: now,
        createdAt: now,
        updatedAt: now,
        syncStatus: 'pending',
      );
      await repo.saveProcedureLog(log);

      // A completed procedure shows on the tooth chart, as in the app.
      final chartIds = <String>[];
      final t = DentalChart.treatmentForProcedure(cat.code, cat.name);
      if (t != null && tooth != null) {
        final entry = ToothChartEntryModel(
          id: _uuid.v4(),
          doctorId: doctorId,
          patientId: patientId,
          toothNumber: tooth,
          treatment: t.name,
          condition: t == ToothTreatment.extraction
              ? ToothCondition.missing.name
              : null,
          procedureLogId: log.id,
          visitId: visit?.id,
          baseEntryId: timeline.latestAt(visit?.id)[tooth]?.id ?? '',
          notes: cat.name,
          recordedAt: now,
          createdAt: now,
          updatedAt: now,
          syncStatus: 'pending',
        );
        await repo.saveToothChartEntry(entry);
        chartIds.add(entry.id);
      }
      _refreshProcedures(ctx, patientId);
      _refreshChart(ctx, patientId);
      final who = await _patientName(ctx, patientId);
      return AiToolResult.ok(
        {
          'logId': log.id,
          'procedure': cat.name,
          'tooth': ?tooth,
          'chartUpdated': chartIds.isNotEmpty,
        },
        summary:
            'Logged ${cat.name}${tooth == null ? '' : ' on tooth $tooth'}'
            '${who == null ? '' : ' for $who'}',
        undo: () async {
          await repo.deleteProcedureLog(log.id);
          for (final id in chartIds) {
            await repo.deleteToothChartEntry(id);
          }
          _refreshProcedures(ctx, patientId);
          _refreshChart(ctx, patientId);
        },
      );
    },
  ),
  AiTool(
    name: 'record_perio',
    description:
        'Records one periodontal reading (probing depth in mm, optional '
        'recession, bleeding, pus) at one site of one adult tooth, in the '
        'patient\'s perio exam for today (a new exam is started if there is '
        'none today). Sites: MB, B, DB (buccal side), ML, L, DL (lingual).',
    group: AiToolGroup.dental,
    risk: AiToolRisk.write,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'patientId': AiParam.string('Patient ID from find_patient'),
      'tooth': AiParam.enumOf(_adultTeeth, 'Adult tooth, FDI'),
      'site': AiParam.enumOf(_perioSites, 'Site on the tooth'),
      'depth': AiParam.integer('Probing depth in mm', min: 0, max: 20),
      'recession': AiParam.integer(
        'Recession in mm (negative if the gum margin is above the CEJ)',
        required: false,
        min: -5,
        max: 20,
      ),
      'bleeding': AiParam.boolean('Bleeding on probing', required: false),
      'suppuration': AiParam.boolean('Pus at the site', required: false),
    },
    run: (ctx, args) async {
      final patientId = args['patientId'] as String;
      final tooth = args['tooth'] as String;
      final site = _perioSites.indexOf(args['site'] as String);
      final repo = ctx.read(dentalRecordsRepoProvider);
      final doctorId = ctx.read(dentalDoctorIdProvider);
      final exams = await repo.forPatient(doctorId, patientId, RecKind.perio);
      final now = DateTime.now();
      final today = exams.isNotEmpty && _sameDay(exams.first.recordedAt, now)
          ? exams.first
          : null;

      final teethMap = <String, dynamic>{};
      final source = today ?? (exams.isEmpty ? null : exams.first);
      final raw = source?.data['teeth'];
      if (raw is Map) {
        for (final e in raw.entries) {
          // A new exam only carries over teeth that are missing.
          if (today != null || PerioTooth.fromJson(e.value).missing) {
            teethMap['${e.key}'] = e.value;
          }
        }
      }
      final pt = PerioTooth.fromJson(teethMap[tooth]);
      if (pt.missing) {
        return AiToolResult.error('Tooth $tooth is marked missing in the exam');
      }
      pt.pd[site] = args['depth'] as int;
      final rec = args['recession'] as int?;
      if (rec != null) pt.rec[site] = rec;
      final bleeding = args['bleeding'] as bool?;
      if (bleeding != null) pt.bop[site] = bleeding;
      final sup = args['suppuration'] as bool?;
      if (sup != null) pt.sup[site] = sup;
      teethMap[tooth] = pt.toJson();

      final saved = today != null
          ? today.copyWith(data: {...today.data, 'teeth': teethMap})
          : DentalRecord.create(patientId, RecKind.perio, {
              'teeth': teethMap,
              'plaque': <String, dynamic>{},
              'notes': '',
            }, at: now);
      await repo.save(doctorId, saved);
      final who = await _patientName(ctx, patientId);
      return AiToolResult.ok(
        {
          'examId': saved.id,
          'newExam': today == null,
          'tooth': tooth,
          'site': args['site'],
          'depth': args['depth'],
        },
        summary:
            'Recorded ${args['depth']} mm at ${args['site']} of tooth $tooth'
            '${who == null ? '' : ' for $who'}',
        undo: () =>
            today != null ? repo.save(doctorId, today) : repo.delete(saved.id),
      );
    },
  ),
  AiTool(
    name: 'log_sterilization',
    description:
        'Logs one autoclave sterilisation cycle (done now). Cycle number '
        'defaults to the next one for that autoclave.',
    group: AiToolGroup.dental,
    risk: AiToolRisk.write,
    permission: ClinicPermission.inventory,
    params: const {
      'load': AiParam.string('What was in the load, e.g. "Surgical kit x3"'),
      'result': AiParam.enumOf(['pass', 'fail', 'incomplete'], 'Cycle result'),
      'cycle': AiParam.integer('Cycle number', required: false, min: 1),
      'autoclave': AiParam.string('Autoclave name', required: false),
      'operator': AiParam.string(
        'Who ran it (defaults to the signed-in person)',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final repo = ctx.read(dentalRepositoryProvider);
      final doctorId = ctx.read(dentalDoctorIdProvider);
      final me = ctx.read(doctorIdentityProvider).fullName ?? '';
      final machine = _s(args['autoclave']) ?? '';
      var cycle = args['cycle'] as int?;
      if (cycle == null) {
        final logs = await repo.getSterilizationLogs(doctorId);
        var top = 0;
        for (final l in logs) {
          if (l.autoclaveName.trim().toLowerCase() == machine.toLowerCase() &&
              l.cycleNumber > top) {
            top = l.cycleNumber;
          }
        }
        cycle = top + 1;
      }
      final now = DateTime.now();
      final log = SterilizationLogModel(
        id: _uuid.v4(),
        doctorId: doctorId,
        cycleDate: now,
        operatorName: _s(args['operator']) ?? me,
        loadDescription: args['load'] as String,
        result: args['result'] as String,
        createdAt: now,
        updatedAt: now,
        autoclaveName: machine,
        cycleNumber: cycle,
        createdBy: me,
        syncStatus: 'pending',
      );
      await repo.saveSterilizationLog(log);
      ctx.refresh(clinicSterilizationProvider);
      return AiToolResult.ok(
        {'logId': log.id, 'cycle': cycle, 'result': log.result},
        summary: 'Logged sterilisation cycle $cycle (${log.result})',
        undo: () async {
          await repo.saveSterilizationLog(
            log.copyWith(
              isDeleted: true,
              updatedAt: DateTime.now(),
              syncStatus: 'pending',
            ),
          );
          ctx.refresh(clinicSterilizationProvider);
        },
      );
    },
  ),
  AiTool(
    name: 'list_referrals',
    description:
        'Lists referrals between CruDoc doctors: incoming (sent to this '
        'clinic) or outgoing (sent by this clinic), newest first.',
    group: AiToolGroup.dental,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: const {
      'direction': AiParam.enumOf(['incoming', 'outgoing'], 'Which list'),
    },
    run: (ctx, args) async {
      final incoming = args['direction'] == 'incoming';
      final shares = await ctx.read(
        (incoming ? incomingSharesProvider : outgoingSharesProvider).future,
      );
      final sorted = [...shares]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return AiToolResult.ok({
        'count': sorted.length,
        'referrals': [
          for (final s in sorted.take(15))
            {
              'referralId': s.id,
              (incoming ? 'from' : 'to'): incoming
                  ? s.senderName
                  : s.recipientName,
              'patientName': s.patientName,
              'status': s.status.label,
              'urgency': s.urgency.name,
              if (s.teeth.isNotEmpty) 'teeth': s.teeth,
              if (s.reason.trim().isNotEmpty) 'reason': _cut(s.reason.trim()),
              'date': _dateStr(s.createdAt),
            },
        ],
      });
    },
  ),
  AiTool(
    name: 'list_lab_cases',
    description:
        'Lists dental lab cases (crowns, bridges, dentures...) with stage and '
        'due date, soonest due first. status: open (not yet fitted), overdue, '
        'or one stage.',
    group: AiToolGroup.dental,
    risk: AiToolRisk.read,
    permission: ClinicPermission.clinicalView,
    params: const {
      'status': AiParam.enumOf(_labStatuses, 'Filter', required: false),
    },
    run: (ctx, args) async {
      final status = _s(args['status']);
      final records = await ctx
          .read(dentalRecordsRepoProvider)
          .all(ctx.read(dentalDoctorIdProvider), RecKind.labCase);
      final now = DateTime.now();
      final cases = [
        for (final r in records)
          if (r.patientId.isNotEmpty) LabCase.fromRecord(r),
      ].where((c) {
        return switch (status) {
          null => true,
          'open' => c.stage.isOpen,
          'overdue' => c.isOverdue(now),
          _ => c.stage.name == status,
        };
      }).toList()..sort((a, b) => a.due.compareTo(b.due));
      return AiToolResult.ok({
        'count': cases.length,
        'cases': [
          for (final c in cases.take(_maxItems))
            {
              'labCaseId': c.id,
              'patientId': c.patientId,
              'type': c.type,
              if (c.teeth.isNotEmpty) 'teeth': c.teeth,
              if (c.labName.isNotEmpty) 'lab': c.labName,
              'stage': c.stage.name,
              'due': _dateStr(c.due),
              'overdue': c.isOverdue(now),
            },
        ],
      });
    },
  ),
  AiTool(
    name: 'create_lab_case',
    description:
        'Creates a new dental lab case (a lab prescription) for a patient, at '
        'stage "scanned". lab is the lab\'s name.',
    group: AiToolGroup.dental,
    risk: AiToolRisk.write,
    permission: ClinicPermission.clinicalEdit,
    params: const {
      'patientId': AiParam.string('Patient ID from find_patient'),
      'type': AiParam.enumOf(labCaseTypes, 'What the lab will make'),
      'lab': AiParam.string('Lab name'),
      'due': AiParam.date('Date it is due back'),
      'tooth': AiParam.enumOf(_allTeeth, 'Tooth, FDI', required: false),
      'shade': AiParam.string('Shade, e.g. A2', required: false),
      'note': AiParam.string('Note for the lab', required: false),
    },
    run: (ctx, args) async {
      final patientId = args['patientId'] as String;
      final labName = args['lab'] as String;
      final due = DateTime.parse(args['due'] as String);
      final tooth = _s(args['tooth']);
      final repo = ctx.read(dentalRecordsRepoProvider);
      final doctorId = ctx.read(dentalDoctorIdProvider);

      // Link to a saved lab contact when exactly one matches the name.
      final contacts = [
        for (final r in await repo.all(doctorId, RecKind.referralContact))
          ReferralContact.fromRecord(r),
      ];
      final wanted = labName.toLowerCase();
      final matches = [
        for (final c in contacts)
          if (c.name.toLowerCase().contains(wanted) ||
              wanted.contains(c.name.toLowerCase()))
            if (c.name.trim().isNotEmpty) c,
      ];
      final contact = matches.length == 1 ? matches.first : null;

      final now = DateTime.now();
      final record = DentalRecord.create(patientId, RecKind.labCase, {
        'labContactId': contact?.id ?? '',
        'labName': contact?.name ?? labName,
        'type': args['type'],
        'teeth': tooth == null ? <String>[] : [tooth],
        'material': '',
        'shade': _s(args['shade']) ?? '',
        'shadeSystem': 'VITA classical',
        'margin': '',
        'notes': _s(args['note']) ?? '',
        'due': due.millisecondsSinceEpoch,
        'stage': LabCaseStage.scanned.name,
        'history': [
          {
            'stage': LabCaseStage.scanned.name,
            'at': now.millisecondsSinceEpoch,
            'note': 'Lab case created',
          },
        ],
        'files': <Map<String, dynamic>>[],
      }, at: now);
      await repo.save(doctorId, record);
      final who = await _patientName(ctx, patientId);
      return AiToolResult.ok(
        {
          'labCaseId': record.id,
          'type': args['type'],
          'lab': contact?.name ?? labName,
          'due': args['due'],
        },
        summary:
            'Created ${args['type']} lab case${who == null ? '' : ' for $who'}'
            ', due ${args['due']}',
        undo: () => repo.delete(record.id),
      );
    },
  ),
];
