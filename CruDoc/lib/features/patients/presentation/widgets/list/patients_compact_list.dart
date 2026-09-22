import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/list/patients_table.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Split mode: compact two-line rows beside the preview pane.
class PatientsCompactList extends StatelessWidget {
  const PatientsCompactList({
    super.key,
    required this.view,
    required this.filter,
    required this.now,
    required this.onTap,
    this.selectedRowKey,
  });

  final PatientsListView view;

  /// Decides the right-hand column (last visit / due / overdue).
  final PatientFilter filter;
  final DateTime now;
  final PatientRowTap onTap;
  final GlobalKey? selectedRowKey;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final selectedId = view.selected?.id;
    final rows = view.visible;
    final rightTitle = switch (filter) {
      PatientFilter.balanceDue => 'Due',
      PatientFilter.followUpOverdue => 'Overdue',
      _ => 'Last visit',
    };
    final header = CruType.caption.w600.tint(c.label2);

    final children = <Widget>[
      Container(
        height: CruSize.tableHeader,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.separator)),
        ),
        child: Row(
          children: [
            Expanded(child: Text('Patient', style: header)),
            Text(rightTitle, style: header),
          ],
        ),
      ),
      const SizedBox(height: CruSpace.s6),
    ];
    for (var i = 0; i < rows.length; i++) {
      final s = rows[i];
      final selected = s.id == selectedId;
      if (i > 0) {
        final hidden = selected || rows[i - 1].id == selectedId;
        children.add(
          Opacity(
            opacity: hidden ? 0 : 1,
            child: const CruSeparator(
              indent: CruSize.patientTextInset,
              endIndent: CruSpace.s16,
            ),
          ),
        );
      }
      final row = _CompactRow(
        summary: s,
        filter: filter,
        now: now,
        selected: selected,
        onTap: () => onTap(s),
      );
      children.add(
        selected && selectedRowKey != null
            ? KeyedSubtree(key: selectedRowKey, child: row)
            : row,
      );
    }
    children.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          CruSpace.s12,
          CruSpace.s16,
          CruSpace.s4,
        ),
        child: Text(
          'Showing ${rows.length} of ${view.rows.length}',
          style: CruType.subhead.tabular.tint(c.label3),
        ),
      ),
    );

    return CruCard(
      semanticLabel: 'Patient list',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s6,
        CruSpace.s12,
        CruSpace.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.summary,
    required this.filter,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  final PatientSummary summary;
  final PatientFilter filter;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final s = summary;
    final subtitle = PatientFormat.treatmentLine(s) ?? s.condition;

    String? top;
    String? sub;
    var attention = false;
    switch (filter) {
      case PatientFilter.balanceDue:
        // "since <date>" under the amount is a GAP (no due date).
        top = s.hasBalance ? PatientFormat.rupees(s.balance) : null;
        attention = true;
      case PatientFilter.followUpOverdue:
        final since = s.overdueSince;
        if (since != null) {
          top = PatientFormat.days(PatientsBuilder.daysSince(since, now));
          sub = 'since ${PatientFormat.weekdayDate(since)}';
          attention = true;
        }
      default:
        final last = s.lastVisit;
        if (last != null) {
          top = PatientFormat.day(last.scheduledStart, now);
          sub = DashFormat.time(last.scheduledStart);
        }
    }

    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        scaleOnPress: false,
        semanticLabel: 'Preview ${s.name}',
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.compactRow,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
          decoration: ShapeDecoration(
            color: selected
                ? c.accentTint
                : (hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0)),
            shape: cruShape(CruRadius.control),
          ),
          child: Row(
            children: [
              CruMonogram(
                name: s.name,
                size: CruSize.monogramList,
                background: selected ? c.surface : c.inset,
                foreground: selected ? c.accentText : null,
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: CruType.row.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: CruType.subhead.tint(c.label2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    top ?? '—',
                    maxLines: 1,
                    style: top == null
                        ? CruType.row.w500.tint(c.label3)
                        : attention
                            ? CruType.row.tabular.tint(c.amberText)
                            : CruType.row.w500.tabular.tint(c.label),
                  ),
                  if (sub != null)
                    Text(
                      sub,
                      maxLines: 1,
                      style: CruType.caption.tabular.tint(c.label2),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
