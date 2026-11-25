import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/data/outcome_scale.dart';
import 'package:doctor_management_app/features/therapy/data/outcome_scale_registry.dart';
import 'package:doctor_management_app/features/therapy/domain/outcome_score_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Patient Details card: the outcome measures taken, and what they show.
///
/// Only scales the patient has actually been given appear. A clinic that
/// treats necks has no use for a list of every instrument in the app, and a
/// row reading "not measured" for ten scales says nothing.
///
/// An instrument whose asset is missing is named rather than hidden: a
/// physio who believes the clinic has the NDI needs to be told it has not,
/// and quietly leaving it out of the picker is how that goes unnoticed.
class OutcomeScalesCard extends ConsumerWidget {
  const OutcomeScalesCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final load = ref.watch(outcomeScalesProvider);
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: patient.id,
        kind: RecKind.physioScaleScore,
      )),
    );

    final scales = load.value?.scales ?? const <ScaleDef>[];
    final problems = load.value?.problems ?? const <String>[];
    final records = recs.value ?? const <DentalRecord>[];

    // Only the scales this patient has been given, most recently taken
    // first, so the measure being tracked now leads.
    final used = <ScaleDef, List<ScaleResult>>{};
    for (final s in scales) {
      final trend = scaleTrend(s, records);
      if (trend.isNotEmpty) used[s] = trend;
    }
    final ordered = used.keys.toList()
      ..sort((a, b) => used[b]!.last.takenAt.compareTo(used[a]!.last.takenAt));

    return CruCard(
      semanticLabel: 'Outcome measures',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CruIconTile(icon: CruIcons.arrowDown, tone: CruTileTone.neutral),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Outcome measures',
                      style: CruType.headline.w600.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      ordered.isEmpty
                          ? 'Scored questionnaires and timed tests'
                          : '${ordered.length} measure'
                                '${ordered.length == 1 ? '' : 's'} tracked',
                      style: CruType.caption.tabular.tint(c.label2),
                    ),
                  ],
                ),
              ),
              CruCapsuleButton(
                label: ordered.isEmpty ? 'Measure' : '+ Measure',
                icon: ordered.isEmpty ? CruIcons.plus : null,
                onPressed: scales.isEmpty
                    ? null
                    : () => pickOutcomeScale(context, ref, patient),
              ),
            ],
          ),
          for (final s in ordered)
            _ScaleRow(
              scale: s,
              trend: used[s]!,
              onTap: () => showOutcomeScaleSheet(context, ref, patient, s),
            ),
          // Instruments the clinic has not supplied. Stated plainly, once,
          // without turning the card amber: nothing is wrong with this
          // patient's record, something is missing from the app's setup.
          if (problems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CruSpace.s12),
              child: Text(
                '${problems.length} instrument'
                '${problems.length == 1 ? '' : 's'} not installed',
                style: CruType.caption.tint(c.label3),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScaleRow extends StatelessWidget {
  const _ScaleRow({
    required this.scale,
    required this.trend,
    required this.onTap,
  });

  final ScaleDef scale;
  final List<ScaleResult> trend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final latest = latestResult(trend);
    final change = scaleChange(trend);

    // Green only for a change big enough that the instrument itself says it
    // is real. Everything else stays neutral rather than dressing up noise.
    final Color tint;
    if (change == null || !change.mdcKnown || !change.beyondMdc) {
      tint = c.label2;
    } else {
      tint = change.improved ? c.greenText : c.amberText;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(CruRadius.control),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: CruSpace.s12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(scale.short, style: CruType.body.w600.tint(c.label)),
                  Text(
                    latest?.line ?? trend.last.line,
                    style: CruType.caption.tabular.tint(c.label2),
                  ),
                  if (change != null && change.size != 0)
                    Text(
                      change.reportLine,
                      style: CruType.caption.tabular.tint(tint),
                    ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            Text(
              DentalFormat.date(trend.last.takenAt),
              style: CruType.caption.tabular.tint(c.label3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Choose which measure to take.
Future<void> pickOutcomeScale(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
) async {
  final load = await ref.read(outcomeScalesProvider.future);
  if (!context.mounted) return;
  final chosen = await showModalBottomSheet<ScaleDef>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ScalePicker(load: load),
  );
  if (chosen == null || !context.mounted) return;
  await showOutcomeScaleSheet(context, ref, patient, chosen);
}

class _ScalePicker extends StatelessWidget {
  const _ScalePicker({required this.load});

  final ScaleLoad load;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          0,
          CruSpace.s16,
          CruSpace.s16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Take a measure', style: CruType.headline.tint(c.label)),
            const SizedBox(height: CruSpace.s16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in load.scales)
                      InkWell(
                        borderRadius: BorderRadius.circular(CruRadius.control),
                        onTap: () => Navigator.of(context).pop(s),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: CruSpace.s12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${s.short} — ${s.name}',
                                style: CruType.body.w600.tint(c.label),
                              ),
                              Text(
                                s.isQuestionnaire
                                    ? '${s.region} · '
                                          '${s.items.length} sections'
                                    : '${s.region} · measured in ${s.unit}',
                                style: CruType.caption.tint(c.label2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Why an instrument the physio expects is not listed.
                    if (load.problems.isNotEmpty) ...[
                      const SizedBox(height: CruSpace.s16),
                      Text(
                        'NOT INSTALLED',
                        style: CruType.groupLabel.tint(c.label2),
                      ),
                      const SizedBox(height: CruSpace.s4),
                      Text(
                        'These instruments are licensed, and the clinic '
                        'supplies its own copy. See '
                        'assets/outcome_scales/README.md.',
                        style: CruType.caption.tint(c.label3),
                      ),
                      for (final p in load.problems)
                        Padding(
                          padding: const EdgeInsets.only(top: CruSpace.s4),
                          child: Text(p, style: CruType.caption.tint(c.label3)),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Administer one measure.
Future<void> showOutcomeScaleSheet(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
  ScaleDef scale,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ScaleSheet(patient: patient, scale: scale),
);

class _ScaleSheet extends ConsumerStatefulWidget {
  const _ScaleSheet({required this.patient, required this.scale});

  final Patient patient;
  final ScaleDef scale;

  @override
  ConsumerState<_ScaleSheet> createState() => _ScaleSheetState();
}

class _ScaleSheetState extends ConsumerState<_ScaleSheet> {
  final Map<String, int> _answers = {};
  final _value = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  ScaleDef get scale => widget.scale;

  @override
  void dispose() {
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  /// What this would score if saved now, so the physio can see a section
  /// still missing before it becomes an unreportable record.
  ScaleResult get _preview => ScaleResult.of(
    scale,
    OutcomeScore(
      scaleId: scale.id,
      answers: _answers,
      value: double.tryParse(_value.text.trim()),
      note: '',
      record: DentalRecord.create(
        widget.patient.id,
        RecKind.physioScaleScore,
        const {},
      ),
    ),
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    await saveDentalRecord(
      ref,
      DentalRecord.create(
        widget.patient.id,
        RecKind.physioScaleScore,
        OutcomeScore.toData(
          scaleId: scale.id,
          answers: _answers,
          value: double.tryParse(_value.text.trim()),
          note: _note.text.trim(),
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final preview = _preview;
    final canSave = scale.isQuestionnaire
        ? _answers.isNotEmpty
        : double.tryParse(_value.text.trim()) != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          0,
          CruSpace.s16,
          CruSpace.s16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(scale.name, style: CruType.headline.tint(c.label)),
            const SizedBox(height: CruSpace.s4),
            Text(scale.source, style: CruType.caption.tint(c.label3)),
            if (scale.instruction.isNotEmpty) ...[
              const SizedBox(height: CruSpace.s8),
              Text(scale.instruction, style: CruType.caption.tint(c.label2)),
            ],
            const SizedBox(height: CruSpace.s16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (scale.isQuestionnaire)
                      for (final item in scale.items)
                        _ItemBlock(
                          item: item,
                          chosen: _answers[item.id],
                          onChoose: (i) => setState(() {
                            // Tapping the chosen answer again clears it, so
                            // a mis-tap becomes unanswered rather than a
                            // different answer.
                            if (_answers[item.id] == i) {
                              _answers.remove(item.id);
                            } else {
                              _answers[item.id] = i;
                            }
                          }),
                        )
                    else
                      CruTextField(
                        label: '${scale.name} (${scale.unit})',
                        controller: _value,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        tabular: true,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    if (scale.usageNote.isNotEmpty) ...[
                      const SizedBox(height: CruSpace.s12),
                      Text(
                        scale.usageNote,
                        style: CruType.caption.tint(c.label3),
                      ),
                    ],
                    const SizedBox(height: CruSpace.s12),
                    CruTextField(
                      label: 'Note',
                      controller: _note,
                      hint: scale.isQuestionnaire
                          ? 'Anything that affected the answers'
                          : 'Walking aid, rests, why it stopped early',
                      optional: true,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: CruSpace.s12),
            // What it will report as, said before saving rather than
            // discovered on the card afterwards.
            Container(
              padding: const EdgeInsets.all(CruSpace.s12),
              decoration: BoxDecoration(
                color: c.inset,
                borderRadius: BorderRadius.circular(CruRadius.control),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      preview.isReportable
                          ? preview.line
                          : (scale.isQuestionnaire
                                ? '${preview.answered} of '
                                      '${scale.items.length} answered — '
                                      '${preview.stillNeeded} more before '
                                      'this reports a score'
                                : 'No figure entered yet'),
                      style: CruType.caption.tabular.tint(
                        preview.isReportable ? c.label : c.label2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CruSpace.s12),
            CruButton(
              label: _saving ? 'Saving…' : 'Save ${scale.short}',
              expand: true,
              onPressed: _saving || !canSave ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// One questionnaire section: its heading, and its answers in the
/// instrument's own order.
///
/// Options are never re-ordered or re-worded for display, because the index
/// is the score and the wording is the instrument.
class _ItemBlock extends StatelessWidget {
  const _ItemBlock({
    required this.item,
    required this.chosen,
    required this.onChoose,
  });

  final ScaleItem item;
  final int? chosen;
  final ValueChanged<int> onChoose;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: CruType.callout.w600.tint(c.label),
                ),
              ),
              if (chosen == null)
                Text('Not answered', style: CruType.caption.tint(c.label3)),
            ],
          ),
          const SizedBox(height: CruSpace.s8),
          for (var i = 0; i < item.options.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(CruRadius.control),
              onTap: () => onChoose(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: CruSpace.s4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      chosen == i
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 18,
                      color: chosen == i ? c.accent : c.label3,
                    ),
                    const SizedBox(width: CruSpace.s8),
                    Expanded(
                      child: Text(
                        item.options[i],
                        style: CruType.caption.tint(
                          chosen == i ? c.label : c.label2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
