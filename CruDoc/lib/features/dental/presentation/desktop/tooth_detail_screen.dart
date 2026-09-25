import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/chart_legend.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_art.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_2d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_dialogs.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/endo_dialog.dart';
import 'package:doctor_management_app/features/dental/records/perio_chart_screen.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A patient's chart from every source: findings, the plan, the latest
/// perio exam and the endo records.
ToothChartData watchPatientChart(WidgetRef ref, String patientId) {
  final entries = ref.watch(patientToothChartProvider(patientId)).value ??
      const <ToothChartEntryModel>[];
  final plan = ref.watch(patientTreatmentPlanProvider(patientId)).value ??
      const <TreatmentPlanLineItemModel>[];
  final perio = ref
          .watch(patientRecordsProvider((patientId: patientId, kind: RecKind.perio)))
          .value ??
      const <DentalRecord>[];
  final endo = ref
          .watch(patientRecordsProvider((patientId: patientId, kind: RecKind.endo)))
          .value ??
      const <DentalRecord>[];
  return ToothChartData.from(
    entries,
    plan,
    perioExam: perio.isEmpty ? null : perio.first,
    endo: endo,
  );
}

/// Opens [tooth] full screen. Completes with the tooth shown last (the
/// dentist can step to its neighbours there).
Future<String?> openToothDetail(
  BuildContext context, {
  required Patient patient,
  required String tooth,
}) =>
    Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: Theme.of(context),
          child: ToothDetailScreen(patient: patient, tooth: tooth),
        ),
      ),
    );

/// Opens the patient's perio chart full screen.
Future<void> openPerioChart(BuildContext context, Patient patient) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: Theme.of(context),
          child: PerioChartScreen(patient: patient),
        ),
      ),
    );

/// One tooth up close: its anatomy from the cheek side and from above
/// (pick surfaces there to chart them), what was found and done, planned
/// work, gums, root canal and history. ← → step to the neighbours.
class ToothDetailScreen extends ConsumerStatefulWidget {
  const ToothDetailScreen({
    super.key,
    required this.patient,
    required this.tooth,
  });

  final Patient patient;
  final String tooth;

  @override
  ConsumerState<ToothDetailScreen> createState() => _ToothDetailScreenState();
}

class _ToothDetailScreenState extends ConsumerState<ToothDetailScreen> {
  late String _tooth = widget.tooth;
  ChartLayer _layer = ChartLayer.dental;
  final Set<ToothSurface> _picked = {};

  Patient get p => widget.patient;

  /// Teeth in chart order: the upper row, then the lower row.
  List<String> get _order {
    final (upper, lower) = ToothSpec.arches(child: DentalChart.isPrimary(_tooth));
    return [...upper, ...lower];
  }

  String _neighbour(int step) {
    final o = _order;
    final i = o.indexOf(_tooth);
    return o[(i + step + o.length) % o.length];
  }

  void _go(String tooth) {
    if (tooth == _tooth) return;
    setState(() {
      _tooth = tooth;
      _picked.clear();
    });
  }

  void _back() => Navigator.of(context).pop(_tooth);

