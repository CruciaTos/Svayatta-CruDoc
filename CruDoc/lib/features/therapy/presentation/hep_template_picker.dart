import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/domain/hep_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Picking one of the clinic's saved programmes to start a new one from.
///
/// The sibling of the rehab-protocol picker: that one offers the textbook
/// protocols CruDoc ships, this one offers what the clinic itself has built
/// and kept. Returns the chosen template, or null.
Future<HepTemplate?> pickHepTemplate(BuildContext context) =>
    showModalBottomSheet<HepTemplate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _TemplateSheet(),
    );

class _TemplateSheet extends ConsumerWidget {
  const _TemplateSheet();

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    HepTemplate t,
  ) async {
    final ok = await confirmDental(
      context,
      title: 'Delete this saved program?',
      body:
          '"${t.title}" will go from the list. Programs already given to '
          'patients are not touched.',
      action: 'Delete',
    );
    if (ok) await deleteDentalRecord(ref, t.record);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final templates = ref.watch(hepTemplatesProvider);
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
            Text('Saved programs', style: CruType.headline.tint(c.label)),
            const SizedBox(height: CruSpace.s4),
            Text(
              'Start from one of your own programs. The exercises are '
              'copied in; you can change them before saving.',
              style: CruType.caption.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s16),
            if (templates.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: CruSpace.s24),
                child: Text(
                  'No saved programs yet. Build one, then use '
                  '"Save as template".',
                  textAlign: TextAlign.center,
                  style: CruType.caption.tint(c.label3),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: templates.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: CruSpace.s8),
                  itemBuilder: (_, i) {
                    final t = templates[i];
                    return CruCard(
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(t),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.title.trim().isEmpty
                                        ? 'Untitled program'
                                        : t.title,
                                    style: CruType.body.w600.tint(c.label),
                                  ),
                                  const SizedBox(height: CruSpace.s2),
                                  Text(
                                    '${t.items.length} exercise'
                                    '${t.items.length == 1 ? '' : 's'} · saved '
                                    '${DentalFormat.date(t.date)}',
                                    style: CruType.caption.tabular.tint(
                                      c.label2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: c.label2,
                              ),
                              onPressed: () => _delete(context, ref, t),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
