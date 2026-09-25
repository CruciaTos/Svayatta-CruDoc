import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/dental/data/models/dental_procedure_log_model.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_render.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_dialogs.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/endo_dialog.dart';
import 'package:doctor_management_app/features/dental/records/perio_chart_screen.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _uuid = Uuid();

/// Opens [tooth] full size (double-click on the chart).
Future<void> showToothDetail(
  BuildContext context, {
  required Patient patient,
  required String tooth,
}) => showDialog<void>(
  context: context,
  builder: (_) => ToothDetailView(patient: patient, tooth: tooth),
);

/// One tooth, full size. Left: every tooth's number (pick another) and
/// this tooth seen from the cheek, from above and from the tongue side,
/// with the gum line and pockets from the last perio exam; the surfaces
/// are picked on the top view. Middle: its history, then what was found
/// and what was done, as tiles. Right: the finding being recorded, the
/// endodontic tests and the six perio sites.
class ToothDetailView extends ConsumerStatefulWidget {
  const ToothDetailView({
    super.key,
    required this.patient,
    required this.tooth,
  });

  final Patient patient;
  final String tooth;

  @override
  ConsumerState<ToothDetailView> createState() => _ToothDetailViewState();
}

enum _Grid { condition, treatment }

/// [tooth] with [condition] and [treatment], as the chart shows it.
ToothVisual _visual(
  String tooth,
  ToothCondition? condition,
  ToothTreatment? treatment, [
  List<String> planned = const [],
]) {
  final now = DateTime.now();
  return ToothVisual(
    number: tooth,
    state: DentalChart.stateOf(
      ToothChartEntryModel(
        id: '',
        doctorId: '',
        patientId: '',
        toothNumber: tooth,
        condition: condition?.name,
        treatment: treatment?.name,
        recordedAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    ),
    condition: condition,
    treatment: treatment,
    planned: planned,
  );
}

bool _anterior(ToothSpec s) =>
    s.kind != ToothKind.premolar && s.kind != ToothKind.molar;

DentalRecord? _newest(Iterable<DentalRecord> records) => records.isEmpty
    ? null
    : records.reduce((a, b) => a.recordedAt.isAfter(b.recordedAt) ? a : b);

/// This tooth's readings in a perio exam; null when it has none.
PerioTooth? _perioOf(DentalRecord exam, String tooth) {
  final raw = exam.data['teeth'];
  if (raw is! Map || raw[tooth] == null) return null;
  final t = PerioTooth.fromJson(raw[tooth]);
  if (t.missing) return null;
  final any =
      t.pd.any((v) => v != null) ||
      t.rec.any((v) => v != null) ||
      t.mobility != null ||
      t.furcation != null;
  return any ? t : null;
}

class _ToothDetailViewState extends ConsumerState<ToothDetailView> {
  late String _tooth = widget.tooth;

  /// The tooth the draft below was loaded for.
  String? _draftFor;
  ToothCondition? _condition;
  ToothTreatment? _treatment;
  final Set<ToothSurface> _surfaces = {};
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  _Grid _grid = _Grid.condition;
  bool _dirty = false;
  bool _saving = false;
  bool _saved = false;
  bool _allHistory = false;
  String? _notice;

  Patient get p => widget.patient;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Start from what the chart shows for the tooth now.
  void _load(ToothChartEntryModel? latest) {
    _draftFor = _tooth;
    _condition = DentalChart.condition(latest?.condition);
    _treatment = DentalChart.treatment(latest?.treatment);
    _surfaces
      ..clear()
      ..addAll(DentalChart.surfaces(latest?.surface));
    _notes.clear();
    _date = DateTime.now();
    _dirty = false;
    _saved = false;
    _notice = null;
    _allHistory = false;
    _grid = _treatment != null && _condition == null
        ? _Grid.treatment
        : _Grid.condition;
  }

  void _edit(VoidCallback change) => setState(() {
    change();
    _dirty = true;
    _saved = false;
    _notice = null;
  });

  Future<bool> _discardOk() async {
    if (!_dirty) return true;
    return confirmDental(
      context,
      title: 'Discard this finding?',
      body: "What you picked for this tooth hasn't been saved.",
      action: 'Discard',
    );
  }

  Future<void> _switchTo(String tooth) async {
    if (tooth == _tooth) return;
    if (!await _discardOk() || !mounted) return;
    setState(() {
      _tooth = tooth;
      _draftFor = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final now = DateTime.now();
      final at = DateTime(
        _date.year,
        _date.month,
        _date.day,
        now.hour,
        now.minute,
        now.second,
      );
      await ref
          .read(dentalRepositoryProvider)
          .saveToothChartEntry(
            ToothChartEntryModel(
              id: _uuid.v4(),
              doctorId: ref.read(dentalDoctorIdProvider),
              patientId: p.id,
              toothNumber: _tooth,
              condition: _condition?.name,
              treatment: _treatment?.name,
              surface: DentalChart.storeSurfaces(_surfaces),
              notes: _notes.text.trim(),
              recordedAt: at,
              createdAt: now,
              updatedAt: now,
              syncStatus: 'pending',
            ),
          );
      refreshDentalPatient(ref, p.id);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _saved = true;
        _notes.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = "Couldn't save the finding. Try again.";
      });
    }
  }

  void _openPerio() {
    final theme = Theme.of(context);
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: theme,
          child: PerioChartScreen(patient: p),
        ),
      ),
    );
  }

  String _summary(ToothNumbering n) => [
    toothLabel(_tooth, n),
    if (_surfaces.isNotEmpty)
      [
        for (final s in ToothSurface.values)
          if (_surfaces.contains(s)) DentalChart.surfaceLabel(s),
      ].join(', '),
    _condition == null ? 'Healthy' : DentalChart.conditionLabel(_condition!),
    if (_treatment != null) '${DentalChart.treatmentLabel(_treatment!)} done',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final chart = ref.watch(patientToothChartProvider(p.id));
    final entries = chart.value ?? const <ToothChartEntryModel>[];
    final plan =
        ref.watch(patientTreatmentPlanProvider(p.id)).value ??
        const <TreatmentPlanLineItemModel>[];
    final logs =
        ref.watch(patientProcedureLogProvider(p.id)).value ??
        const <DentalProcedureLogModel>[];
    final numbering =
        ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    final perioExams =
        ref
            .watch(
              patientRecordsProvider((patientId: p.id, kind: RecKind.perio)),
            )
            .value ??
        const <DentalRecord>[];
    final endoRecords =
        ref
            .watch(
              patientRecordsProvider((patientId: p.id, kind: RecKind.endo)),
            )
            .value ??
        const <DentalRecord>[];

    final data = ToothChartData.from(entries, plan);
    final latest = DentalChart.latest(entries);
    if (_draftFor != _tooth && chart.hasValue) _load(latest[_tooth]);

    final spec = ToothSpec.of(_tooth);
    final onChart = data.of(_tooth);
    final draft = _visual(_tooth, _condition, _treatment, onChart.planned);
    final exam = _newest(perioExams);
    final perio = exam == null ? null : _perioOf(exam, _tooth);
    final endo = _newest(endoRecords.where((r) => r.str('tooth') == _tooth));
    final entry = latest[_tooth];

    final timeline = <(DateTime, String, String?, Widget?, VoidCallback?)>[
      for (final e in entries)
        if (e.toothNumber == _tooth && !e.isDeleted)
          (
            e.recordedAt,
            DentalChart.findingText(e),
            e.notes.trim().isEmpty ? null : e.notes.trim(),
            null,
            null,
          ),
      for (final l in logs)
        if (l.toothNumbers.contains(_tooth) && !l.isDeleted)
          (
            l.performedAt,
            l.procedureName,
            [
              l.materials ?? '',
              l.notes,
            ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' · '),
            procedureStatusPill(c, l.status),
            () => showProcedureLogDialog(context, patient: p, existing: l),
          ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final planned = [
      for (final i in plan)
        if (!i.isDeleted &&
            i.toothNumbers.map((t) => t.trim()).contains(_tooth))
          i,
    ]..sort((a, b) => a.sequence.compareTo(b.sequence));

    final header = _Header(
      tooth: _tooth,
      numbering: numbering,
      patientName: p.fullName,
      state: onChart.state,
      facts: [
        (
          'On the chart',
          entry == null ? 'Healthy' : DentalChart.findingText(entry),
        ),
        ('Recorded', entry == null ? '—' : DentalFormat.date(entry.recordedAt)),
        ('Planned', onChart.isPlanned ? onChart.planned.join(', ') : 'Nothing'),
      ],
    );

    final left = SizedBox(
      width: 284,
      child: CruCard(
        semanticLabel: 'Tooth ${toothLabel(_tooth, numbering)}',
        padding: const EdgeInsets.fromLTRB(10, 16, 16, 16),
        child: _ToothColumn(
          tooth: _tooth,
          data: data,
          draft: draft,
          surfaces: _surfaces,
          tone: _tone(c),
          perio: perio,
          numbering: numbering,
          onTooth: _switchTo,
          onSurface: (s) => _edit(
            () =>
                _surfaces.contains(s) ? _surfaces.remove(s) : _surfaces.add(s),
          ),
        ),
      ),
    );

    final shown = _allHistory ? timeline : timeline.take(4).toList();
    final history = CruCard(
      semanticLabel: 'History',
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title(
            'History',
            trailing: CruCapsuleButton(
              label: 'Log procedure',
              onPressed: () =>
                  showProcedureLogDialog(context, patient: p, teeth: [_tooth]),
            ),
          ),
          const SizedBox(height: CruSpace.s10),
          if (timeline.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
              child: Text(
                'Nothing recorded for this tooth yet.',
                style: CruType.subhead.tint(c.label2),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      'Date',
                      style: CruType.groupLabel.tint(c.label3),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Entry',
                      style: CruType.groupLabel.tint(c.label3),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Notes',
                      style: CruType.groupLabel.tint(c.label3),
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    child: Text(
                      'Status',
                      textAlign: TextAlign.right,
                      style: CruType.groupLabel.tint(c.label3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CruSpace.s6),
            const CruSeparator(),
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
                      flex: 4,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CruType.text.tint(
                          onTap == null ? c.label : c.accentText,
                        ),
                      ),
                    ),
                    const SizedBox(width: CruSpace.s12),
                    Expanded(
                      flex: 4,
                      child: Text(
                        note == null || note.isEmpty ? '—' : note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CruType.subhead.tint(c.label2),
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child:
                            pill ??
                            Text(
                              'Finding',
                              style: CruType.caption.tint(c.label3),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            if (timeline.length > 4)
              Padding(
                padding: const EdgeInsets.only(
                  left: CruSpace.s12,
                  top: CruSpace.s4,
                ),
                child: CruLink(
                  label: _allHistory
                      ? 'Show fewer'
                      : 'Show all ${timeline.length}',
                  onPressed: () => setState(() => _allHistory = !_allHistory),
                ),
              ),
          ],
        ],
      ),
    );

    final tiles = _FindingTiles(
      tooth: _tooth,
      grid: _grid,
      condition: _condition,
      treatment: _treatment,
      onGrid: (g) => setState(() => _grid = g),
      onCondition: (v) => _edit(() => _condition = v),
      onTreatment: (v) => _edit(() => _treatment = v),
    );

    final planCard = CruCard(
      semanticLabel: 'Plan for this tooth',
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title(
            'Plan for this tooth',
            trailing: CruCapsuleButton(
              label: 'Add to plan',
              onPressed: () =>
                  showPlanItemDialog(context, patient: p, teeth: [_tooth]),
            ),
          ),
          const SizedBox(height: CruSpace.s8),
          if (planned.isEmpty)
            Text(
              'Nothing planned for this tooth.',
              style: CruType.subhead.tint(c.label2),
            )
          else
            for (final i in planned)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: CruSpace.s6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        i.procedureName.trim().isEmpty
                            ? 'Procedure'
                            : i.procedureName,
                        style: CruType.callout.tint(c.label),
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

    final record = CruCard(
      semanticLabel: 'Record finding',
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title('Record', trailing: toothStatePill(c, draft.state)),
          const SizedBox(height: CruSpace.s12),
          Container(
            padding: const EdgeInsets.all(CruSpace.s14),
            decoration: ShapeDecoration(
              color: c.inset,
              shape: cruShape(CruRadius.control),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _summary(numbering),
                  style: CruType.callout.w500.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s4),
                Text(
                  _dirty
                      ? 'Not saved yet'
                      : (_saved ? 'Saved to the chart' : 'As on the chart'),
                  style: CruType.caption.tint(
                    _dirty ? c.amberText : (_saved ? c.greenText : c.label3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.s12),
          CruPickerField(
            label: 'Date',
            icon: CruIcons.calendar,
            value: DentalFormat.date(_date),
            placeholder: 'Pick a date',
            trailing: DentalFormat.sameDay(_date, DateTime.now())
                ? const CruInfoPill(text: 'Today')
                : null,
            onTap: () async {
              final d = await pickDentalDate(
                context,
                initial: _date,
                last: DateTime.now(),
              );
              if (d != null) _edit(() => _date = d);
            },
          ),
          const SizedBox(height: CruSpace.s12),
          CruTextField(
            label: 'Notes',
            optional: true,
            controller: _notes,
            maxLines: 2,
            hint: 'Sensitive to cold, deep pocket distal…',
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => _edit(() {}),
          ),
          if (_notice != null) ...[
            const SizedBox(height: CruSpace.s8),
            Text(_notice!, style: CruType.subhead.tint(c.redText)),
          ],
          const SizedBox(height: CruSpace.s14),
          Row(
            children: [
              if (_dirty)
                CruLink(
                  label: 'Undo changes',
                  onPressed: () => setState(() => _draftFor = null),
                ),
              const Spacer(),
              CruButton(
                label: _saving ? 'Saving…' : 'Save finding',
                onPressed: _dirty && !_saving ? _save : null,
              ),
            ],
          ),
        ],
      ),
    );

    final endoCard = _EndoCard(
      record: endo,
      onOpen: () => showEndoDialog(context, p, existing: endo, tooth: _tooth),
    );
    final perioCard = _PerioCard(
      spec: spec,
      perio: perio,
      examAt: exam?.recordedAt,
      onOpen: _openPerio,
    );

    const gap = SizedBox(height: CruSpace.s16, width: CruSpace.s16);
    final middle = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [history, gap, tiles, gap, planCard],
    );
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [record, gap, endoCard, gap, perioCard],
    );
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w >= 1060) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              left,
              gap,
              Expanded(child: middle),
              gap,
              SizedBox(width: 340, child: right),
            ],
          );
        }
        if (w >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              left,
              gap,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [middle, gap, right],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: left),
            gap,
            middle,
            gap,
            right,
          ],
        );
      },
    );

    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _discardOk() && context.mounted) Navigator.of(context).pop();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
            if (_dirty && !_saving) _save();
          },
        },
        child: Dialog(
          backgroundColor: c.canvas,
          surfaceTintColor: c.canvas.withValues(alpha: 0),
          insetPadding: const EdgeInsets.all(CruSpace.s24),
          shape: cruShape(CruRadius.card, side: BorderSide(color: c.hairline)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 1280,
              maxHeight: size.height - CruSpace.s24 * 2,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, gap, body],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What the picked surfaces are shaded in: decay amber, work done
  /// green, otherwise the accent.
  Color _tone(CruColors c) {
    if (_condition == ToothCondition.caries ||
        _condition == ToothCondition.fractured) {
      return c.amberText;
    }
    if (_treatment != null || _condition == ToothCondition.restored) {
      return c.greenText;
    }
    return c.accent;
  }
}

