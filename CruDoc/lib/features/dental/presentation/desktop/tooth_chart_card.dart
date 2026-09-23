import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/data/models/dental_procedure_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_2d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_3d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_dialogs.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The patient's teeth: a 2D anatomical chart or 3D jaws (toggle),
/// Findings or Plan, adult or milk teeth. Picking a tooth shows its
/// history and what can be done: record a finding, log a procedure, add
/// it to the plan.
class ToothChartCard extends ConsumerStatefulWidget {
  const ToothChartCard({super.key, required this.patient});

  final Patient patient;

  @override
  ConsumerState<ToothChartCard> createState() => _ToothChartCardState();
}

class _ToothChartCardState extends ConsumerState<ToothChartCard> {
  bool _threeD = false;
  ChartMode _mode = ChartMode.findings;
  bool? _child;
  String? _selected;

  Patient get p => widget.patient;

  bool _defaultChild(ToothChartData data) {
    if (data.hasPrimary && !data.hasPermanent) return true;
    if (data.hasPermanent) return false;
    final age = DateTime.now().difference(p.dateOfBirth).inDays / 365.25;
    return age > 0 && age < 6;
  }

  Future<void> _record(String tooth, ToothChartEntryModel? latest) =>
      showToothFindingDialog(context, patient: p, tooth: tooth, latest: latest);

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final entries = ref.watch(patientToothChartProvider(p.id)).value ??
        const <ToothChartEntryModel>[];
    final plan = ref.watch(patientTreatmentPlanProvider(p.id)).value ??
        const <TreatmentPlanLineItemModel>[];
    final logs = ref.watch(patientProcedureLogProvider(p.id)).value ??
        const <DentalProcedureLogModel>[];
    final data = ToothChartData.from(entries, plan);
    final child = _child ?? _defaultChild(data);
    final latest = DentalChart.latest(entries);

