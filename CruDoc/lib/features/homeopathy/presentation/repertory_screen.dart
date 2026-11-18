import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/utils/app_notice.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/homeopathy/data/materia_medica_data.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/repertorization.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/repertory_engine.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/repertory_registry.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/rubric.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/materia_medica_screen.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_form_helpers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/repertory_grid.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/repertory_suggest_sheet.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Widest the page grows on desktop; it reads as a column.
const double _maxWidth = 760;

/// Rubrics listed under the search box before the physician narrows it.
const int _pickerLimit = 30;

const _disclaimer =
    'Aid to analysis — selection and judgement stay with the '
    'physician';

enum _Tab { rubrics, result, saved }

const _weightNames = {1: 'Normal', 2: 'Important', 3: 'Characteristic'};

/// Mini repertory for one patient: pick rubrics, see the remedy grid, save
/// the repertorization. Nothing is written to the case sheet.
class RepertoryScreen extends ConsumerStatefulWidget {
  const RepertoryScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final String patientId;

  /// Used only to strip the name from text sent to the AI.
  final String patientName;

  static Future<void> open(
    BuildContext context, {
    required String patientId,
    required String patientName,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          RepertoryScreen(patientId: patientId, patientName: patientName),
    ),
  );

  @override
  ConsumerState<RepertoryScreen> createState() => _RepertoryScreenState();
}

class _RepertoryScreenState extends ConsumerState<RepertoryScreen> {
  final _search = TextEditingController();
  final _note = TextEditingController();
  _Tab _tab = _Tab.rubrics;
  String? _chapter;
  List<SelectedRubric> _selected = [];
  String? _chosen;
  Repertorization? _editing;
  bool _saving = false;

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  RecKey get _key =>
      (patientId: widget.patientId, kind: RecKind.homeoRepertorization);

  bool _has(String id) => _selected.any((s) => s.id == id);

  void _toggle(Rubric r) => setState(() {
    if (_has(r.id)) {
      _selected = [
        for (final s in _selected)
          if (s.id != r.id) s,
      ];
    } else {
      _selected = [..._selected, SelectedRubric(r.id)];
    }
  });

  void _cycleWeight(SelectedRubric s) => setState(() {
    final next = s.weight >= 3 ? 1 : s.weight + 1;
    _selected = [
      for (final e in _selected)
        if (e.id == s.id) e.withWeight(next) else e,
    ];
  });

  void _remove(String id) => setState(() {
    _selected = [
      for (final s in _selected)
        if (s.id != id) s,
    ];
  });

  Future<void> _suggest() async {
    final ids = await showRepertorySuggestSheet(
      context,
      patientId: widget.patientId,
      patientNames: [widget.patientName],
      alreadyAdded: {for (final s in _selected) s.id},
    );
    if (ids == null || ids.isEmpty || !mounted) return;
    setState(() {
      for (final id in ids) {
        if (!_has(id) && Repertory.instance.byId(id) != null) {
          _selected = [..._selected, SelectedRubric(id)];
        }
      }
    });
  }

  void _startNew() => setState(() {
    _selected = [];
    _chosen = null;
    _editing = null;
    _note.clear();
    _tab = _Tab.rubrics;
  });

  void _open(Repertorization r) => setState(() {
    final rep = Repertory.instance;
    _selected = [
      for (final s in r.rubrics)
        if (rep.byId(s.id) != null) s,
    ];
    _chosen = r.chosenRemedy;
    _note.text = r.note;
    _editing = r;
    _tab = _Tab.result;
  });