  Future<void> _record(ToothChartEntryModel? latest) async {
    final saved = await showToothFindingDialog(
      context,
      patient: p,
      tooth: _tooth,
      latest: latest,
      surfaces: _picked.isEmpty ? null : {..._picked},
    );
    if (saved && mounted) setState(_picked.clear);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _go(_neighbour(-1));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _go(_neighbour(1));
    } else if (k == LogicalKeyboardKey.escape) {
      _back();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final data = watchPatientChart(ref, p.id);
    final entries = ref.watch(patientToothChartProvider(p.id)).value ??
        const <ToothChartEntryModel>[];
    final plan = ref.watch(patientTreatmentPlanProvider(p.id)).value ??
        const <TreatmentPlanLineItemModel>[];
    final logs = ref.watch(patientProcedureLogProvider(p.id)).value ??
        const <DentalProcedureLogModel>[];
    final v = data.of(_tooth);
    final history = entries
        .where((e) => e.toothNumber == _tooth && !e.isDeleted)
        .toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final latest = history.isEmpty ? null : history.first;
    final procedures = logs
        .where((l) => l.toothNumbers.contains(_tooth) && !l.isDeleted)
        .toList();
    final planItems = plan
        .where((i) =>
            !i.isDeleted && i.toothNumbers.map((t) => t.trim()).contains(_tooth))
        .toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    final prev = _neighbour(-1);
    final next = _neighbour(1);
    final numbering =
        ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    String label(String t) => toothLabel(t, numbering);

    final stage = _StageCard(
      data: data,
      tooth: _tooth,
      layer: _layer,
      picked: _picked,
      numbering: numbering,
      onLayer: (l) => setState(() => _layer = l),
      onPick: (s) => setState(
        () => _picked.contains(s) ? _picked.remove(s) : _picked.add(s),
      ),
      onClearPicked: () => setState(_picked.clear),
      onRecordPicked: () => _record(latest),
      onGo: _go,
    );
    final side = <Widget>[
      _NowCard(visual: v, latest: latest),
      _PlanCard(patient: p, tooth: _tooth, items: planItems),
      _GumsCard(patient: p, visual: v, exam: data.perioExam),
      _EndoCard(patient: p, tooth: _tooth, visual: v),
      _HistoryCard(patient: p, history: history, procedures: procedures),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: c.canvas,
        body: SafeArea(
          child: Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: Padding(
              padding: CruSpace.mainPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CruIconButton(
                        icon: CruIcons.chevronLeft,
                        semanticLabel: 'Back',
                        tooltip: 'Back (Esc)',
                        onPressed: _back,
                      ),
                      const SizedBox(width: CruSpace.s8),
                      Expanded(
                        child: DentalPageHeader(
                          title: 'Tooth ${label(_tooth)}',
                          subtitle: '${DentalChart.name(_tooth)} · ${p.fullName}',
                          actions: [
                            CruSquareButton(
                              icon: CruIcons.chevronLeft,
                              secondary: true,
                              semanticLabel: 'Tooth ${label(prev)}',
                              tooltip: 'Tooth ${label(prev)} (←)',
                              onPressed: () => _go(prev),
                            ),
                            CruSquareButton(
                              icon: CruIcons.chevronRight,
                              secondary: true,
                              semanticLabel: 'Tooth ${label(next)}',
                              tooltip: 'Tooth ${label(next)} (→)',
                              onPressed: () => _go(next),
                            ),
                            CruButton(
                              label: 'Log procedure',
                              kind: CruButtonKind.secondary,
                              onPressed: () => showProcedureLogDialog(
                                context,
                                patient: p,
                                teeth: [_tooth],
                              ),
                            ),
                            CruButton(
                              label: 'Record finding',
                              icon: CruIcons.plus,
                              onPressed: () => _record(latest),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CruSpace.cardGap),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 980;
                        return SingleChildScrollView(
                          child: wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: stage),
                                    const SizedBox(width: CruSpace.cardGap),
                                    SizedBox(
                                      width: CruSize.rightColumn,
                                      child: _Stack(side),
                                    ),
                                  ],
                                )
                              : _Stack([stage, ...side]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cards stacked with the card gap.
class _Stack extends StatelessWidget {
  const _Stack(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: CruSpace.cardGap),
            children[i],
          ],
        ],
      );
}

// ================================================================= stage

/// The tooth drawn large from the cheek side and from above, with the
/// surfaces to pick, its numbers in other notations, and the whole mouth
/// to jump to another tooth.
class _StageCard extends StatefulWidget {
  const _StageCard({
    required this.data,
    required this.tooth,
    required this.layer,
    required this.picked,
    required this.numbering,
    required this.onLayer,
    required this.onPick,
    required this.onClearPicked,
    required this.onRecordPicked,
    required this.onGo,
  });

  final ToothChartData data;
  final String tooth;
  final ChartLayer layer;
  final Set<ToothSurface> picked;
  final ToothNumbering numbering;
  final ValueChanged<ChartLayer> onLayer;
  final ValueChanged<ToothSurface> onPick;
  final VoidCallback onClearPicked;
  final VoidCallback onRecordPicked;
  final ValueChanged<String> onGo;

  @override
  State<_StageCard> createState() => _StageCardState();
}

class _StageCardState extends State<_StageCard> {
  static const double _height = 460;
  ToothSurface? _hover;
  _Stage? _stage;

  @override
  void didUpdateWidget(_StageCard old) {
    super.didUpdateWidget(old);
    if (old.tooth != widget.tooth) _hover = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final v = widget.data.of(widget.tooth);
    final spec = ToothSpec.of(widget.tooth);
    final picked = widget.picked;
    final pickable = !(v.missing && !v.implant);
    final hint = picked.isNotEmpty
        ? '${_surfaceNames(picked)} picked'
        : _hover != null
            ? '${_surfaceName(_hover!, spec)} · click to pick it'
            : v.missing && !v.implant
                ? 'This tooth is missing'
                : 'Click the surfaces on the tooth to chart them';

    return CruCard(
      semanticLabel: 'Tooth ${toothLabel(widget.tooth, widget.numbering)}',
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CruSegmentedControl<ChartLayer>(
                semanticLabel: 'Show',
                segments: [
                  for (final l in const [
                    ChartLayer.dental,
                    ChartLayer.perio,
                    ChartLayer.endo,
                  ])
                    CruSegment(l, l.label),
                ],
                selected: widget.layer,
                onChanged: widget.onLayer,
              ),
              const Spacer(),
              toothStatePill(c, v.state),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, _height);
              var stage = _stage;
              if (stage == null ||
                  stage.size != size ||
                  stage.spec.number != widget.tooth) {
                stage = _stage = _Stage.of(spec, size);
              }
              final s = stage;
              return SizedBox(
                height: _height,
                child: MouseRegion(
                  cursor: _hover == null ? MouseCursor.defer : SystemMouseCursors.click,
                  onHover: (e) {
                    final hit = pickable ? s.surfaceAt(e.localPosition) : null;
                    if (hit != _hover) setState(() => _hover = hit);
                  },
                  onExit: (_) => setState(() => _hover = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final hit = pickable ? s.surfaceAt(d.localPosition) : null;
                      if (hit != null) widget.onPick(hit);
                    },
                    child: CustomPaint(
                      size: size,
                      painter: _StagePainter(
                        stage: s,
                        visual: v,
                        layer: widget.layer,
                        hover: _hover,
                        picked: {...picked},
                        colors: c,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  hint,
                  style: CruType.subhead.tint(picked.isEmpty ? c.label3 : c.label),
                ),
              ),
              if (picked.isNotEmpty) ...[
                CruLink(label: 'Clear', onPressed: widget.onClearPicked),
                const SizedBox(width: CruSpace.s12),
                CruButton(
                  label: 'Record finding on ${picked.map(DentalChart.surfaceLetter).join(', ')}',
                  kind: CruButtonKind.tinted,
                  onPressed: widget.onRecordPicked,
                ),
              ],
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          ChartLegend(layer: widget.layer),
          const SizedBox(height: CruSpace.s16),
          _Facts(spec: spec),
          const SizedBox(height: CruSpace.s16),
          const CruSeparator(),
          const SizedBox(height: CruSpace.s14),
          Text('All teeth', style: CruType.groupLabel.tint(c.label3)),
          const SizedBox(height: CruSpace.s6),
          ToothChart2D(
            data: widget.data,
            child: DentalChart.isPrimary(widget.tooth),
            rows: ChartRows.occlusal,
            maxScale: 4.2,
            selected: widget.tooth,
            onSelect: widget.onGo,
            numbering: widget.numbering,
          ),
        ],
      ),
    );
  }
}

String _surfaceName(ToothSurface s, ToothSpec spec) {
  final upper = spec.upper;
  final front = spec.kind != ToothKind.premolar && spec.kind != ToothKind.molar;
  return switch (s) {
    ToothSurface.mesial => 'Mesial',
    ToothSurface.distal => 'Distal',
    ToothSurface.occlusal => 'Occlusal',
    ToothSurface.incisal => 'Incisal',
    ToothSurface.buccal => front ? 'Labial' : 'Buccal',
    ToothSurface.lingual => upper ? 'Palatal' : 'Lingual',
    ToothSurface.cervical => 'Cervical',
  };
}

String _surfaceNames(Set<ToothSurface> s) =>
    s.map(DentalChart.surfaceLabel).join(', ');

/// Where the two views sit, and which surface is where.
class _Stage {
  _Stage._(this.spec, this.size, this.buccal, this.occlusal);

  factory _Stage.of(ToothSpec spec, Size size) {
    const gap = 110.0;
    const caption = 30.0;
    final len = spec.crown + spec.root;
    final k = math.min(
      20.0,
      math.min(
        (size.height - caption - 36) / len,
        (size.width - gap - 80) / (spec.md * 2),
      ),
    );
    final x0 = (size.width - (spec.md * k * 2 + gap)) / 2;
    final mid = (size.height - caption) / 2 + 4;
    return _Stage._(
      spec,
      size,
      BuccalShape.of(
        spec,
        k: k,
        cx: x0 + spec.md * k / 2,
        edgeY: spec.upper ? mid + len * k / 2 : mid - len * k / 2,
      ),
      OcclusalShape.of(
        spec,
        k: k,
        center: Offset(x0 + spec.md * k * 1.5 + gap, mid),
      ),
    );
  }

  final ToothSpec spec;
  final Size size;
  final BuccalShape buccal;
  final OcclusalShape occlusal;

  bool get front =>
      spec.kind != ToothKind.premolar && spec.kind != ToothKind.molar;

  ToothSurface get _top => front ? ToothSurface.incisal : ToothSurface.occlusal;

  ToothSurface? surfaceAt(Offset p) {
    if (occlusal.outline.contains(p)) {
      for (final s in [
        _top,
        ToothSurface.mesial,
        ToothSurface.distal,
        ToothSurface.buccal,
        ToothSurface.lingual,
      ]) {
        final a = occlusal.surfaceArea(s);
        if (a != null && a.contains(p)) return s;
      }
      return _top;
    }
    if (buccal.crown.contains(p)) {
      for (final s in [
        _top,
        ToothSurface.cervical,
        ToothSurface.mesial,
        ToothSurface.distal,
        ToothSurface.buccal,
      ]) {
        final r = buccal.surfaceArea(s);
        if (r != null && _inOval(r, p)) return s;
      }
      return ToothSurface.buccal;
    }
    return null;
  }

  static bool _inOval(Rect r, Offset p) {
    final dx = (p.dx - r.center.dx) / (r.width / 2);
    final dy = (p.dy - r.center.dy) / (r.height / 2);
    return dx * dx + dy * dy <= 1;
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter({
    required this.stage,
    required this.visual,
    required this.layer,
    required this.hover,
    required this.picked,
    required this.colors,
  });

  final _Stage stage;
  final ToothVisual visual;
  final ChartLayer layer;
  final ToothSurface? hover;
  final Set<ToothSurface> picked;
  final CruColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    final b = stage.buccal;
    final o = stage.occlusal;
    final look = visual.look(layer);
    ToothArt.buccal(canvas, b, look, c);
    ToothArt.occlusal(canvas, o, look, c);

    // Gums from the latest perio exam.
    final p = visual.perio;
    if (layer == ChartLayer.perio && p != null && visual.charted && !look.missing) {
      const idx = [2, 1, 0];
      final g = ToothArt.pockets(
        canvas,
        b,
        c,
        pd: [for (final i in idx) p.pd[i]],
        rec: [for (final i in idx) p.rec[i]],
        bop: [for (final i in idx) p.bop[i]],
        furcation: p.furcation,
      );
      ToothArt.gumLine(canvas, g.margin, c);
      ToothArt.bleeding(canvas, g.bleeding, c);
    }

    // Surfaces: the picked ones as one shape per view, the hovered one
    // lighter.
    void mark(Iterable<ToothSurface> surfaces, {required bool on}) {
      final fill = Paint()..color = c.accent.withValues(alpha: on ? 0.22 : 0.12);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 1.8 : 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = c.accent.withValues(alpha: on ? 0.95 : 0.55);
      Path? top;
      Path? face;
      for (final s in surfaces) {
        final a = o.surfaceArea(s);
        if (a != null) top = top == null ? a : Path.combine(PathOperation.union, top, a);
        final r = b.surfaceArea(s);
        if (r != null) {
          final oval = Path()..addOval(r);
          face = face == null ? oval : Path.combine(PathOperation.union, face, oval);
        }
      }
      if (face != null) face = Path.combine(PathOperation.intersect, face, b.crown);
      for (final p in [?top, ?face]) {
        canvas.drawPath(p, fill);
        canvas.drawPath(p, line);
      }
    }

    if (picked.isNotEmpty) mark(picked, on: true);
    if (hover != null && !picked.contains(hover)) mark([hover!], on: false);

    // Which way is which.
    final quiet = CruType.caption.w600.tint(c.label3);
    final spec = stage.spec;
    final lingual = spec.upper ? 'P' : 'L';
    _label(canvas, 'M', o.at(1.32, 0), quiet);
    _label(canvas, 'D', o.at(-1.32, 0), quiet);
    _label(canvas, 'B', o.at(0, -1.3), quiet);
    _label(canvas, lingual, o.at(0, 1.3), quiet);
    final crownMid = b.crownRect.center.dy;
    final mesialRight = !b.mirror;
    _label(canvas, 'M', Offset(mesialRight ? b.crownRect.right + 14 : b.crownRect.left - 14, crownMid), quiet);
    _label(canvas, 'D', Offset(mesialRight ? b.crownRect.left - 14 : b.crownRect.right + 14, crownMid), quiet);

    final caption = CruType.subhead.tint(c.label2);
    final y = size.height - 14;
    _label(canvas, stage.front ? 'Lip side' : 'Cheek side', Offset(b.cx, y), caption);
    _label(canvas, stage.front ? 'Biting edge' : 'Biting surface', Offset(o.center.dx, y), caption);
  }

  static void _label(Canvas canvas, String text, Offset at, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_StagePainter old) =>
      old.stage != stage ||
      old.visual != visual ||
      old.layer != layer ||
      old.hover != hover ||
      !setEquals(old.picked, picked) ||
      old.colors != colors;
}

/// The tooth's number in each notation, its roots, and which set it's in.
class _Facts extends StatelessWidget {
  const _Facts({required this.spec});

  final ToothSpec spec;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final q = int.parse(spec.number[0]);
    final n = spec.position;
    final String universal;
    final String palmer;
    final side = switch (q) {
      1 || 5 => 'UR',
      2 || 6 => 'UL',
      3 || 7 => 'LL',
      _ => 'LR',
    };
    if (spec.primary) {
      final letter = switch (q) {
        5 => 5 - n,
        6 => 5 + n - 1,
        7 => 10 + 5 - n,
        _ => 15 + n - 1,
      };
      universal = String.fromCharCode(65 + letter);
      palmer = '$side${String.fromCharCode(64 + n)}';
    } else {
      universal = '${switch (q) {
        1 => 9 - n,
        2 => 8 + n,
        3 => 25 - n,
        _ => 24 + n,
      }}';
      palmer = '$side$n';
    }
    Widget fact(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: CruType.caption.tint(c.label3)),
            const SizedBox(height: CruSpace.s2),
            Text(value, style: CruType.callout.w600.tabular.tint(c.label)),
          ],
        );
    return Wrap(
      spacing: CruSpace.s32,
      runSpacing: CruSpace.s12,
      children: [
        fact('FDI', spec.number),
        fact('Universal', universal),
        fact('Palmer', palmer),
        fact('Roots', '${spec.roots}'),
        fact('Set', spec.primary ? 'Milk tooth' : 'Permanent'),
      ],
    );
  }
}