// ================================================================= header

class _Header extends StatelessWidget {
  const _Header({
    required this.tooth,
    required this.numbering,
    required this.patientName,
    required this.state,
    required this.facts,
  });

  final String tooth;
  final ToothNumbering numbering;
  final String patientName;
  final ToothState state;
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          ToothBadge(tooth: tooth, state: state),
          const SizedBox(width: CruSpace.s14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DentalChart.name(tooth),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.title2.tint(c.label),
                ),
                Text(
                  'Tooth ${toothLabel(tooth, numbering)} · $patientName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tint(c.label2),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s24),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: CruSpace.s32,
              runSpacing: CruSpace.s8,
              children: [
                for (final (label, value) in facts)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: CruType.caption.tint(c.label3)),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CruType.subhead.w500.tint(c.label),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s16),
          CruIconButton(
            icon: CruIcons.close,
            size: CruSize.squareButton,
            iconSize: 18,
            semanticLabel: 'Close',
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(text, style: CruType.headline.tint(c.label)),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

// ============================================================ tooth column

/// The number rail and the tooth drawn three ways, with the surface
/// toggles under it.
class _ToothColumn extends StatelessWidget {
  const _ToothColumn({
    required this.tooth,
    required this.data,
    required this.draft,
    required this.surfaces,
    required this.tone,
    required this.perio,
    required this.numbering,
    required this.onTooth,
    required this.onSurface,
  });

  final String tooth;
  final ToothChartData data;
  final ToothVisual draft;
  final Set<ToothSurface> surfaces;
  final Color tone;
  final PerioTooth? perio;
  final ToothNumbering numbering;
  final ValueChanged<String> onTooth;
  final ValueChanged<ToothSurface> onSurface;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final spec = ToothSpec.of(tooth);
    final (upper, lower) = ToothSpec.arches(child: spec.primary);
    int key(String t) {
      if (numbering == ToothNumbering.fdi) return int.parse(t);
      final l = toothLabel(t, numbering);
      return int.tryParse(l) ?? l.codeUnitAt(0);
    }

    final teeth = [...upper, ...lower]
      ..sort((a, b) => key(a).compareTo(key(b)));
    final options = [
      ToothSurface.mesial,
      ToothSurface.distal,
      _anterior(spec) ? ToothSurface.incisal : ToothSurface.occlusal,
      ToothSurface.buccal,
      ToothSurface.lingual,
      ToothSurface.cervical,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                for (var i = 0; i < teeth.length; i++) ...[
                  if (i > 0 && teeth[i][0] != teeth[i - 1][0])
                    Container(
                      width: 16,
                      height: 1,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: c.separator,
                    ),
                  _RailItem(
                    label: toothLabel(teeth[i], numbering),
                    state: data.of(teeth[i]).state,
                    selected: teeth[i] == tooth,
                    onTap: () => onTooth(teeth[i]),
                  ),
                ],
              ],
            ),
            const SizedBox(width: CruSpace.s8),
            Expanded(
              child: _ToothArt(
                spec: spec,
                visual: draft,
                surfaces: surfaces,
                tone: tone,
                perio: perio,
                onSurface: onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s12),
        Padding(
          padding: const EdgeInsets.only(left: CruSpace.s6),
          child: Text('Surfaces', style: CruType.groupLabel.tint(c.label3)),
        ),
        const SizedBox(height: CruSpace.s6),
        Padding(
          padding: const EdgeInsets.only(left: CruSpace.s6),
          child: DentalChipWrap<ToothSurface>(
            options: options,
            label: DentalChart.surfaceLetter,
            isSelected: surfaces.contains,
            onTap: onSurface,
          ),
        ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.state,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final ToothState state;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fg = selected
        ? c.onAccent
        : switch (state) {
            ToothState.needsCare => c.amberText,
            ToothState.treated => c.greenText,
            ToothState.missing || ToothState.notErupted => c.label3,
            ToothState.healthy => c.label2,
          };
    return CruPressable(
      onTap: onTap,
      semanticLabel: 'Tooth $label',
      scaleOnPress: false,
      builder: (context, hovered) => Container(
        width: 36,
        height: 17,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: selected
              ? c.accent
              : (hovered ? c.hoverFill : c.surface.withValues(alpha: 0)),
          shape: const StadiumBorder(),
        ),
        child: Text(label, style: CruType.caption.w600.tabular.tint(fg)),
      ),
    );
  }
}

const double _artHeight = 572;

/// The drawings sit a little right of centre, clear of their captions.
const double _artShift = 14;

/// Where the three drawings sit, and the surface regions of the top view.
class _ArtGeometry {
  _ArtGeometry(this.width, this.spec) {
    const sideH = _artHeight * 0.39;
    top = Rect.fromLTWH(0, 0, width, sideH);
    occlusal = Rect.fromLTWH(0, sideH, width, _artHeight - sideH * 2);
    bottom = Rect.fromLTWH(0, _artHeight - sideH, width, sideH);
    k = math.min(
      (sideH - 20) / (spec.crown + spec.root),
      width * 0.52 / spec.md,
    );
    shape = ToothShape(spec, k);

    final ko = math.min(
      occlusal.height * 0.74 / spec.bl,
      width * 0.52 / spec.md,
    );
    final a = spec.md * ko / 2;
    final b = spec.bl * ko / 2;
    center = Offset(width / 2 + _artShift, occlusal.center.dy);
    final mx = spec.patientRight ? -1.0 : 1.0;
    final by = spec.upper ? 1.0 : -1.0;
    // Unit shape with the buccal side up and mesial left, placed so the
    // top side matches the view above it and mesial faces the midline.
    at = (double x, double y) => center + Offset(x * a * mx, y * b * by);
    final unit = switch (spec.kind) {
      ToothKind.centralIncisor || ToothKind.lateralIncisor => const [
        Offset(-1, -0.55),
        Offset(-0.55, -1),
        Offset(0.55, -1),
        Offset(1, -0.55),
        Offset(0.55, 0.35),
        Offset(0.18, 0.95),
        Offset(-0.18, 0.95),
        Offset(-0.55, 0.35),
      ],
      ToothKind.canine => const [
        Offset(-1, -0.25),
        Offset(-0.45, -0.95),
        Offset(0.45, -0.95),
        Offset(1, -0.25),
        Offset(0.55, 0.5),
        Offset(0, 1),
        Offset(-0.55, 0.5),
      ],
      ToothKind.premolar => _superellipse(2.4),
      ToothKind.molar => _superellipse(3.4),
    };
    outline = ToothShape.smoothClosed([for (final u in unit) at(u.dx, u.dy)]);
    inner = _anterior(spec)
        ? (Path()..addOval(
            Rect.fromCenter(
              center: at(0, spec.kind == ToothKind.canine ? -0.12 : -0.2),
              width: a * (spec.kind == ToothKind.canine ? 0.9 : 1.35),
              height: b * 0.34,
            ),
          ))
        : ToothShape.smoothClosed([
            for (final u in unit) at(u.dx * 0.5, u.dy * 0.46),
          ]);
    Path wedge(Offset p1, Offset p2) => Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    // Through the box's corners, far enough out to cover the outline.
    Offset corner(double sx, double sy) => center + Offset(sx * a, sy * b) * 3;
    final tl = corner(-1, -1),
        tr = corner(1, -1),
        bl = corner(-1, 1),
        br = corner(1, 1);
    final ring = Path.combine(PathOperation.difference, outline, inner);
    Path region(Path w) => Path.combine(PathOperation.intersect, ring, w);
    final screenTop = region(wedge(tl, tr));
    final screenBottom = region(wedge(bl, br));
    final screenLeft = region(wedge(tl, bl));
    final screenRight = region(wedge(tr, br));
    final mesialLeft = !spec.patientRight;
    regions = {
      _anterior(spec) ? ToothSurface.incisal : ToothSurface.occlusal: inner,
      spec.upper ? ToothSurface.buccal : ToothSurface.lingual: screenTop,
      spec.upper ? ToothSurface.lingual : ToothSurface.buccal: screenBottom,
      mesialLeft ? ToothSurface.mesial : ToothSurface.distal: screenLeft,
      mesialLeft ? ToothSurface.distal : ToothSurface.mesial: screenRight,
    };
    dividers = [
      for (final p in [tl, tr, bl, br]) (center, p),
    ];
    ringPath = ring;
  }

