import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/charting_page.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What a row does when tapped (the screen decides: select, or open).
typedef PatientRowTap = void Function(PatientSummary summary);

/// Table mode: the full-width list card with grouped 64 px rows.
class PatientsTable extends ConsumerWidget {
  const PatientsTable({
    super.key,
    required this.view,
    required this.now,
    required this.onTap,
    this.selectedId,
    this.selectedRowKey,
    this.showFooter = true,
    this.hint,
    this.trailing,
    this.empty,
  });

  final PatientsListView view;
  final DateTime now;
  final PatientRowTap onTap;

  /// Highlighted while the preview sheet is open over the table.
  final String? selectedId;

  /// Put on the selected row so keyboard moves can scroll it into view.
  final GlobalKey? selectedRowKey;

  final bool showFooter;

  /// Right side of the footer ("Click a patient to preview").
  final String? hint;

  /// Below the rows (the first-week panel).
  final Widget? trailing;

  /// Shown instead of rows when nothing matches.
  final Widget? empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    // Dentists with Charting in the sidebar get a chart button per row.
    final goToTab = ref.watch(shellNavigatorProvider);
    final chart =
        goToTab != null &&
        sidebarTabs(
          dental: ref.watch(dentalFeaturesProvider),
          access: ref.watch(clinicAccessProvider).value,
        ).any((t) => t.tab == DesktopTab.charting);
    void openChart(PatientSummary s) {
      ref.read(chartingPatientIdProvider.notifier).state = s.id;
      goToTab?.call(DesktopTab.charting);
    }

    return CruCard(
      semanticLabel: 'Patient list',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s6,
        CruSpace.s12,
        CruSpace.s12,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < CruSize.tableNarrow;
          final children = <Widget>[
            _TableHeader(narrow: narrow, chart: chart),
            if (view.visible.isEmpty && empty != null) empty!,
          ];
          for (final g in view.groups) {
            if (g.title != null) {
              children.add(
                _GroupHeader(title: g.title!, count: _groupTotal(g, view.rows)),
              );
            } else {
              children.add(const SizedBox(height: CruSpace.s8));
            }
            for (var i = 0; i < g.rows.length; i++) {
              final s = g.rows[i];
              final selected = s.id == selectedId;
              if (i > 0) {
                final prevSelected = g.rows[i - 1].id == selectedId;
                children.add(
                  Opacity(
                    opacity: selected || prevSelected ? 0 : 1,
                    child: const CruSeparator(
                      indent: CruSize.patientTextInset,
                      endIndent: CruSpace.s16,
                    ),
                  ),
                );
              }
              final row = PatientTableRow(
                summary: s,
                now: now,
                narrow: narrow,
                selected: selected,
                onTap: () => onTap(s),
                onChart: chart ? () => openChart(s) : null,
              );
              children.add(
                selected && selectedRowKey != null
                    ? KeyedSubtree(key: selectedRowKey, child: row)
                    : row,
              );
            }
          }
          if (trailing != null) {
            children
              ..add(const SizedBox(height: CruSpace.s12))
              ..add(trailing!);
          }
          if (showFooter && view.visible.isNotEmpty) {
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CruSpace.s16,
                  CruSpace.s14,
                  CruSpace.s16,
                  CruSpace.s4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Showing ${view.visible.length} of ${view.rows.length}',
                        style: CruType.subhead.tabular.tint(c.label3),
                      ),
                    ),
                    if (hint != null)
                      Text(hint!, style: CruType.subhead.tint(c.label3)),
                  ],
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
        },
      ),
    );
  }

  /// A group's count covers every page, not just the rows revealed.
  static int _groupTotal(PatientGroup g, List<PatientSummary> all) =>
      switch (g.title) {
        'Seen today' => all.where((s) => s.seenToday).length,
        'Past 7 days' =>
          all.where((s) => s.seenWithin7Days && !s.seenToday).length,
        'Earlier' => all.where((s) => !s.seenWithin7Days).length,
        _ => g.rows.length,
      };
}

/// Lays out the seven table columns (HTML grid: 2.1fr 64 2.3fr 124 148
/// 92 16, gap 20). [narrow] drops Age and Next visit.
class _Columns extends StatelessWidget {
  const _Columns({
    required this.narrow,
    required this.patient,
    required this.age,
    required this.condition,
    required this.last,
    required this.next,
    required this.balance,
    required this.chevron,
    this.chart,
  });

  final bool narrow;

  /// The Charting button column, for dentists; null leaves it out.
  final Widget? chart;
  final Widget patient;
  final Widget age;
  final Widget condition;
  final Widget last;
  final Widget next;
  final Widget balance;
  final Widget chevron;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: CruSpace.s20);
    return Row(
      children: [
        Expanded(flex: 21, child: patient),
        if (!narrow) ...[
          gap,
          SizedBox(width: CruSize.tableAgeColumn, child: age),
        ],
        gap,
        Expanded(flex: 23, child: condition),
        gap,
        SizedBox(width: CruSize.tableLastVisitColumn, child: last),
        if (!narrow) ...[
          gap,
          SizedBox(width: CruSize.tableNextVisitColumn, child: next),
        ],
        gap,
        SizedBox(width: CruSize.tableBalanceColumn, child: balance),
        if (chart != null) ...[
          const SizedBox(width: CruSpace.s12),
          SizedBox(width: _chartColumn, child: chart),
        ],
        gap,
        SizedBox(width: CruSize.tableChevronColumn, child: chevron),
      ],
    );
  }
}