    final counts = [
      if (data.count(ToothState.needsCare) > 0)
        '${data.count(ToothState.needsCare)} need care',
      if (data.count(ToothState.treated) > 0)
        '${data.count(ToothState.treated)} treated',
      if (data.count(ToothState.missing) > 0)
        '${data.count(ToothState.missing)} missing',
      if (data.plannedTeeth > 0) '${data.plannedTeeth} planned',
    ];

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text('Tooth chart', style: CruType.headline.tint(c.label)),
        ),
        const SizedBox(height: CruSpace.s2),
        Text(
          counts.isEmpty ? 'No findings yet' : counts.join(' · '),
          style: CruType.subhead.tabular.tint(c.label2),
        ),
      ],
    );
    final controls = Wrap(
      spacing: CruSpace.s8,
      runSpacing: CruSpace.s8,
      children: [
        CruSegmentedControl<ChartMode>(
          semanticLabel: 'Show',
          segments: const [
            CruSegment(ChartMode.findings, 'Findings'),
            CruSegment(ChartMode.plan, 'Plan'),
          ],
          selected: _mode,
          onChanged: (m) => setState(() => _mode = m),
        ),
        CruSegmentedControl<bool>(
          semanticLabel: 'View',
          segments: const [
            CruSegment(false, '2D'),
            CruSegment(true, '3D'),
          ],
          selected: _threeD,
          onChanged: (v) => setState(() => _threeD = v),
        ),
      ],
    );

    void select(String t) => setState(() => _selected = t);
    void open(String t) => _record(t, latest[t]);

    return CruCard(
      semanticLabel: 'Tooth chart',
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (narrow) ...[
                header,
                const SizedBox(height: CruSpace.s12),
                controls,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: header),
                    const SizedBox(width: CruSpace.s16),
                    controls,
                  ],
                ),
              const SizedBox(height: CruSpace.s16),
              AnimatedSwitcher(
                duration: CruMotion.of(context, CruMotion.fast),
                switchInCurve: CruMotion.curve,
                switchOutCurve: CruMotion.curve,
                child: _threeD
                    ? ToothChart3D(
                        key: const ValueKey('3d'),
                        data: data,
                        child: child,
                        mode: _mode,
                        selected: _selected,
                        onSelect: select,
                        onOpen: open,
                        height: (constraints.maxWidth * 0.62).clamp(380.0, 540.0),
                      )
                    : ToothChart2D(
                        key: const ValueKey('2d'),
                        data: data,
                        child: child,
                        mode: _mode,
                        selected: _selected,
                        onSelect: select,
                        onOpen: open,
                      ),
              ),
              const SizedBox(height: CruSpace.s12),
              Row(
                children: [
                  Expanded(child: _Legend(mode: _mode)),
                  const SizedBox(width: CruSpace.s12),
                  CruSegmentedControl<bool>(
                    semanticLabel: 'Teeth',
                    segments: const [
                      CruSegment(false, 'Adult'),
                      CruSegment(true, 'Milk teeth'),
                    ],
                    selected: child,
                    onChanged: (v) => setState(() {
                      _child = v;
                      _selected = null;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              const CruSeparator(),
              const SizedBox(height: CruSpace.s16),
              if (_selected == null)
                Row(
                  children: [
                    CruIcon(DentalIcons.tooth, size: 18, color: c.label3),
                    const SizedBox(width: CruSpace.s8),
                    Expanded(
                      child: Text(
                        'Pick a tooth to see its history, record a finding or '
                        'plan work. Double-click (or Enter) to record straight away.',
                        style: CruType.subhead.tint(c.label2),
                      ),
                    ),
                  ],
                )
              else
                _ToothPanel(
                  patient: p,
                  tooth: _selected!,
                  visual: data.of(_selected!),
                  history: entries
                      .where((e) => e.toothNumber == _selected && !e.isDeleted)
                      .toList(),
                  procedures: logs
                      .where((l) => l.toothNumbers.contains(_selected) && !l.isDeleted)
                      .toList(),
                  onRecord: () => _record(_selected!, latest[_selected!]),
                  onClose: () => setState(() => _selected = null),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.mode});

  final ChartMode mode;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    Widget item(Color dot, String label, {bool ring = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: ShapeDecoration(
                color: ring ? c.surface : dot,
                shape: CircleBorder(
                  side: ring ? BorderSide(color: dot, width: 1.5) : BorderSide.none,
                ),
              ),
            ),
            const SizedBox(width: CruSpace.s6),
            Text(label, style: CruType.caption.tint(c.label2)),
          ],
        );
    return Wrap(
      spacing: CruSpace.s14,
      runSpacing: CruSpace.s6,
      children: mode == ChartMode.plan
          ? [
              item(c.accent, 'Work planned'),
              item(c.label3, 'Nothing planned', ring: true),
            ]
          : [
              item(c.enamelEdge, 'Healthy', ring: true),
              item(c.amberText, 'Needs care'),
              item(c.greenText, 'Treated'),
              item(c.label3, 'Missing'),
              item(c.accent, 'Planned'),
            ],
    );
  }
}

/// The picked tooth: name, state, what's planned, the actions and its
/// history (findings and procedures, newest first).
class _ToothPanel extends StatefulWidget {
  const _ToothPanel({
    required this.patient,
    required this.tooth,
    required this.visual,
    required this.history,
    required this.procedures,
    required this.onRecord,
    required this.onClose,
  });

  final Patient patient;
  final String tooth;
  final ToothVisual visual;
  final List<ToothChartEntryModel> history;
  final List<DentalProcedureLogModel> procedures;
  final VoidCallback onRecord;
  final VoidCallback onClose;

  @override
  State<_ToothPanel> createState() => _ToothPanelState();
}

class _ToothPanelState extends State<_ToothPanel> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final v = widget.visual;
    final timeline = <(DateTime, String, String?, Widget?, VoidCallback?)>[
      for (final e in widget.history)
        (e.recordedAt, DentalChart.findingText(e), e.notes.trim().isEmpty ? null : e.notes.trim(), null, null),
      for (final l in widget.procedures)
        (
          l.performedAt,
          l.procedureName,
          _joined([l.materials ?? '', l.notes]),
          procedureStatusPill(c, l.status),
          () => showProcedureLogDialog(context, patient: widget.patient, existing: l),
        ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final shown = _all ? timeline : timeline.take(4).toList();
    final latestText = widget.history.isEmpty
        ? 'Nothing recorded yet'
        : DentalChart.findingText(
            ([...widget.history]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt))).first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ToothBadge(tooth: widget.tooth, state: v.state),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DentalChart.name(widget.tooth),
                    style: CruType.callout.w600.tint(c.label),
                  ),
                  const SizedBox(height: CruSpace.s4),
                  Wrap(
                    spacing: CruSpace.s8,
                    runSpacing: CruSpace.s4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      toothStatePill(c, v.state),
                      Text(latestText, style: CruType.subhead.tint(c.label2)),
                    ],
                  ),
                  if (v.isPlanned) ...[
                    const SizedBox(height: CruSpace.s4),
                    Text(
                      'Planned: ${v.planned.join(', ')}',
                      style: CruType.subhead.tint(c.accentText),
                    ),
                  ],
                ],
              ),
            ),
            CruIconButton(
              icon: CruIcons.close,
              size: CruSize.squareButton,
              iconSize: 16,
              semanticLabel: 'Close tooth ${widget.tooth}',
              tooltip: 'Close',
              onPressed: widget.onClose,
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s14),
        Wrap(
          spacing: CruSpace.s8,
          runSpacing: CruSpace.s8,
          children: [
            CruButton(label: 'Record finding', onPressed: widget.onRecord),
            CruButton(
              label: 'Log procedure',
              kind: CruButtonKind.secondary,
              onPressed: () => showProcedureLogDialog(context,
                  patient: widget.patient, teeth: [widget.tooth]),
            ),
            CruButton(
              label: 'Add to plan',
              kind: CruButtonKind.secondary,
              onPressed: () => showPlanItemDialog(context,
                  patient: widget.patient, teeth: [widget.tooth]),
            ),
          ],
        ),
        if (timeline.isNotEmpty) ...[
          const SizedBox(height: CruSpace.s16),
          Text('History', style: CruType.groupLabel.tint(c.label3)),
          const SizedBox(height: CruSpace.s6),
          for (final (date, title, note, pill, onTap) in shown)
            DentalListRow(
              semanticLabel: '$title, ${DentalFormat.date(date)}',
              onTap: onTap,
              minHeight: 44,
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      DentalFormat.date(date),
                      style: CruType.subhead.tabular.tint(c.label2),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: CruType.text.tint(c.label)),
                        if (note != null)
                          Text(
                            note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: CruType.subhead.tint(c.label2),
                          ),
                      ],
                    ),
                  ),
                  ?pill,
                ],
              ),
            ),
          if (timeline.length > 4)
            Padding(
              padding: const EdgeInsets.only(left: CruSpace.s12, top: CruSpace.s4),
              child: CruLink(
                label: _all ? 'Show fewer' : 'Show all ${timeline.length}',
                onPressed: () => setState(() => _all = !_all),
              ),
            ),
        ],
      ],
    );
  }
}