  final double width;
  final ToothSpec spec;
  late final Rect top;
  late final Rect occlusal;
  late final Rect bottom;
  late final double k;
  late final ToothShape shape;
  late final Offset center;

  /// Unit coordinates (buccal up, mesial left) to screen.
  late final Offset Function(double x, double y) at;
  late final Path outline;
  late final Path inner;
  late final Path ringPath;
  late final Map<ToothSurface, Path> regions;
  late final List<(Offset, Offset)> dividers;

  static List<Offset> _superellipse(double n) => [
    for (var i = 0; i < 16; i++)
      () {
        final t = i / 16 * 2 * math.pi;
        final c = math.cos(t), s = math.sin(t);
        return Offset(
          c.sign * math.pow(c.abs(), 2 / n).toDouble(),
          s.sign * math.pow(s.abs(), 2 / n).toDouble(),
        );
      }(),
  ];

  ToothSurface? surfaceAt(Offset p) {
    if (!outline.contains(p)) return null;
    for (final e in regions.entries) {
      if (e.value.contains(p)) return e.key;
    }
    return null;
  }
}

class _ToothArt extends StatefulWidget {
  const _ToothArt({
    required this.spec,
    required this.visual,
    required this.surfaces,
    required this.tone,
    required this.perio,
    required this.onSurface,
  });

