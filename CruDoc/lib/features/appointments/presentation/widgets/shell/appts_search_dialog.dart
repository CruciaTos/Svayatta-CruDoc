import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Finds visits by patient name; picking one opens its day.
Future<void> showApptsSearchDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const ApptsSearchDialog(),
    );

class ApptsSearchDialog extends ConsumerStatefulWidget {
  const ApptsSearchDialog({super.key});

  @override
  ConsumerState<ApptsSearchDialog> createState() => _ApptsSearchDialogState();
}

class _ApptsSearchDialogState extends ConsumerState<ApptsSearchDialog> {
  final _query = TextEditingController();

  /// Rows shown at most, so the dialog keeps a fixed height.
  static const int _maxRows = 6;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<ApptItem> _results(List<ApptItem> all, DateTime now) {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final today = ApptsBuilder.dateOnly(now);
    final matches = all.where((i) => i.name.toLowerCase().contains(q)).toList();
    // Upcoming first (soonest first), then past (most recent first).
    final upcoming = matches.where((i) => !i.start.isBefore(today)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final past = matches.where((i) => i.start.isBefore(today)).toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    return [...upcoming, ...past].take(_maxRows).toList();
  }

  void _open(ApptItem item) {
    Navigator.of(context).pop();
    ref
        .read(apptsControllerProvider.notifier)
        .openDay(item.start, visitId: item.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final all = ref.watch(apptItemsProvider).value ?? const <ApptItem>[];
    final now = ref.watch(apptsNowProvider);
    final results = _results(all, now);
    final hasQuery = _query.text.trim().isNotEmpty;

    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: c.surface.withValues(alpha: 0),
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(
        top: CruSpace.s32 * 3,
        left: CruSpace.s24,
        right: CruSpace.s24,
      ),
      shape: cruShape(CruRadius.card, side: BorderSide(color: c.hairline)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: CruSize.remindersDialog),
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: CruSize.searchBar,
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
                decoration: ShapeDecoration(
                  color: c.inset,
                  shape: cruShape(CruRadius.control),
                ),
                child: Row(
                  children: [
                    CruIcon(CruIcons.search, size: 17, strokeWidth: 2, color: c.label2),
                    const SizedBox(width: CruSpace.s10),
                    Expanded(
                      child: TextField(
                        controller: _query,
                        autofocus: true,
                        cursorColor: c.accent,
                        style: CruType.input.tint(c.label),
                        decoration: InputDecoration.collapsed(
                          hintText: 'Find a visit by patient name',
                          hintStyle: CruType.input.tint(c.label3),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (results.isNotEmpty) _open(results.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (hasQuery) ...[
                const SizedBox(height: CruSpace.s8),
                if (results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s8,
                      vertical: CruSpace.s12,
                    ),
                    child: Text(
                      'No visits for “${_query.text.trim()}”.',
                      style: CruType.text.tint(c.label2),
                    ),
                  )
                else
                  for (final item in results) _ResultRow(item: item, onTap: () => _open(item)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.item, required this.onTap});

  final ApptItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      semanticLabel: '${item.name}, ${ApptFormat.dateLine(item.start)}, '
          '${ApptFormat.time(item.start)}',
      scaleOnPress: false,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        height: CruSize.scheduleRow,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
        decoration: ShapeDecoration(
          color: hovered ? c.inset : c.inset.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            CruMonogram(name: item.name, size: CruSize.monogramList),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: CruType.callout.w600.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      '${DashFormat.weekday(item.start)}, '
                          '${DashFormat.shortDate(item.start)}',
                      ApptFormat.time(item.start),
                      if (item.reason != null) item.reason!,
                    ].join(' · '),
                    style: CruType.caption.tabular.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
          ],
        ),
      ),
    );
  }
}