// ================================================================= cards

/// A side card: title, an optional action, content.
class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: title,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: CruType.headline.tint(c.label)),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: CruSpace.s10),
          child,
        ],
      ),
    );
  }
}

/// What's on the chart for the tooth now.
class _NowCard extends StatelessWidget {
  const _NowCard({required this.visual, required this.latest});

  final ToothVisual visual;
  final ToothChartEntryModel? latest;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final e = latest;
    return _SideCard(
      title: 'On the chart',
      action: toothStatePill(c, visual.state),
      child: e == null
          ? Text(
              'Nothing recorded yet. Record a finding to start this tooth’s '
              'history.',
              style: CruType.subhead.tint(c.label2),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_found(e), style: CruType.callout.w600.tint(c.label)),
                const SizedBox(height: CruSpace.s2),
                Text(
                  'Recorded ${DentalFormat.date(e.recordedAt)}',
                  style: CruType.caption.tabular.tint(c.label3),
                ),
                if (e.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s8),
                  Text(e.notes.trim(), style: CruType.subhead.tint(c.label2)),
                ],
                if (visual.surfaces.isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s10),
                  Wrap(
                    spacing: CruSpace.s6,
                    runSpacing: CruSpace.s6,
                    children: [
                      for (final s in visual.surfaces)
                        CruPill(
                          text: DentalChart.surfaceLabel(s),
                          background: c.inset,
                          foreground: c.label2,
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

/// "Decay", "Root canal treated · Crown done"; "Healthy" when nothing
/// was found (surfaces show separately).
String _found(ToothChartEntryModel e) {
  final c = DentalChart.condition(e.condition);
  final t = DentalChart.treatment(e.treatment);
  final parts = [
    if (c != null) DentalChart.conditionLabel(c),
    if (t != null) '${DentalChart.treatmentLabel(t)} done',
  ];
  return parts.isEmpty ? 'Healthy' : parts.join(' · ');
}

/// Planned work on this tooth.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.patient,
    required this.tooth,
    required this.items,
  });

  final Patient patient;
  final String tooth;
  final List<TreatmentPlanLineItemModel> items;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return _SideCard(
      title: 'Plan',
      action: CruCapsuleButton(
        label: 'Add to plan',
        onPressed: () => showPlanItemDialog(context, patient: patient, teeth: [tooth]),
      ),
      child: items.isEmpty
          ? Text(
              'Nothing planned for this tooth.',
              style: CruType.subhead.tint(c.label2),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final i in items)
                  DentalListRow(
                    semanticLabel: i.procedureName,
                    minHeight: 48,
                    onTap: () => showPlanItemDialog(context, patient: patient, existing: i),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i.procedureName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CruType.callout.tint(c.label),
                              ),
                              if (i.estimatedPrice > 0)
                                Text(
                                  DashFormat.rupees(i.estimatedPrice),
                                  style: CruType.subhead.tabular.tint(c.label2),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: CruSpace.s8),
                        planStatusPill(c, i.status),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// This tooth in the latest perio exam.
class _GumsCard extends StatelessWidget {
  const _GumsCard({
    required this.patient,
    required this.visual,
    required this.exam,
  });

  final Patient patient;
  final ToothVisual visual;
  final DentalRecord? exam;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final p = visual.perio;
    final open = CruLink(
      label: 'Perio chart',
      onPressed: () => openPerioChart(context, patient),
    );
    if (exam == null || p == null || !visual.charted) {
      return _SideCard(
        title: 'Gums',
        action: open,
        child: Text(
          exam == null
              ? 'No perio exam yet.'
              : 'Not charted in the exam of ${DentalFormat.date(exam!.recordedAt)}.',
          style: CruType.subhead.tint(c.label2),
        ),
      );
    }
    Widget depth(int site) {
      final d = p.pd[site];
      final deep = (d ?? 0) >= 4;
      return SizedBox(
        width: 56,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              d == null ? '–' : '$d',
              style: (deep ? CruType.callout.w600 : CruType.callout)
                  .tabular
                  .tint(deep ? c.amberText : c.label),
            ),
            if (p.bop[site]) ...[
              const SizedBox(width: CruSpace.s4),
              Container(
                width: 7,
                height: 7,
                decoration: ShapeDecoration(color: c.amber, shape: const CircleBorder()),
              ),
            ],
          ],
        ),
      );
    }