  final ToothSpec spec;
  final ToothVisual visual;
  final Set<ToothSurface> surfaces;
  final Color tone;
  final PerioTooth? perio;
  final ValueChanged<ToothSurface> onSurface;

  @override
  State<_ToothArt> createState() => _ToothArtState();
}

class _ToothArtState extends State<_ToothArt> {
  ToothSurface? _hover;
  _ArtGeometry? _geo;

  _ArtGeometry _geometry(double width) {
    final g = _geo;
    if (g != null && g.width == width && g.spec == widget.spec) return g;
    return _geo = _ArtGeometry(width, widget.spec);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final spec = widget.spec;
    final captionStyle = CruType.caption.tint(c.label3);
    final inner = spec.upper ? 'Palatal' : 'Lingual';
    return LayoutBuilder(
      builder: (context, constraints) {
        final geo = _geometry(constraints.maxWidth);
        return SizedBox(
          height: _artHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ArtPainter(
                    geo: geo,
                    visual: widget.visual,
                    surfaces: widget.surfaces,
                    hover: _hover,
                    tone: widget.tone,
                    perio: widget.perio,
                    colors: c,
                  ),
                ),
              ),
              Positioned.fill(
                child: MouseRegion(
                  cursor: _hover == null
                      ? MouseCursor.defer
                      : SystemMouseCursors.click,
                  onHover: (e) {
                    final s = geo.surfaceAt(e.localPosition);
                    if (s != _hover) setState(() => _hover = s);
                  },
                  onExit: (_) => setState(() => _hover = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final s = geo.surfaceAt(d.localPosition);
                      if (s != null) widget.onSurface(s);
                    },
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: Text(spec.upper ? 'Buccal' : inner, style: captionStyle),
              ),
              Positioned(
                left: 0,
                top: geo.occlusal.top + 4,
                child: Text(
                  _anterior(spec) ? 'Incisal' : 'Occlusal',
                  style: captionStyle,
                ),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: Text(spec.upper ? inner : 'Buccal', style: captionStyle),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter({
    required this.geo,
    required this.visual,
    required this.surfaces,
    required this.hover,
    required this.tone,
    required this.perio,
    required this.colors,
  });

  final _ArtGeometry geo;
  final ToothVisual visual;
  final Set<ToothSurface> surfaces;
  final ToothSurface? hover;
  final Color tone;
  final PerioTooth? perio;
  final CruColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final spec = geo.spec;
    final mx = spec.patientRight ? -1.0 : 1.0;
    // Upper tooth: cheek side above, palate below. Lower: tongue side
    // above, cheek below. Both with the crowns towards the middle.
    final topSites = spec.upper ? const [0, 1, 2] : const [3, 4, 5];
    final bottomSites = spec.upper ? const [3, 4, 5] : const [0, 1, 2];
    _side(
      canvas,
      geo.top,
      geo.top.bottom - 8,
      flipped: true,
      mx: mx,
      sites: topSites,
    );
    _side(
      canvas,
      geo.bottom,
      geo.bottom.top + 8,
      flipped: false,
      mx: mx,
      sites: bottomSites,
    );
    _occlusal(canvas);
  }

  /// The tooth side-on, biting edge at [edgeY], roots away from the middle.
  void _side(
    Canvas canvas,
    Rect zone,
    double edgeY, {
    required bool flipped,
    required double mx,
    required List<int> sites,
  }) {
    final c = colors;
    final k = geo.k;
    // Millimetre guides from the biting edge, every 2 mm.
    final guide = Paint()
      ..color = c.separator
      ..strokeWidth = 1;
    for (var mm = 2; mm * k < zone.height - 4; mm += 2) {
      final y = flipped ? edgeY - mm * k : edgeY + mm * k;
      for (var x = zone.left + 44; x < zone.right; x += 5) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 2, zone.right), y),
          guide,
        );
      }
    }
    canvas.save();
    canvas.translate(zone.center.dx + _artShift, edgeY);
    canvas.scale(mx, flipped ? -1 : 1);
    paintTooth(
      canvas,
      geo.shape,
      visual,
      c,
      look: ToothLook(down: flipped ? -1 : 1),
    );
    final t = perio;
    if (t != null) _perio(canvas, t, sites);
    canvas.restore();
  }