/// Width of the Charting button column: fits the button below.
const double _chartColumn = 120;

/// "Charting" with the tooth, the same button as the header's Recalls:
/// opens Charting for the row's patient.
class _ChartButton extends StatelessWidget {
  const _ChartButton({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: CruButton(
      label: 'Charting',
      kind: CruButtonKind.secondary,
      icon: DentalIcons.tooth,
      semanticLabel: 'Open charting for $name',
      onPressed: onTap,
    ),
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.narrow, required this.chart});

  final bool narrow;
  final bool chart;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final style = CruType.caption.w600.tint(c.accentText);
    Text t(String s, [TextAlign align = TextAlign.start]) => Text(
      s,
      style: style,
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Container(
      height: CruSize.tableHeader,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.separator)),
      ),
      child: _Columns(
        narrow: narrow,
        patient: t('Patient'),
        age: t('Age'),
        condition: t('Condition and treatment'),
        last: t('Last visit'),
        next: t('Next visit'),
        balance: t('Balance', TextAlign.end),
        chevron: const SizedBox.shrink(),
        chart: chart ? const SizedBox.shrink() : null,
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s16,
        CruSpace.s16,
        CruSpace.s16,
        CruSpace.s6,
      ),
      child: Semantics(
        header: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(title, style: CruType.groupLabel.tint(c.label2)),
            const SizedBox(width: CruSpace.s8),
            Text(
              '$count',
              style: CruType.groupLabel.w500.tabular.tint(c.label3),
            ),
          ],
        ),
      ),
    );
  }
}

/// One 64 px table row.
class PatientTableRow extends StatelessWidget {
  const PatientTableRow({
    super.key,
    required this.summary,
    required this.now,
    required this.onTap,
    this.narrow = false,
    this.selected = false,
    this.onChart,
  });

  final PatientSummary summary;
  final DateTime now;
  final VoidCallback onTap;

  /// Opens Charting for this patient; null hides the button.
  final VoidCallback? onChart;
  final bool narrow;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final s = summary;
    final p = s.patient;
    final phone = p.phone.trim().isEmpty ? null : PatientFormat.phone(p.phone);
    final dash = Text('—', style: CruType.text.tint(c.label3));

    Widget twoLine(Widget top, String? bottom, {bool tabularBottom = true}) =>
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            top,
            if (bottom != null)
              CruTimeText(
                bottom,
                style:
                    (tabularBottom ? CruType.subhead.tabular : CruType.subhead)
                        .tint(c.label2),
                timeColor: c.accentText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        );

    final condition = s.condition;
    final treatment = PatientFormat.treatmentLine(s);
    final Widget conditionCell = condition == null && treatment == null
        ? dash
        : twoLine(
            condition == null
                ? Text(
                    treatment!,
                    style: CruType.subhead.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    condition,
                    style: CruType.callout.w500.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            condition == null ? null : treatment,
            tabularBottom: false,
          );

    final last = s.lastVisit;
    final Widget lastCell = last == null
        ? dash
        : twoLine(
            Text(
              PatientFormat.day(last.scheduledStart, now),
              style: CruType.text.tint(c.label),
              maxLines: 1,
            ),
            DashFormat.time(last.scheduledStart),
          );

    final next = s.nextVisit;
    final overdue = s.overdueSince;
    final Widget nextCell;
    if (next != null) {
      nextCell = twoLine(
        Text(
          PatientFormat.day(next.scheduledStart, now),
          style: CruType.text.tint(c.label),
          maxLines: 1,
        ),
        DashFormat.time(next.scheduledStart),
      );
    } else if (overdue != null) {
      nextCell = twoLine(
        Text('Overdue', style: CruType.text.w600.tint(c.amberText)),
        'since ${PatientFormat.weekdayDate(overdue)}',
      );
    } else {
      nextCell = dash;
    }

    final balanceCell = Text(
      s.hasBalance ? PatientFormat.rupees(s.balance) : '—',
      textAlign: TextAlign.end,
      maxLines: 1,
      style: s.hasBalance
          ? CruType.text.w600.tabular.tint(c.amberText)
          : CruType.text.tint(c.label3),
    );

    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: 'Preview ${s.name}',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: CruSize.tableRow,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
        decoration: ShapeDecoration(
          color: selected
              ? c.accentTint
              : (hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0)),
          shape: cruShape(
            CruRadius.control,
            side: selected
                ? BorderSide(color: c.accent, width: 1.5)
                : BorderSide.none,
          ),
        ),
        child: _Columns(
          narrow: narrow,
          patient: Row(
            children: [
              CruMonogram(
                name: s.name,
                size: CruSize.monogramList,
                background: selected ? c.surface : null,
                foreground: selected ? c.accentText : null,
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: twoLine(
                  Text(
                    s.name,
                    style: CruType.row.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Patient ID is a GAP (UUIDs only): phone alone.
                  phone,
                ),
              ),
            ],
          ),
          age: Text(
            PatientFormat.ageSex(p),
            style: CruType.text.tabular.tint(c.label),
            maxLines: 1,
          ),
          condition: conditionCell,
          last: lastCell,
          next: nextCell,
          balance: balanceCell,
          chart: onChart == null
              ? null
              : _ChartButton(name: s.name, onTap: onChart!),
          chevron: CruIcon(
            CruIcons.chevronRight,
            size: 16,
            strokeWidth: 2,
            color: c.label3,
          ),
        ),
      ),
    );
  }
}