    Widget row(String label, List<int> sites, List<String> names) => Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(label, style: CruType.subhead.tint(c.label2)),
              ),
              for (var i = 0; i < 3; i++)
                Tooltip(message: names[i], child: depth(sites[i])),
            ],
          ),
        );
    final recession = p.rec.whereType<int>().fold<int?>(
          null,
          (m, r) => m == null || r > m ? r : m,
        );
    return _SideCard(
      title: 'Gums',
      action: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 96),
              for (final s in const ['M', 'Mid', 'D'])
                SizedBox(
                  width: 56,
                  child: Text(s, style: CruType.caption.tint(c.label3)),
                ),
            ],
          ),
          row('Cheek side', const [0, 1, 2], const ['Mesiobuccal', 'Buccal', 'Distobuccal']),
          row('Tongue side', const [3, 4, 5], const ['Mesiolingual', 'Lingual', 'Distolingual']),
          const SizedBox(height: CruSpace.s8),
          Text(
            [
              'Pocket depths in mm',
              if (p.bop.any((b) => b)) 'dot marks bleeding',
            ].join(' · '),
            style: CruType.caption.tint(c.label3),
          ),
          if ((recession ?? 0) > 0 ||
              (p.mobility ?? 0) > 0 ||
              (p.furcation ?? 0) > 0) ...[
            const SizedBox(height: CruSpace.s8),
            Wrap(
              spacing: CruSpace.s6,
              runSpacing: CruSpace.s6,
              children: [
                if ((recession ?? 0) > 0)
                  CruPill(
                    text: 'Recession up to $recession mm',
                    background: c.inset,
                    foreground: c.label2,
                  ),
                if ((p.mobility ?? 0) > 0)
                  CruPill(
                    text: 'Mobility ${p.mobility}',
                    background: c.amberTint,
                    foreground: c.amberText,
                  ),
                if ((p.furcation ?? 0) > 0)
                  CruPill(
                    text: 'Furcation ${p.furcation}',
                    background: c.amberTint,
                    foreground: c.amberText,
                  ),
              ],
            ),
          ],
          const SizedBox(height: CruSpace.s8),
          Text(
            'Exam ${DentalFormat.date(exam!.recordedAt)}',
            style: CruType.caption.tabular.tint(c.label3),
          ),
        ],
      ),
    );
  }
}