  /// Gum margin (gumShade) and pocket depth (amber band) at the three sites
  /// of this side: mesial, middle, distal.
  void _perio(Canvas canvas, PerioTooth t, List<int> sites) {
    final c = colors;
    final s = geo.shape;
    final pd = [for (final i in sites) t.pd[i]];
    final rec = [for (final i in sites) t.rec[i]];
    if (pd.every((v) => v == null)) return;
    int at(List<int?> l, int i) =>
        l[i] ?? l[1] ?? l.whereType<int>().firstOrNull ?? 0;
    final xs = [-s.cw * 0.9, 0.0, s.cw * 0.9];
    final margin = [
      for (var i = 0; i < 3; i++) Offset(xs[i], s.ch + at(rec, i) * s.k),
    ];
    final pocket = [
      for (var i = 0; i < 3; i++) Offset(xs[i], margin[i].dy + at(pd, i) * s.k),
    ];
    List<Offset> spread(List<Offset> p) => [
      Offset(-s.mw - 10, p[0].dy),
      ...p,
      Offset(s.mw + 10, p[2].dy),
    ];
    final m = _spline(spread(margin));
    final pk = _spline(spread(pocket));
    canvas.drawPath(
      Path()..addPolygon([...m, ...pk.reversed], true),
      Paint()..color = c.amber.withValues(alpha: 0.28),
    );
    canvas.drawPath(
      Path()..addPolygon(pk, false),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = c.amberText,
    );
    canvas.drawPath(
      Path()..addPolygon(m, false),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = c.gumShade,
    );
    for (var i = 0; i < 3; i++) {
      if (t.bop[sites[i]]) {
        canvas.drawCircle(pocket[i], 3.2, Paint()..color = c.redText);
      }
      if (t.sup[sites[i]]) {
        canvas.drawCircle(
          pocket[i],
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = c.amberText,
        );
      }
    }
  }

