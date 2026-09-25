import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/month/month_metrics.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import 'agenda_row.dart';

/// Appointments, Agenda: a card listing visits from the anchor date
/// forward (the next 30 days) under date headers. Clicking a row opens
/// the Day view with that visit selected.
class AppointmentsAgendaView extends ConsumerWidget {
  const AppointmentsAgendaView({super.key});

  /// How far ahead the list reaches.
  static const int days = 30;

  static const EdgeInsets _cardPadding = EdgeInsets.fromLTRB(
    CruSpace.s12,
    CruSpace.s8,
    CruSpace.s12,
    CruSpace.s12,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final anchor = ref.watch(apptsControllerProvider.select((s) => s.anchor));
    final today = ApptsBuilder.dateOnly(ref.watch(apptsNowProvider));
    final from = ApptsBuilder.dateOnly(anchor);
    final to = DateTime(from.year, from.month, from.day + days);
    final async = ref.watch(apptItemsProvider);
    final all = async.value;

    if (all == null) {
      return SizedBox(
        width: double.infinity,
        child: async.hasError
            ? CruCard(
                child: Text(
                  "Couldn't load appointments.",
                  style: CruType.text.tint(c.label2),
                ),
              )
            : const SkeletonCard(rows: 6, rowHeight: kAgendaRowHeight),
      );
    }

    final items = ApptsBuilder.inRange(all, from, to);

    if (items.isEmpty) {
      return SizedBox(
        width: double.infinity,
        child: Align(
          alignment: Alignment.topCenter,
          child: CruCard(
            padding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s24,
              vertical: CruSpace.s32,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  Text(
                    'Nothing booked',
                    style: CruType.headline.tint(c.label),
                  ),
                  const SizedBox(height: CruSpace.s4),
                  Text(
                    'No appointments in the $days days from '
                    '${DateFormat('d MMMM').format(from)}.',
                    textAlign: TextAlign.center,
                    style: CruType.text.tint(c.label2),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Flatten into headers and rows so the list can build lazily.
    final entries = <_Entry>[];
    DateTime? current;
    final countByDay = <DateTime, int>{};
    for (final i in items) {
      final d = ApptsBuilder.dateOnly(i.start);
      countByDay[d] = (countByDay[d] ?? 0) + 1;
    }
    for (final i in items) {
      final d = ApptsBuilder.dateOnly(i.start);
      if (d != current) {
        entries.add(_Entry.header(d));
        current = d;
      } else {
        entries.add(const _Entry.separator());
      }
      entries.add(_Entry.row(d, i));
    }

    final controller = ref.read(apptsControllerProvider.notifier);

    return SizedBox(
      width: double.infinity,
      child: CruCard(
        padding: _cardPadding,
        semanticLabel: 'Agenda',
        child: ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final e = entries[index];
            if (e.item == null && e.date == null) {
              return const CruSeparator(
                indent: CruSpace.s12 + MonthMetrics.timeColumn + CruSpace.s12,
                endIndent: CruSpace.s12,
              );
            }
            if (e.item == null) {
              return AgendaDateHeader(
                date: e.date!,
                today: today,
                count: countByDay[e.date!] ?? 0,
              );
            }
            return AgendaRow(
              item: e.item!,
              onTap: () => controller.openDay(e.date!, visitId: e.item!.id),
            );
          },
        ),
      ),
    );
  }
}

/// A date header ([date] only), a row ([date] + [item]) or a separator
/// (neither).
class _Entry {
  const _Entry.header(DateTime this.date) : item = null;
  const _Entry.row(DateTime this.date, ApptItem this.item);
  const _Entry.separator()
      : date = null,
        item = null;

  final DateTime? date;
  final ApptItem? item;
}