/// The tooth's endo record.
class _EndoCard extends StatelessWidget {
  const _EndoCard({
    required this.patient,
    required this.tooth,
    required this.visual,
  });

  final Patient patient;
  final String tooth;
  final ToothVisual visual;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final e = visual.endo;
    if (e == null) {
      return _SideCard(
        title: 'Root canal',
        action: CruCapsuleButton(
          label: 'Start endo record',
          onPressed: () => showEndoDialog(context, patient, tooth: tooth),
        ),
        child: Text(
          visual.rootCanal
              ? 'Root canal treated (on the chart). No endo record with '
                  'canal details.'
              : 'No endo record for this tooth.',
          style: CruType.subhead.tint(c.label2),
        ),
      );
    }
    final canals = e.record.data['canals'] is List
        ? [
            for (final k in e.record.data['canals'] as List)
              if (k is Map)
                [
                  '${k['name'] ?? ''}'.trim(),
                  if (k['wl'] is num) '${(k['wl'] as num).toString()} mm',
                ].where((t) => t.isNotEmpty).join(' '),
          ].where((t) => t.isNotEmpty).toList()
        : const <String>[];
    final obturatedOn = e.record.date('obturatedOn');
    final raw = e.record.data['tests'];
    final tests = [
      if (raw is Map)
        for (final t in const ['Cold', 'Heat', 'EPT', 'Percussion', 'Palpation'])
          if ('${raw[t] ?? ''}'.isNotEmpty) (t, '${raw[t]}'),
    ];
    return _SideCard(
      title: 'Root canal',
      action: CruCapsuleButton(
        label: 'Open record',
        onPressed: () => showEndoDialog(context, patient, existing: e.record),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          e.obturated
              ? CruPill(text: 'Obturated', background: c.greenTint, foreground: c.greenText)
              : CruPill(text: 'In progress', background: c.amberTint, foreground: c.amberText),
          const SizedBox(height: CruSpace.s10),
          if (e.pulpal.isNotEmpty)
            Text(e.pulpal, style: CruType.callout.tint(c.label)),
          if (e.periapical.isNotEmpty)
            Text(
              e.periapical,
              style: CruType.subhead.tint(e.lesion ? c.amberText : c.label2),
            ),
          if (tests.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s10),
            for (final (test, result) in tests)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: CruSpace.s2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(test, style: CruType.subhead.tint(c.label2)),
                    ),
                    Text(
                      result,
                      style: _abnormalTests.contains(result)
                          ? CruType.subhead.w600.tint(c.amberText)
                          : CruType.subhead.tint(c.label),
                    ),
                  ],
                ),
              ),
          ],
          if (canals.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s8),
            Text(
              'Canals: ${canals.join(' · ')}',
              style: CruType.subhead.tabular.tint(c.label2),
            ),
          ],
          const SizedBox(height: CruSpace.s6),
          Text(
            obturatedOn == null
                ? 'Started ${DentalFormat.date(e.record.recordedAt)}'
                : 'Obturated ${DentalFormat.date(obturatedOn)}',
            style: CruType.caption.tabular.tint(c.label3),
          ),
        ],
      ),
    );
  }
}