  /// The biting surface from above, split into its five surfaces.
  void _occlusal(Canvas canvas) {
    final c = colors;
    final eve = c.isEvening;
    final o = geo.outline;
    final b = o.getBounds();
    canvas.drawPath(
      o.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: eve ? 0.4 : 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      o,
      Paint()
        ..shader = ui.Gradient.radial(
          geo.center + Offset(-b.width * 0.08, -b.height * 0.1),
          math.max(b.width, b.height) * 0.62,
          [c.enamel, c.enamel, c.enamelShade],
          [0, 0.5, 1],
        ),
    );
    canvas.save();
    canvas.clipPath(o);
    canvas.drawPath(
      o,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = b.width * 0.16
        ..color = c.enamelEdge.withValues(alpha: eve ? 0.5 : 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, b.width * 0.06),
    );
    final glow = Paint()
      ..color = Colors.white.withValues(alpha: eve ? 0.14 : 0.6)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, b.width * 0.07);
    final spec = geo.spec;
    final cusps = switch (spec.kind) {
      ToothKind.molar => const [
        Offset(-0.45, -0.45),
        Offset(0.45, -0.45),
        Offset(-0.45, 0.45),
        Offset(0.45, 0.45),
      ],
      ToothKind.premolar => const [Offset(0, -0.48), Offset(0, 0.5)],
      ToothKind.canine => const [Offset(0, -0.3)],
      _ => const <Offset>[],
    };
    for (final u in cusps) {
      canvas.drawCircle(geo.at(u.dx, u.dy), b.width * 0.13, glow);
    }
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = c.enamelEdge.withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
    Path line(List<Offset> u) =>
        Path()..addPolygon([for (final p in u) geo.at(p.dx, p.dy)], false);
    switch (spec.kind) {
      case ToothKind.molar:
        canvas.drawPath(
          line(const [
            Offset(-0.6, 0.02),
            Offset(-0.2, 0.1),
            Offset(0.15, -0.06),
            Offset(0.6, 0.02),
          ]),
          groove,
        );
        canvas.drawPath(
          line(const [Offset(-0.02, -0.04), Offset(0, -0.62)]),
          groove,
        );
        canvas.drawPath(
          line(const [Offset(0.08, 0.04), Offset(0.1, 0.62)]),
          groove,
        );
      case ToothKind.premolar:
        canvas.drawPath(
          line(const [
            Offset(-0.55, 0.02),
            Offset(0, -0.04),
            Offset(0.55, 0.02),
          ]),
          groove,
        );
      case ToothKind.centralIncisor || ToothKind.lateralIncisor:
        canvas.drawPath(
          line(const [Offset(-0.75, -0.25), Offset(0.75, -0.25)]),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = glow.color
            ..maskFilter = glow.maskFilter,
        );
      case ToothKind.canine:
        break;
    }
    canvas.restore();

    // Picked surfaces, then the hovered one.
    for (final e in geo.regions.entries) {
      if (surfaces.contains(e.key)) {
        canvas.drawPath(e.value, Paint()..color = tone.withValues(alpha: 0.34));
      }
    }
    final h = hover;
    if (h != null && geo.regions[h] != null) {
      canvas.drawPath(
        geo.regions[h]!,
        Paint()
          ..color = c.accent.withValues(
            alpha: surfaces.contains(h) ? 0.14 : 0.16,
          ),
      );
    }
    // Where the surfaces meet.
    final line2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = c.enamelEdge.withValues(alpha: 0.45);
    canvas.save();
    canvas.clipPath(geo.ringPath);
    for (final (a, z) in geo.dividers) {
      canvas.drawLine(a, z, line2);
    }
    canvas.restore();
    canvas.drawPath(geo.inner, line2);
    canvas.drawPath(
      o,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = c.enamelEdge.withValues(alpha: 0.65),
    );
  }

  /// Points along a smooth curve through [p] (Catmull-Rom).
  static List<Offset> _spline(List<Offset> p) {
    final out = <Offset>[];
    for (var i = 0; i < p.length - 1; i++) {
      final p0 = p[math.max(0, i - 1)];
      final p1 = p[i];
      final p2 = p[i + 1];
      final p3 = p[math.min(p.length - 1, i + 2)];
      for (var j = 0; j < 8; j++) {
        final t = j / 8;
        final t2 = t * t, t3 = t2 * t;
        out.add(
          (p1 * 2 +
                  (p2 - p0) * t +
                  (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                  (-p0 + p1 * 3 - p2 * 3 + p3) * t3) *
              0.5,
        );
      }
    }
    out.add(p.last);
    return out;
  }

  // The draft and the perio readings are rebuilt on every change, and
  // one tooth is cheap to paint.
  @override
  bool shouldRepaint(_ArtPainter old) => true;
}

// ================================================================== tiles

/// What was found, or what was done, as big picture tiles; each shows
/// this tooth the way the chart will draw it.
class _FindingTiles extends StatelessWidget {
  const _FindingTiles({
    required this.tooth,
    required this.grid,
    required this.condition,
    required this.treatment,
    required this.onGrid,
    required this.onCondition,
    required this.onTreatment,
  });

