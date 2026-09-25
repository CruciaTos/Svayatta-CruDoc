import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/data/models/dental_procedure_log_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/chart_legend.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_2d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_3d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_dialogs.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/tooth_detail_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/tooth_detail_view.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The patient's teeth as a realistic chart (or 3D jaws): what was found
/// and done, the plan, gums and canals as layers, adult or milk teeth.
/// Clicking a tooth opens it.
class ToothChartCard extends ConsumerStatefulWidget {
  const ToothChartCard({super.key, required this.patient});

  final Patient patient;

  @override
  ConsumerState<ToothChartCard> createState() => _ToothChartCardState();
}

class _ToothChartCardState extends ConsumerState<ToothChartCard> {
  bool _threeD = false;
  ChartLayer _layer = ChartLayer.dental;
  bool? _child;
  String? _selected;

  Patient get p => widget.patient;

  bool _defaultChild(ToothChartData data) {
    if (data.hasPrimary && !data.hasPermanent) return true;
    if (data.hasPermanent) return false;
    final age = DateTime.now().difference(p.dateOfBirth).inDays / 365.25;
    return age > 0 && age < 6;
  }

  Future<void> _open(String tooth) async {
    setState(() => _selected = tooth);
    await showToothDetail(context, patient: p, tooth: tooth);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final data = watchPatientChart(ref, p.id);
    final numbering =
        ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    final child = _child ?? _defaultChild(data);
    // 3D shows findings or the plan; the other layers are chart-only.
    final layer =
        _threeD && _layer != ChartLayer.plan ? ChartLayer.dental : _layer;

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
          counts.isEmpty
              ? 'No findings yet · click a tooth to open it'
              : counts.join(' · '),
          style: CruType.subhead.tabular.tint(c.label2),
        ),
      ],
    );
    final controls = Wrap(
      spacing: CruSpace.s8,
      runSpacing: CruSpace.s8,
      children: [
        CruSegmentedControl<ChartLayer>(
          semanticLabel: 'Show',
          segments: [
            for (final l in _threeD
                ? const [ChartLayer.dental, ChartLayer.plan]
                : ChartLayer.values)
              CruSegment(l, l.label),
          ],
          selected: layer,
          onChanged: (l) => setState(() => _layer = l),
        ),
        CruSegmentedControl<bool>(
          semanticLabel: 'View',
          segments: const [
            CruSegment(false, 'Chart'),
            CruSegment(true, '3D'),
          ],
          selected: _threeD,
          onChanged: (v) => setState(() => _threeD = v),
        ),
      ],
    );
    final perioDate = data.perioExam == null
        ? null
        : 'Perio exam ${DentalFormat.date(data.perioExam!.recordedAt)}';

    return CruCard(
      semanticLabel: 'Tooth chart',
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 780;
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
                        mode: layer.mode,
                        selected: _selected,
                        onSelect: (t) => setState(() => _selected = t),
                        onOpen: _open,
                        height:
                            (constraints.maxWidth * 0.62).clamp(380.0, 540.0),
                        numbering: numbering,
                      )
                    : ToothChart2D(
                        key: const ValueKey('2d'),
                        data: data,
                        child: child,
                        layer: layer,
                        selected: _selected,
                        onSelect: _open,
                        numbering: numbering,
                      ),
              ),
              if (!_threeD && layer.showsPerio && data.perioExam == null) ...[
                const SizedBox(height: CruSpace.s12),
                _PerioNotice(patient: p),
              ],
              if (_threeD && _selected != null) ...[
                const SizedBox(height: CruSpace.s12),
                _Peek(
                  tooth: _selected!,
                  visual: data.of(_selected!),
                  onOpen: () => _open(_selected!),
                ),
              ],
              const SizedBox(height: CruSpace.s14),
              Row(
                children: [
                  Expanded(
                    child: _threeD
                        ? _StateLegend(plan: layer == ChartLayer.plan)
                        : ChartLegend(
                            layer: layer,
                            trailing: layer.showsPerio ? perioDate : null,
                          ),
                  ),
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
            ],
          );
        },
      ),
    );
  }
}

/// Perio layer without an exam: say so and offer the perio chart.
class _PerioNotice extends StatelessWidget {
  const _PerioNotice({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s14,
        CruSpace.s10,
        CruSpace.s10,
        CruSpace.s10,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'No perio exam yet. Gum lines, pockets and bleeding show on '
              'the teeth once you chart one.',
              style: CruType.subhead.tint(c.label2),
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruCapsuleButton(
            label: 'Open perio chart',
            kind: CruCapsuleKind.surface,
            onPressed: () => openPerioChart(context, patient),
          ),
        ],
      ),
    );
  }
}

/// The tooth picked in 3D, and the way into it.
class _Peek extends StatelessWidget {
  const _Peek({
    required this.tooth,
    required this.visual,
    required this.onOpen,
  });

  final String tooth;
  final ToothVisual visual;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      children: [
        ToothBadge(tooth: tooth, state: visual.state),
        const SizedBox(width: CruSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DentalChart.name(tooth),
                style: CruType.callout.w600.tint(c.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                visual.detail(ChartLayer.all) ??
                    DentalChart.stateLabel(visual.state),
                style: CruType.subhead.tint(c.label2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: CruSpace.s12),
        CruCapsuleButton(label: 'Open tooth', onPressed: onOpen),
      ],
    );
  }
}

/// 3D colours: by state, or planned work.
class _StateLegend extends StatelessWidget {
  const _StateLegend({required this.plan});

  final bool plan;

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
                  side: ring
                      ? BorderSide(color: dot, width: 1.5)
                      : BorderSide.none,
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
      children: plan
          ? [
              item(c.accent, 'Work planned'),
              item(c.label3, 'Nothing planned', ring: true),
            ]
          : [
              item(c.enamelEdge, 'Healthy', ring: true),
              item(c.amberText, 'Needs care'),
              item(c.greenText, 'Treated'),
              item(c.label3, 'Missing'),
            ],
    );
  }
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
                              ?DentalChart.teethText(
                                shown[i].toothNumbers,
                                ref.watch(toothNumberingProvider).value ??
                                    ToothNumbering.fdi,
                              ),
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
