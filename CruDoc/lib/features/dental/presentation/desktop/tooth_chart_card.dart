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
import 'package:doctor_management_app/features/dental/presentation/desktop/charting_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/tooth_detail_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/tooth_detail_view.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens the patient's Charting on its Teeth tab.
Future<void> openToothChart(BuildContext context, Patient patient) =>
    openCharting(context, patient);

/// "3 need care · 4 treated · 1 missing · 2 planned"; empty when nothing
/// is charted.
List<String> toothChartCounts(ToothChartData data) => [
  if (data.count(ToothState.needsCare) > 0)
    '${data.count(ToothState.needsCare)} need care',
  if (data.count(ToothState.treated) > 0)
    '${data.count(ToothState.treated)} treated',
  if (data.count(ToothState.missing) > 0)
    '${data.count(ToothState.missing)} missing',
  if (data.plannedTeeth > 0) '${data.plannedTeeth} planned',
];

/// Milk teeth first: only milk teeth charted, or nothing charted and the
/// patient is under six.
bool defaultMilkTeeth(ToothChartData data, Patient p) {
  if (data.hasPrimary && !data.hasPermanent) return true;
  if (data.hasPermanent) return false;
  final age = DateTime.now().difference(p.dateOfBirth).inDays / 365.25;
  return age > 0 && age < 6;
}