  final String tooth;
  final _Grid grid;
  final ToothCondition? condition;
  final ToothTreatment? treatment;
  final ValueChanged<_Grid> onGrid;
  final ValueChanged<ToothCondition?> onCondition;
  final ValueChanged<ToothTreatment?> onTreatment;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final spec = ToothSpec.of(tooth);
    final tiles = grid == _Grid.condition
        ? [
            for (final o in const [null, ...ToothCondition.values])
              _Tile(
                spec: spec,
                visual: _visual(tooth, o, null),
                label: o == null ? 'Healthy' : DentalChart.conditionLabel(o),
                selected: o == condition,
                onTap: () => onCondition(o),
              ),
          ]
        : [
            for (final o in const [null, ...ToothTreatment.values])
              _Tile(
                spec: spec,
                visual: _visual(tooth, null, o),
                label: o == null
                    ? 'Nothing done'
                    : DentalChart.treatmentLabel(o),
                selected: o == treatment,
                onTap: () => onTreatment(o),
              ),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  grid == _Grid.condition ? 'What you see' : 'What was done',
                  style: CruType.headline.tint(c.label),
                ),
              ),
            ),
            CruSegmentedControl<_Grid>(
              semanticLabel: 'Finding',
              segments: const [
                CruSegment(_Grid.condition, 'Condition'),
                CruSegment(_Grid.treatment, 'Treatment'),
              ],
              selected: grid,
              onChanged: onGrid,
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s12),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = CruSpace.s12;
            final cols = constraints.maxWidth >= 440 ? 4 : 3;
            final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final t in tiles) SizedBox(width: w, child: t)],
            );
          },
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.spec,
    required this.visual,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ToothSpec spec;
  final ToothVisual visual;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: 116,
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          decoration: ShapeDecoration(
            color: selected
                ? c.accent
                : (hovered
                      ? Color.alphaBlend(c.hoverFill, c.surface)
                      : c.surface),
            shape: cruShape(
              CruRadius.largeTile,
              side: selected ? BorderSide.none : BorderSide(color: c.hairline),
            ),
            shadows: selected ? null : c.cardShadow,
          ),
          child: Column(
            children: [
              Expanded(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _MiniTooth(spec: spec, visual: visual, colors: c),
                ),
              ),
              const SizedBox(height: CruSpace.s6),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: CruType.subhead.w600.tint(
                  selected ? c.onAccent : c.label,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTooth extends CustomPainter {
  _MiniTooth({required this.spec, required this.visual, required this.colors});

  final ToothSpec spec;
  final ToothVisual visual;
  final CruColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    const shown = 0.5;
    final len = spec.crown + spec.root * shown;
    final k = math.min((size.height - 4) / len, size.width * 0.46 / spec.md);
    canvas.save();
    canvas.translate(size.width / 2, (size.height - len * k) / 2);
    paintTooth(
      canvas,
      ToothShape(spec, k),
      visual,
      colors,
      look: const ToothLook(rootShown: shown, fadeRoots: true),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MiniTooth old) =>
      old.spec != spec ||
      old.colors != colors ||
      old.visual.condition != visual.condition ||
      old.visual.treatment != visual.treatment;
}

// ============================================================ endo, perio

/// Endodontic test icons (24-unit viewBox).
abstract final class _TestIcons {
  static const cold = CruIconData(
    'M12 3V21M4.2 7.5L19.8 16.5M4.2 16.5L19.8 7.5M9.5 4.6L12 6.2L14.5 4.6M9.5 19.4L12 17.8L14.5 19.4',
  );
  static const heat = CruIconData(
    'M12 21C8.4 21 6 18.5 6 15.2C6 12 8.4 10.2 9.4 7.5C9.8 9.2 10.8 10.3 11.8 10.8'
    'C12 7.8 13.3 5 15.5 3C15.9 5.9 17.1 7.6 18.2 9.3C19.2 10.8 20 12.3 20 14.6'
    'C20 18.2 16.4 21 12 21Z',
  );
  static const bolt = CruIconData('M13 3L5 13.5H11L10 21L18 10.5H12L13 3Z');
  static const tap = CruIconData('M5 19L13 11M11 6.5L15.5 2L20 6.5L15.5 11Z');
  static const touch = CruIconData(
    'M9 12V5.5A1.5 1.5 0 0 1 12 5.5V11M12 10.5V9A1.5 1.5 0 0 1 15 9V11.5'
    'M15 10.5A1.5 1.5 0 0 1 18 10.5V14C18 18 15.5 21 12 21C9.8 21 8.3 19.9 7.3 18.2'
    'L5.2 14.6A1.4 1.4 0 0 1 7.6 13.2L9 15',
  );
}

class _EndoCard extends StatelessWidget {
  const _EndoCard({required this.record, required this.onOpen});

  final DentalRecord? record;
  final VoidCallback onOpen;

  static const _abnormal = {
    'No response',
    'Lingering',
    'Exaggerated',
    'Tender',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final r = record;
    final raw = r?.data['tests'];
    final results = raw is Map ? raw : const {};
    final tests = [
      ('Cold', 'Cold', _TestIcons.cold, c.tealText),
      ('Heat', 'Heat', _TestIcons.heat, c.redText),
      ('Percussion', 'Percussion', _TestIcons.tap, c.label2),
      ('EPT', 'Electric pulp test', _TestIcons.bolt, c.amberText),
      ('Palpation', 'Palpation', _TestIcons.touch, c.accentText),
    ];
    final diagnosis = r == null
        ? ''
        : [
            r.str('pulpal'),
            r.str('periapical'),
          ].where((s) => s.isNotEmpty).join(' · ');
    return CruCard(
      semanticLabel: 'Endodontic tests',
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title(
            'Endodontic tests',
            trailing: Text(
              r == null ? 'Not tested' : DentalFormat.date(r.recordedAt),
              style: CruType.caption.tabular.tint(c.label3),
            ),
          ),
          const SizedBox(height: CruSpace.s6),
          for (final (key, name, icon, tint) in tests)
            _TestRow(
              name: name,
              icon: icon,
              tint: tint,
              value: results[key]?.toString(),
              abnormal: _abnormal.contains(results[key]?.toString()),
              onTap: onOpen,
            ),
          const SizedBox(height: CruSpace.s6),
          Text(
            r == null
                ? 'No endo record for this tooth. Pick a test to start one.'
                : (diagnosis.isEmpty ? 'No diagnosis yet.' : diagnosis),
            style: CruType.caption.tint(r == null ? c.label3 : c.label2),
          ),
        ],
      ),
    );
  }
}