/// Vitality test results that point to a problem.
const _abnormalTests = {'No response', 'Lingering', 'Exaggerated', 'Tender'};

/// Findings and procedures on this tooth, newest first.
class _HistoryCard extends StatefulWidget {
  const _HistoryCard({
    required this.patient,
    required this.history,
    required this.procedures,
  });

  final Patient patient;
  final List<ToothChartEntryModel> history;
  final List<DentalProcedureLogModel> procedures;

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final timeline = <(DateTime, String, String?, Widget?, VoidCallback?)>[
      for (final e in widget.history)
        (
          e.recordedAt,
          [
            _found(e),
            if (DentalChart.surfaces(e.surface).isNotEmpty)
              DentalChart.surfaces(e.surface).map(DentalChart.surfaceLetter).join(', '),
          ].join(' · '),
          e.notes.trim().isEmpty ? null : e.notes.trim(),
          null,
          null,
        ),
      for (final l in widget.procedures)
        (
          l.performedAt,
          l.procedureName,
          _joined([l.materials ?? '', l.notes]),
          procedureStatusPill(c, l.status),
          () => showProcedureLogDialog(context, patient: widget.patient, existing: l),
        ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final shown = _all ? timeline : timeline.take(5).toList();
    return _SideCard(
      title: 'History',
      child: timeline.isEmpty
          ? Text(
              'No findings or procedures on this tooth yet.',
              style: CruType.subhead.tint(c.label2),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (date, title, note, pill, onTap) in shown)
                  DentalListRow(
                    semanticLabel: '$title, ${DentalFormat.date(date)}',
                    onTap: onTap,
                    minHeight: 48,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 84,
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
                if (timeline.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(left: CruSpace.s12, top: CruSpace.s4),
                    child: CruLink(
                      label: _all ? 'Show fewer' : 'Show all ${timeline.length}',
                      onPressed: () => setState(() => _all = !_all),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Non-empty parts joined with " · ", or null.
String? _joined(List<String> parts) {
  final kept = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  return kept.isEmpty ? null : kept.join(' · ');
}