/// Charting on the Clinical tab: the biting surfaces as a small map of
/// what was found, done and planned, and pills for the gums and root
/// canals that open those tabs. The card opens Charting on Teeth.
class ToothChartPreviewCard extends ConsumerWidget {
  const ToothChartPreviewCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final data = watchPatientChart(ref, patient.id);
    final numbering =
        ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    final counts = toothChartCounts(data);
    void open([ChartingTab tab = ChartingTab.teeth]) =>
        openCharting(context, patient, tab: tab);
    final exam = data.perioExam;
    final ongoing = data.teeth
        .where((t) => t.endo != null && !t.endo!.obturated)
        .length;
    final canals = data.teeth.where((t) => t.endo != null).length;
    Widget pill(String text, Color fill, Color ink, ChartingTab tab) =>
        CruPressable(
          onTap: () => open(tab),
          scaleOnPress: false,
          semanticLabel: 'Open $text',
          builder: (context, hovered) =>
              CruPill(text: text, background: fill, foreground: ink),
        );
    return CruPressable(
      onTap: open,
      scaleOnPress: false,
      semanticLabel: 'Open the tooth chart',
      builder: (context, hovered) => CruCard(
        semanticLabel: 'Tooth chart',
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Charting',
                          style: CruType.headline.tint(c.label),
                        ),
                      ),
                      const SizedBox(height: CruSpace.s2),
                      Text(
                        counts.isEmpty
                            ? 'Nothing charted yet'
                            : counts.join(' · '),
                        style: CruType.subhead.tabular.tint(c.label2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CruSpace.s12),
                CruLink(label: 'Open charting', onPressed: open),
              ],
            ),
            const SizedBox(height: CruSpace.s12),
            Wrap(
              spacing: CruSpace.s6,
              runSpacing: CruSpace.s6,
              children: [
                pill(
                  exam == null
                      ? 'No perio exam'
                      : 'Perio ${DentalFormat.shortDate(exam.recordedAt)}',
                  c.inset,
                  exam == null ? c.label2 : c.label,
                  ChartingTab.perio,
                ),
                if (canals > 0)
                  ongoing > 0
                      ? pill(
                          '$ongoing root canal${ongoing == 1 ? '' : 's'} '
                          'in progress',
                          c.amberTint,
                          c.amberText,
                          ChartingTab.rootCanals,
                        )
                      : pill(
                          '$canals root canal${canals == 1 ? '' : 's'}',
                          c.inset,
                          c.label,
                          ChartingTab.rootCanals,
                        ),
              ],
            ),
            const SizedBox(height: CruSpace.s16),
            // A picture here: the teeth answer on the full chart.
            IgnorePointer(
              child: ToothChart2D(
                data: data,
                child: defaultMilkTeeth(data, patient),
                selected: null,
                onSelect: (_) {},
                rows: ChartRows.occlusal,
                numbering: numbering,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The patient's teeth as a realistic chart (or 3D jaws): what was found
/// and done, the plan, gums and canals as layers, adult or milk teeth.
/// Clicking a tooth opens it.
class ToothChartCard extends ConsumerStatefulWidget {
  const ToothChartCard({
    super.key,
    required this.patient,
    this.fullScreen = false,
  });

  final Patient patient;

  /// On Charting's Teeth tab: the toolbar carries the counts, and the
  /// teeth grow with the window.
  final bool fullScreen;

  @override
  ConsumerState<ToothChartCard> createState() => _ToothChartCardState();
}

class _ToothChartCardState extends ConsumerState<ToothChartCard> {
  bool _threeD = false;
  ChartLayer _layer = ChartLayer.dental;
  bool? _child;
  String? _selected;

  Patient get p => widget.patient;

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
    final child = _child ?? defaultMilkTeeth(data, p);
    // 3D shows findings or the plan; the other layers are chart-only.
    final layer = _threeD && _layer != ChartLayer.plan
        ? ChartLayer.dental
        : _layer;

    final counts = toothChartCounts(data);

    final header = widget.fullScreen
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Tooth chart',
                  style: CruType.headline.tint(c.label),
                ),
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
            for (final l
                in _threeD
                    ? const [ChartLayer.dental, ChartLayer.plan]
                    : ChartLayer.values)
              CruSegment(l, l.label),
          ],
          selected: layer,
          onChanged: (l) => setState(() => _layer = l),
        ),
        CruSegmentedControl<bool>(
          semanticLabel: 'View',
          segments: const [CruSegment(false, 'Chart'), CruSegment(true, '3D')],
          selected: _threeD,
          onChanged: (v) => setState(() => _threeD = v),
        ),
      ],
    );
    final perioDate = data.perioExam == null
        ? null
        : 'Perio exam ${DentalFormat.date(data.perioExam!.recordedAt)}';

    // Phones: thinner sides so the teeth get the width.
    final phone = MediaQuery.sizeOf(context).width < 600;
    final teeth = CruSegmentedControl<bool>(
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
    );
    final legend = _threeD
        ? _StateLegend(plan: layer == ChartLayer.plan)
        : ChartLegend(
            layer: layer,
            trailing: layer.showsPerio ? perioDate : null,
          );
    return CruCard(
      semanticLabel: 'Tooth chart',
      padding: phone
          ? const EdgeInsets.fromLTRB(12, 20, 12, 16)
          : const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 780;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (narrow) ...[
                if (!widget.fullScreen) ...[
                  header,
                  const SizedBox(height: CruSpace.s12),
                ],
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
                        height: (constraints.maxWidth * 0.62).clamp(
                          380.0,
                          widget.fullScreen ? 760.0 : 540.0,
                        ),
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
                        // Full screen: past the card's size cap.
                        maxScale: widget.fullScreen ? 10 : null,
                      ),
              ),
              if (!_threeD && layer.showsPerio && data.perioExam == null) ...[
                const SizedBox(height: CruSpace.s12),
                const _PerioNotice(),
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
              if (narrow) ...[
                Align(alignment: Alignment.centerLeft, child: teeth),
                const SizedBox(height: CruSpace.s12),
                legend,
              ] else
                Row(
                  children: [
                    Expanded(child: legend),
                    const SizedBox(width: CruSpace.s12),
                    teeth,
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Perio layer without an exam: say so. The perio chart opens only from
/// Clinical records' Perio button.
class _PerioNotice extends StatelessWidget {
  const _PerioNotice();

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
    final logs =
        [
          ...(ref.watch(patientProcedureLogProvider(widget.patient.id)).value ??
              const <DentalProcedureLogModel>[]),
        ].where((l) => !l.isDeleted).toList()..sort(
          (a, b) => b.performedAt.compareTo(a.performedAt),
        );
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
                  child: Text(
                    'Procedures',
                    style: CruType.headline.tint(c.label),
                  ),
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
                onTap: () => showProcedureLogDialog(
                  context,
                  patient: widget.patient,
                  existing: shown[i],
                ),
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
                padding: const EdgeInsets.only(
                  top: CruSpace.s6,
                  left: CruSpace.s12,
                ),
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
  const NoPlanCard({super.key, required this.patient, this.onCreatePlan});

  final Patient patient;

  /// Opens the plan editor (and refreshes what shows the plan); without
  /// it the editor opens on its own.
  final VoidCallback? onCreatePlan;

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
                Text(
                  'Treatment plan',
                  style: CruType.callout.w600.tint(c.label),
                ),
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
            onPressed:
                onCreatePlan ??
                () => showTreatmentPlanDialog(context, patient: patient),
          ),
        ],
      ),
    );
  }
}