  void _notice(String text) {
    if (AppNotices.hosted) {
      AppNotices.show(AppNotice(text: text));
    } else {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _save() async {
    if (_saving || _selected.isEmpty) return;
    setState(() => _saving = true);
    try {
      final data = Repertorization.toData(
        rubrics: _selected,
        note: _note.text.trim(),
        chosenRemedy: _chosen,
      );
      final rec = _editing != null
          ? _editing!.record.copyWith(data: data)
          : DentalRecord.create(
              widget.patientId,
              RecKind.homeoRepertorization,
              data,
            );
      await saveDentalRecord(ref, rec);
      if (!mounted) return;
      setState(() {
        _editing = Repertorization.fromRecord(rec);
        _tab = _Tab.saved;
      });
      _notice('Repertorization saved.');
    } catch (e) {
      if (mounted) {
        AppNotice.error(
          context,
          "Couldn't save the repertorization.",
          error: e,
          onRetry: _save,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Repertorization r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: 'Delete this repertorization?',
        leading: const CruIconTile(
          icon: CruIcons.warning,
          tone: CruTileTone.neutral,
        ),
        submitLabel: 'Delete',
        onSubmit: () => Navigator.of(ctx).pop(true),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
          child: Text(
            'The ${DateFormat('d MMM yyyy').format(r.date)} repertorization '
            'is removed. The case sheet is not changed.',
            style: CruType.text.tint(ctx.cru.label2),
          ),
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    await deleteDentalRecord(ref, r.record);
    if (!mounted) return;
    if (_editing?.id == r.id) setState(() => _editing = null);
  }

  void _openRemedy(String abbr) {
    final entry = materiaMedicaFor(abbr);
    if (entry != null) MateriaMedicaDetailScreen.open(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final showBar = _tab != _Tab.saved;

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CruSpace.s12,
                    vertical: CruSpace.s8,
                  ),
                  child: Row(
                    children: [
                      CruIconButton(
                        icon: CruIcons.chevronLeft,
                        onPressed: () => Navigator.pop(context),
                        semanticLabel: 'Back',
                      ),
                      const SizedBox(width: CruSpace.s4),
                      Expanded(
                        child: Text(
                          'Repertory',
                          style: CruType.title2.tint(c.label),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _disclaimer,
                      style: CruType.caption.tint(c.label3),
                    ),
                  ),
                ),
                const SizedBox(height: CruSpace.s12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: CruSpace.s20),
                  child: CruSegmentedControl<_Tab>(
                    expand: true,
                    semanticLabel: 'Repertory view',
                    selected: _tab,
                    onChanged: (t) => setState(() => _tab = t),
                    segments: [
                      const CruSegment(_Tab.rubrics, 'Rubrics'),
                      CruSegment(
                        _Tab.result,
                        _selected.isEmpty
                            ? 'Result'
                            : 'Result (${_selected.length})',
                      ),
                      const CruSegment(_Tab.saved, 'Saved'),
                    ],
                  ),
                ),
                if (_editing != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CruSpace.s20,
                      CruSpace.s8,
                      CruSpace.s20,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Editing the repertorization of '
                            '${DateFormat('d MMM yyyy').format(_editing!.date)}',
                            style: CruType.caption.tabular.tint(c.label2),
                          ),
                        ),
                        CruLink(label: 'Start new', onPressed: _startNew),
                      ],
                    ),
                  ),
                const SizedBox(height: CruSpace.s12),
                Expanded(
                  child: switch (_tab) {
                    _Tab.rubrics => _rubricsTab(context),
                    _Tab.result => _resultTab(context),
                    _Tab.saved => _savedTab(context),
                  },
                ),
                if (showBar)
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      CruSpace.s20,
                      CruSpace.s12,
                      CruSpace.s20,
                      CruSpace.s12 + MediaQuery.of(context).padding.bottom,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border(top: BorderSide(color: c.hairline)),
                    ),
                    child: _tab == _Tab.rubrics
                        ? CruButton(
                            label: _selected.isEmpty
                                ? 'Show result'
                                : 'Show result (${_selected.length} rubrics)',
                            expand: true,
                            onPressed: _selected.isEmpty
                                ? null
                                : () => setState(() => _tab = _Tab.result),
                          )
                        : CruButton(
                            label: _saving
                                ? 'Saving...'
                                : (_editing == null
                                      ? 'Save repertorization'
                                      : 'Save changes'),
                            expand: true,
                            onPressed: _selected.isEmpty || _saving
                                ? null
                                : _save,
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Rubrics --------------------------------------------------------------

  Widget _rubricsTab(BuildContext context) {
    final c = context.cru;
    final rep = Repertory.instance;
    final totality = _totalityTexts();
    final hits = rep.search(_search.text, chapter: _chapter);
    final shown = hits.take(_pickerLimit).toList();

    OutlineInputBorder ring(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(CruRadius.control),
      borderSide: BorderSide(color: color, width: 1.5),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s20,
        0,
        CruSpace.s20,
        CruSpace.s24,
      ),
      children: [
        if (totality.isNotEmpty) ...[
          CruCard(
            padding: const EdgeInsets.all(CruSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Characteristic symptoms (from the totality)',
                  style: CruType.subhead.w600.tint(c.label2),
                ),
                const SizedBox(height: CruSpace.s8),
                for (final t in totality)
                  Padding(
                    padding: const EdgeInsets.only(bottom: CruSpace.s4),
                    child: Text(t, style: CruType.text.tint(c.label)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: CruSpace.cardGap),
        ],
        Text(
          _selected.isEmpty
              ? 'Rubrics in this case'
              : 'Rubrics in this case (${_selected.length})',
          style: CruType.headline.tint(c.label),
        ),
        const SizedBox(height: CruSpace.s8),
        if (_selected.isEmpty)
          Text(
            'None yet. Search the rubrics below, or let the AI suggest some '
            'from the case sheet.',
            style: CruType.text.tint(c.label2),
          )
        else
          for (final s in _selected)
            if (rep.byId(s.id) case final r?)
              _SelectedRow(
                rubric: r,
                weight: s.weight,
                onWeight: () => _cycleWeight(s),
                onRemove: () => _remove(s.id),
              ),
        const SizedBox(height: CruSpace.cardGap),
        Row(
          children: [
            Expanded(
              child: Text('Add rubrics', style: CruType.headline.tint(c.label)),
            ),
            _AiCapsule(label: 'Suggest from case', onTap: _suggest),
          ],
        ),
        const SizedBox(height: CruSpace.s12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: CruType.input.tint(c.label),
          cursorColor: c.accent,
          decoration: InputDecoration(
            hintText: 'Search by words, e.g. fear dark',
            hintStyle: CruType.input.tint(c.label3),
            prefixIcon: Padding(
              padding: const EdgeInsets.all(CruSpace.s12),
              child: CruIcon(
                CruIcons.search,
                size: CruSpace.s16,
                color: c.label3,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s12,
              vertical: CruSpace.s12,
            ),
            filled: true,
            fillColor: c.inset,
            border: ring(c.inset.withValues(alpha: 0)),
            enabledBorder: ring(c.inset.withValues(alpha: 0)),
            focusedBorder: ring(c.accent),
          ),
        ),
        const SizedBox(height: CruSpace.s12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            HomeopathyChoiceChip(
              label: 'All',
              selected: _chapter == null,
              onSelected: (_) => setState(() => _chapter = null),
            ),
            for (final ch in rep.chapters)
              HomeopathyChoiceChip(
                label: ch,
                selected: _chapter == ch,
                onSelected: (sel) => setState(() => _chapter = sel ? ch : null),
              ),
          ],
        ),
        const SizedBox(height: CruSpace.s12),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CruSpace.s16),
            child: Text(
              'No rubric matches.',
              style: CruType.text.tint(c.label2),
              textAlign: TextAlign.center,
            ),
          ),
        for (final r in shown)
          _PickerRow(rubric: r, added: _has(r.id), onTap: () => _toggle(r)),
        if (hits.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: CruSpace.s4),
            child: Text(
              'Showing ${shown.length} of ${hits.length}. Type to narrow.',
              style: CruType.caption.tabular.tint(c.label3),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  /// Characteristic and mental-general symptoms of the saved totality, if
  /// the physician made one. Nothing when there is none.
  List<String> _totalityTexts() {
    final recs = ref.watch(patientRecordsProvider(_totalityKey)).value;
    if (recs == null || recs.isEmpty) return const [];
    final raw = recs.first.data['items'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map &&
            e['skip'] != true &&
            (e['tier'] == 'characteristic' || e['tier'] == 'mentalGeneral') &&
            e['text'] is String &&
            (e['text'] as String).trim().isNotEmpty)
          (e['text'] as String).trim(),
    ];
  }

  RecKey get _totalityKey =>
      (patientId: widget.patientId, kind: RecKind.homeoTotality);

  // Result ---------------------------------------------------------------

  Widget _resultTab(BuildContext context) {
    final c = context.cru;
    if (_selected.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s20),
        child: Text(
          'Pick rubrics first to see which remedies cover them.',
          style: CruType.text.tint(c.label2),
        ),
      );
    }
    final result = repertorize(_selected);
    final weights = {for (final s in _selected) s.id: s.weight};
    final notCovered = result.notCoveredByTop3;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s20,
        0,
        CruSpace.s20,
        CruSpace.s24,
      ),
      children: [
        Text('Top remedies', style: CruType.headline.tint(c.label)),
        const SizedBox(height: CruSpace.s4),
        Text(
          'Ranked by rubrics covered, then score (grade x weight). Tap a '
          'remedy to read its Materia medica page.',
          style: CruType.caption.tint(c.label2),
        ),
        const SizedBox(height: CruSpace.s12),
        CruCard(
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s12,
            vertical: CruSpace.s8,
          ),
          child: RepertoryGrid(
            result: result,
            weights: weights,
            chosen: _chosen,
            hasEntry: (a) => materiaMedicaFor(a) != null,
            onOpenRemedy: _openRemedy,
            onChoose: (a) => setState(() => _chosen = _chosen == a ? null : a),
          ),
        ),
        if (_chosen != null) ...[
          const SizedBox(height: CruSpace.s12),
          Row(
            children: [
              CruIcon(CruIcons.check, size: CruSpace.s16, color: c.greenText),
              const SizedBox(width: CruSpace.s6),
              Expanded(
                child: Text(
                  'Chosen remedy: $_chosen. Saved with this repertorization '
                  'only; the case sheet is not changed.',
                  style: CruType.text.tint(c.label),
                ),
              ),
            ],
          ),
        ],
        if (notCovered.isNotEmpty) ...[
          const SizedBox(height: CruSpace.cardGap),
          Text(
            'Not covered by the top 3',
            style: CruType.headline.tint(c.label),
          ),
          const SizedBox(height: CruSpace.s4),
          Text(
            'Rubrics none of the three leading remedies appear in.',
            style: CruType.caption.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s8),
          for (final r in notCovered)
            Padding(
              padding: const EdgeInsets.only(bottom: CruSpace.s4),
              child: Text(r.path, style: CruType.text.tint(c.label)),
            ),
        ],
        const SizedBox(height: CruSpace.cardGap),
        HomeopathyFormField(
          controller: _note,
          label: 'Note',
          hint: 'Why this remedy, what to compare',
          maxLines: 3,
        ),
      ],
    );
  }

  // Saved ----------------------------------------------------------------

  Widget _savedTab(BuildContext context) {
    final c = context.cru;
    final async = ref.watch(patientRecordsProvider(_key));
    final list = [
      for (final r in async.value ?? const <DentalRecord>[])
        Repertorization.fromRecord(r),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s20,
        0,
        CruSpace.s20,
        CruSpace.s24,
      ),
      children: [
        if (list.isEmpty)
          Text(
            async.isLoading
                ? 'Loading...'
                : 'No saved repertorizations for this patient yet.',
            style: CruType.text.tint(c.label2),
          ),
        for (final r in list)
          _SavedRow(item: r, onTap: () => _open(r), onDelete: () => _delete(r)),
      ],
    );
  }
}