class _TestRow extends StatelessWidget {
  const _TestRow({
    required this.name,
    required this.icon,
    required this.tint,
    required this.value,
    required this.abnormal,
    required this.onTap,
  });

  final String name;
  final CruIconData icon;
  final Color tint;
  final String? value;
  final bool abnormal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      semanticLabel: '$name: ${value ?? 'not tested'}',
      scaleOnPress: false,
      builder: (context, hovered) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s6),
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : c.surface.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            CruIcon(icon, size: 16, color: tint),
            const SizedBox(width: CruSpace.s8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CruType.subhead.tint(c.label),
              ),
            ),
            Text(
              value ?? '—',
              style: CruType.subhead.w500.tint(
                value == null ? c.label3 : (abnormal ? c.amberText : c.label2),
              ),
            ),
            const SizedBox(width: CruSpace.s4),
            CruIcon(CruIcons.chevronRight, size: 14, color: c.label3),
          ],
        ),
      ),
    );
  }
}

class _PerioCard extends StatelessWidget {
  const _PerioCard({
    required this.spec,
    required this.perio,
    required this.examAt,
    required this.onOpen,
  });

  final ToothSpec spec;
  final PerioTooth? perio;
  final DateTime? examAt;
  final VoidCallback onOpen;

  static const _roman = ['I', 'II', 'III', 'IV'];

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = perio;
    final inner = spec.upper ? 'palatal' : 'lingual';
    String side(int i) =>
        i < 3 ? 'Buccal' : '${inner[0].toUpperCase()}${inner.substring(1)}';
    String site(int i) => switch (i % 3) {
      0 => 'Mesial',
      2 => 'Distal',
      _ => 'Mid',
    };

    // Rows and columns as the drawing on the left shows them.
    final mesialLeft = !spec.patientRight;
    List<int> row(List<int> s) => mesialLeft ? s : s.reversed.toList();
    final top = row(spec.upper ? [0, 1, 2] : [3, 4, 5]);
    final bottom = row(spec.upper ? [3, 4, 5] : [0, 1, 2]);
    Widget cells(List<int> sites) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(side(sites.first), style: CruType.groupLabel.tint(c.label3)),
        const SizedBox(height: CruSpace.s4),
        Row(
          children: [
            for (var j = 0; j < 3; j++) ...[
              if (j > 0) const SizedBox(width: CruSpace.s8),
              Expanded(
                child: _PerioCell(
                  site: site(sites[j]),
                  side: side(sites[j]),
                  pd: t!.pd[sites[j]],
                  rec: t.rec[sites[j]],
                  bleeding: t.bop[sites[j]],
                  onTap: onOpen,
                ),
              ),
            ],
          ],
        ),
      ],
    );
    final extra = t == null
        ? ''
        : [
            if (t.mobility != null) 'Mobility ${t.mobility}',
            if (t.furcation != null && t.furcation! >= 1 && t.furcation! <= 4)
              'Furcation ${_roman[t.furcation! - 1]}',
          ].join(' · ');
    return CruCard(
      semanticLabel: 'Periodontal',
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title(
            'Periodontal',
            trailing: Text(
              examAt == null ? 'No exam yet' : DentalFormat.date(examAt!),
              style: CruType.caption.tabular.tint(c.label3),
            ),
          ),
          const SizedBox(height: CruSpace.s10),
          if (t == null) ...[
            Text(
              spec.primary
                  ? 'Perio charting covers permanent teeth.'
                  : 'No perio readings for this tooth yet.',
              style: CruType.subhead.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s6),
            Align(
              alignment: Alignment.centerLeft,
              child: CruLink(label: 'Open perio chart', onPressed: onOpen),
            ),
          ] else ...[
            cells(top),
            const SizedBox(height: CruSpace.s10),
            cells(bottom),
            const SizedBox(height: CruSpace.s10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      'Pocket | recession, mm',
                      if (extra.isNotEmpty) extra,
                    ].join(' · '),
                    style: CruType.caption.tint(c.label3),
                  ),
                ),
                CruLink(label: 'Open perio chart', onPressed: onOpen),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PerioCell extends StatelessWidget {
  const _PerioCell({
    required this.site,
    required this.side,
    required this.pd,
    required this.rec,
    required this.bleeding,
    required this.onTap,
  });

  final String site;
  final String side;
  final int? pd;
  final int? rec;
  final bool bleeding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final depth = pd;
    final pdColor = depth == null
        ? c.label3
        : (depth >= 6 ? c.redText : (depth >= 4 ? c.amberText : c.label));
    return CruPressable(
      onTap: onTap,
      semanticLabel:
          '$site $side: pocket ${pd ?? 'not probed'}, recession ${rec ?? 'not probed'}'
          '${bleeding ? ', bleeding' : ''}',
      scaleOnPress: false,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 7),
        decoration: ShapeDecoration(
          color: hovered ? Color.alphaBlend(c.hoverFill, c.surface) : c.surface,
          shape: cruShape(
            CruRadius.control,
            side: BorderSide(color: c.hairline),
          ),
          shadows: c.cardShadow,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (bleeding) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: ShapeDecoration(
                      color: c.redText,
                      shape: const CircleBorder(),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s4),
                ],
                Text(
                  '${pd ?? '–'}',
                  style: CruType.callout.w600.tabular.tint(pdColor),
                ),
                Container(
                  width: 1,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: CruSpace.s6),
                  color: c.separator,
                ),
                Text(
                  '${rec ?? '–'}',
                  style: CruType.callout.tabular.tint(c.label2),
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s2),
            Text(
              site,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CruType.caption.tint(c.label3),
            ),
          ],
        ),
      ),
    );
  }
}
