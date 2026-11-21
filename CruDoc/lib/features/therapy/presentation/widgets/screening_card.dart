import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/data/physio_flags.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Intake screening: the red and yellow flags, and the banner a present red
/// flag raises above everything else on the patient's page.
///
/// Red is reserved in CruDoc for allergies and patient safety, which is
/// exactly what a red flag is, so the banner uses it. Yellow flags change how
/// care is given rather than whether it is safe, so they get amber and never
/// the alarm.

/// The banner for a patient whose screening found something, or null when
/// there is nothing to say. Shown above the patient's cards, not among them.
Widget? physioFlagBanner(
  BuildContext context,
  PhysioScreening screening, {
  required VoidCallback onOpen,
}) {
  if (!screening.hasRed && !screening.hasYellow) return null;
  final c = context.cru;
  final red = screening.presentOf(FlagKind.red);
  final yellow = screening.presentOf(FlagKind.yellow);
  final isRed = red.isNotEmpty;
  final found = isRed ? red : yellow;
  return CruCard(
    semanticLabel: isRed ? 'Red flags present' : 'Yellow flags present',
    padding: const EdgeInsets.symmetric(
      horizontal: CruSpace.s16,
      vertical: CruSpace.s12,
    ),
    child: Row(
      children: [
        CruIconTile(
          icon: CruIcons.warning,
          tone: isRed ? CruTileTone.red : CruTileTone.amber,
        ),
        const SizedBox(width: CruSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isRed
                    ? 'Red flag: refer before treating'
                    : 'Yellow flags noted',
                style: CruType.callout.w600.tint(
                  isRed ? c.redText : c.amberText,
                ),
              ),
              Text(
                [for (final f in found) f.label].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: CruType.subhead.tint(c.label2),
              ),
              // Both kinds found: the red ones are named above, so say the
              // rest is there rather than hiding it.
              if (isRed && yellow.isNotEmpty)
                Text(
                  'Also ${yellow.length} yellow flag'
                  '${yellow.length == 1 ? '' : 's'}',
                  style: CruType.caption.tabular.tint(c.label3),
                ),
            ],
          ),
        ),
        CruCapsuleButton(label: 'Review', onPressed: onOpen),
      ],
    ),
  );
}

/// The banner in place, reading the patient's screening itself.
///
/// Takes no room at all when there is nothing to warn about, so it can sit
/// unconditionally at the top of the physiotherapy page.
class ScreeningBanner extends ConsumerWidget {
  const ScreeningBanner({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: patient.id,
        kind: RecKind.physioScreening,
      )),
    );
    final banner = physioFlagBanner(
      context,
      screeningOf(recs.value ?? const <DentalRecord>[]),
      onOpen: () => showScreeningSheet(context, ref, patient),
    );
    if (banner == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.cardGap),
      child: banner,
    );
  }
}

/// Patient Details card: the state of the screening, and the way into it.
class ScreeningCard extends ConsumerWidget {
  const ScreeningCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: patient.id,
        kind: RecKind.physioScreening,
      )),
    );
    final s = screeningOf(recs.value ?? const <DentalRecord>[]);
    final red = s.presentOf(FlagKind.red).length;
    final yellow = s.presentOf(FlagKind.yellow).length;

    return CruCard(
      semanticLabel: 'Screening',
      child: Row(
        children: [
          CruIconTile(
            icon: CruIcons.warning,
            tone: red > 0
                ? CruTileTone.red
                : (yellow > 0 ? CruTileTone.amber : CruTileTone.neutral),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Screening',
                  style: CruType.headline.w600.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  !s.started
                      ? 'Red and yellow flags not screened yet'
                      : '$red red · $yellow yellow · '
                            '${s.unanswered} not asked',
                  style: CruType.caption.tabular.tint(c.label2),
                ),
              ],
            ),
          ),
          CruCapsuleButton(
            label: s.started ? 'Review' : 'Screen',
            icon: s.started ? null : CruIcons.plus,
            onPressed: () => showScreeningSheet(context, ref, patient),
          ),
        ],
      ),
    );
  }
}

/// The checklist. Each flag is asked and answered, and "not asked" stays
/// visible until it is: a half-finished screening must look half-finished.
Future<void> showScreeningSheet(
  BuildContext context,
  WidgetRef ref,
  Patient patient,
) async {
  final recs = await ref.read(
    patientRecordsProvider((
      patientId: patient.id,
      kind: RecKind.physioScreening,
    )).future,
  );
  if (!context.mounted) return;
  final existing = screeningOf(recs);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ScreeningSheet(patient: patient, existing: existing),
  );
}

class _ScreeningSheet extends ConsumerStatefulWidget {
  const _ScreeningSheet({required this.patient, required this.existing});

  final Patient patient;
  final PhysioScreening existing;

  @override
  ConsumerState<_ScreeningSheet> createState() => _ScreeningSheetState();
}

class _ScreeningSheetState extends ConsumerState<_ScreeningSheet> {
  late final Map<String, FlagAnswer> _answers = {...widget.existing.answers};
  late final TextEditingController _note = TextEditingController(
    text: widget.existing.note,
  );
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = PhysioScreening.toData(
      answers: _answers,
      note: _note.text.trim(),
    );
    final old = widget.existing.record;
    await saveDentalRecord(
      ref,
      old != null
          ? old.copyWith(data: data)
          : DentalRecord.create(
              widget.patient.id,
              RecKind.physioScreening,
              data,
            ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    FlagAnswer answer(String id) => _answers[id] ?? FlagAnswer.notAsked;

    Widget row(PhysioFlag f) {
      final a = answer(f.id);
      return Padding(
        padding: const EdgeInsets.only(bottom: CruSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.label, style: CruType.callout.tint(c.label)),
            if (f.why.isNotEmpty)
              Text(f.why, style: CruType.caption.tint(c.label3)),
            const SizedBox(height: CruSpace.s8),
            Row(
              children: [
                for (final option in [FlagAnswer.absent, FlagAnswer.present])
                  Padding(
                    padding: const EdgeInsets.only(right: CruSpace.s8),
                    child: DentalChoiceChip(
                      label: option == FlagAnswer.present ? 'Yes' : 'No',
                      selected: a == option,
                      // Tapping the chosen answer again clears it back to
                      // not asked, so a mis-tap can be undone honestly.
                      onTap: () => setState(() {
                        if (a == option) {
                          _answers.remove(f.id);
                        } else {
                          _answers[f.id] = option;
                        }
                      }),
                    ),
                  ),
                if (a == FlagAnswer.notAsked)
                  Text('Not asked', style: CruType.caption.tint(c.label3)),
              ],
            ),
          ],
        ),
      );
    }

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
            Text('Screening', style: CruType.headline.tint(c.label)),
            const SizedBox(height: CruSpace.s4),
            Text(
              'Ask each one. A flag left unanswered is recorded as not '
              'asked, not as absent.',
              style: CruType.caption.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final kind in FlagKind.values) ...[
                      Text(
                        kind.label.toUpperCase(),
                        style: CruType.groupLabel.tint(
                          kind == FlagKind.red ? c.redText : c.amberText,
                        ),
                      ),
                      Text(
                        kind.meaning,
                        style: CruType.caption.tint(c.label3),
                      ),
                      const SizedBox(height: CruSpace.s12),
                      for (final f in physioFlagsOf(kind)) row(f),
                      const SizedBox(height: CruSpace.s8),
                    ],
                    CruTextField(
                      label: 'Note',
                      controller: _note,
                      hint: 'Anything else worth recording',
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: CruSpace.s16),
            CruButton(
              label: _saving ? 'Saving…' : 'Save screening',
              expand: true,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