// Rows and small pieces ----------------------------------------------------

class _RubricLabel extends StatelessWidget {
  const _RubricLabel(this.rubric);

  final Rubric rubric;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rubric.leaf, style: CruType.text.w600.tint(c.label)),
        if (rubric.parent.isNotEmpty)
          Text(rubric.parent, style: CruType.caption.tint(c.label3)),
      ],
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.rubric,
    required this.added,
    required this.onTap,
  });

  final Rubric rubric;
  final bool added;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      semanticLabel: '${added ? 'Remove' : 'Add'} ${rubric.path}',
      builder: (context, hovered) => Container(
        margin: const EdgeInsets.only(bottom: CruSpace.s6),
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s12,
          vertical: CruSpace.s10,
        ),
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(c.surface, c) : c.surface,
          shape: cruShape(
            CruRadius.control,
            side: BorderSide(color: c.hairline),
          ),
        ),
        child: Row(
          children: [
            Expanded(child: _RubricLabel(rubric)),
            const SizedBox(width: CruSpace.s8),
            added
                ? CruIcon(
                    CruIcons.check,
                    size: CruSpace.s18,
                    strokeWidth: 2.4,
                    color: c.greenText,
                  )
                : CruIcon(CruIcons.plus, size: CruSpace.s18, color: c.label3),
          ],
        ),
      ),
    );
  }
}

