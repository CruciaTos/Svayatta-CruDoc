import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/therapy/data/exercise_library.dart';
import 'package:doctor_management_app/features/therapy/data/rehab_protocols.dart';
import 'package:doctor_management_app/features/therapy/domain/hep_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Turns a protocol into program items using [catalog] (bundled + custom
/// exercises). Exercises missing from the catalog are skipped.
List<HepItem> protocolItems(RehabProtocol p, List<ExerciseDef> catalog) {
  final byId = {for (final e in catalog) e.id: e};
  return [
    for (final pi in p.items)
      if (byId[pi.exerciseId] case final e?)
        HepItem.fromExercise(e).copyWith(
          sets: pi.sets,
          reps: pi.reps,
          holdSeconds: pi.holdSeconds,
          perDay: pi.perDay,
        ),
  ];
}

/// Bottom sheet: pick a protocol, see its exercises, confirm with "Add all".
/// Returns the chosen protocol, or null.
Future<RehabProtocol?> pickRehabProtocol(BuildContext context) =>
    showModalBottomSheet<RehabProtocol>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ProtocolSheet(),
    );

class _ProtocolSheet extends StatefulWidget {
  const _ProtocolSheet();

  @override
  State<_ProtocolSheet> createState() => _ProtocolSheetState();
}

class _ProtocolSheetState extends State<_ProtocolSheet> {
  RehabProtocol? _open;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final open = _open;
    final names = {for (final e in kExerciseLibrary) e.id: e.name};
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s16,
                0,
                CruSpace.s16,
                CruSpace.s8,
              ),
              child: Row(
                children: [
                  if (open != null)
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => setState(() => _open = null),
                    ),
                  Expanded(
                    child: Text(
                      open?.name ?? 'Start from a protocol',
                      style: CruType.headline.w600.tint(c.label),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
              child: Text(
                open?.description ?? kProtocolDisclaimer,
                style: CruType.caption.tint(c.label2),
              ),
            ),
            const SizedBox(height: CruSpace.s8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
                children: [
                  if (open == null)
                    for (final p in kRehabProtocols)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.name),
                        subtitle: Text(
                          p.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => setState(() => _open = p),
                      )
                  else
                    for (final i in open.items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(names[i.exerciseId] ?? i.exerciseId),
                      ),
                ],
              ),
            ),
            if (open != null)
              Padding(
                padding: const EdgeInsets.all(CruSpace.s16),
                child: CruButton(
                  label: 'Add all',
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(open),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