/// Non-empty parts joined with " · ", or null.
String? _joined(List<String> parts) {
  final kept = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  return kept.isEmpty ? null : kept.join(' · ');
}

/// The patient's procedures, newest first, with Log procedure.
class DentalProceduresCard extends ConsumerStatefulWidget {
  const DentalProceduresCard({super.key, required this.patient});

  final Patient patient;

  @override
  ConsumerState<DentalProceduresCard> createState() =>
      _DentalProceduresCardState();
}

class _DentalProceduresCardState extends ConsumerState<DentalProceduresCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final logs = [
      ...(ref.watch(patientProcedureLogProvider(widget.patient.id)).value ??
          const <DentalProcedureLogModel>[])
    ].where((l) => !l.isDeleted).toList()
      ..sort((a, b) => b.performedAt.compareTo(a.performedAt));
    final shown = _all ? logs : logs.take(5).toList();
    return CruCard(
      semanticLabel: 'Procedures',
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Procedures', style: CruType.headline.tint(c.label)),
                ),
              ),
              CruCapsuleButton(
                label: 'Log procedure',
                onPressed: () =>
                    showProcedureLogDialog(context, patient: widget.patient),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s8),
          if (logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
              child: Text(
                'Nothing logged yet. Completed procedures show on the tooth '
                'chart too.',
                style: CruType.subhead.tint(c.label2),
              ),
            )
          else ...[
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const CruSeparator(),
              DentalListRow(
                semanticLabel: shown[i].procedureName,
                minHeight: 52,
                onTap: () => showProcedureLogDialog(context,
                    patient: widget.patient, existing: shown[i]),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shown[i].procedureName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CruType.callout.tint(c.label),
                          ),
                          Text(
                            [
                              ?DentalChart.teethText(shown[i].toothNumbers),
                              DentalFormat.date(shown[i].performedAt),
                            ].join(' · '),
                            style: CruType.subhead.tabular.tint(c.label2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: CruSpace.s8),
                    procedureStatusPill(c, shown[i].status),
                  ],
                ),
              ),
            ],
            if (logs.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: CruSpace.s6, left: CruSpace.s12),
                child: CruLink(
                  label: _all ? 'Show fewer' : 'Show all ${logs.length}',
                  onPressed: () => setState(() => _all = !_all),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Dentists without a plan yet: say so and offer to start one.
class NoPlanCard extends StatelessWidget {
  const NoPlanCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'Treatment plan',
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Row(
        children: [
          const CruIconTile(icon: DentalIcons.plan, tone: CruTileTone.accent),
          const SizedBox(width: CruSpace.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Treatment plan', style: CruType.callout.w600.tint(c.label)),
                Text(
                  'No plan yet. List the procedures you recommend, with teeth '
                  'and fees.',
                  style: CruType.subhead.tint(c.label2),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruCapsuleButton(
            label: 'Create plan',
            onPressed: () => showTreatmentPlanDialog(context, patient: patient),
          ),
        ],
      ),
    );
  }
}