class _SelectedRow extends StatelessWidget {
  const _SelectedRow({
    required this.rubric,
    required this.weight,
    required this.onWeight,
    required this.onRemove,
  });

  final Rubric rubric;
  final int weight;
  final VoidCallback onWeight;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      margin: const EdgeInsets.only(bottom: CruSpace.s8),
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s10,
        CruSpace.s4,
        CruSpace.s10,
      ),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RubricLabel(rubric),
                const SizedBox(height: CruSpace.s8),
                CruPressable(
                  onTap: onWeight,
                  semanticLabel:
                      'Weight x$weight ${_weightNames[weight]}. Tap to change.',
                  builder: (context, hovered) => Container(
                    height: CruSize.pill,
                    padding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s10,
                    ),
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: hovered ? cruHoverShade(c.inset, c) : c.inset,
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'x$weight',
                          style: CruType.caption.w600.tabular.tint(
                            weight > 1 ? c.label : c.label2,
                          ),
                        ),
                        const SizedBox(width: CruSpace.s6),
                        Text(
                          _weightNames[weight] ?? '',
                          style: CruType.caption.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          CruIconButton(
            icon: FileIcons.trash,
            iconSize: CruSpace.s16,
            onPressed: onRemove,
            semanticLabel: 'Remove ${rubric.path}',
          ),
        ],
      ),
    );
  }
}

/// A violet capsule: AI-generated content starts here.
class _AiCapsule extends StatelessWidget {
  const _AiCapsule({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, hovered) => Container(
        height: CruSize.capsule,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
        decoration: ShapeDecoration(
          color: c.aiTint,
          shape: StadiumBorder(
            side: BorderSide(
              color: hovered ? c.ai : c.ai.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CruIcon(CruIcons.sparkle, size: 15, strokeWidth: 2, color: c.ai),
            const SizedBox(width: CruSpace.s6),
            Text(label, style: CruType.subhead.w600.tint(c.ai)),
          ],
        ),
      ),
    );
  }
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final Repertorization item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final top = item.result.remedies.take(3).map((r) => r.abbr).join(', ');
    final n = item.rubrics.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s8),
      child: CruPressable(
        onTap: onTap,
        semanticLabel:
            'Open repertorization of ${DateFormat('d MMM yyyy').format(item.date)}',
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s16,
            CruSpace.s12,
            CruSpace.s4,
            CruSpace.s12,
          ),
          decoration: ShapeDecoration(
            color: hovered ? cruHoverShade(c.surface, c) : c.surface,
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(color: c.hairline),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('d MMM yyyy').format(item.date),
                      style: CruType.callout.w600.tabular.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      '$n ${n == 1 ? 'rubric' : 'rubrics'}'
                      '${top.isEmpty ? '' : ' · top: $top'}',
                      style: CruType.caption.tabular.tint(c.label2),
                    ),
                    if (item.chosenRemedy != null) ...[
                      const SizedBox(height: CruSpace.s6),
                      CruPill(
                        text: 'Chosen: ${item.chosenRemedy}',
                        background: c.greenTint,
                        foreground: c.greenText,
                        icon: CruIcons.check,
                      ),
                    ],
                    if (item.note.trim().isNotEmpty) ...[
                      const SizedBox(height: CruSpace.s6),
                      Text(
                        item.note.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: CruType.caption.tint(c.label2),
                      ),
                    ],
                  ],
                ),
              ),
              CruIconButton(
                icon: FileIcons.trash,
                iconSize: CruSpace.s16,
                onPressed: onDelete,
                semanticLabel: 'Delete repertorization',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
