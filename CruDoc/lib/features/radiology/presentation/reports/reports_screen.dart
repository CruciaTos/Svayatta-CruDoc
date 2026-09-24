import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/phrase_library.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/template_manager.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum _ReportFilter { all, drafts, preliminary, finalised }

/// Every report written: what's still a draft, what waits for a
/// signature, what was signed and sent. A row opens the report.
class RadReportsScreen extends ConsumerStatefulWidget {
  const RadReportsScreen({super.key});

  @override
  ConsumerState<RadReportsScreen> createState() => _RadReportsScreenState();
}

class _RadReportsScreenState extends ConsumerState<RadReportsScreen> {
  _ReportFilter _filter = _ReportFilter.all;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final reportsAsync = ref.watch(radReportsProvider);
    final studiesAsync = ref.watch(radStudiesProvider);
    final referrers = ref.watch(radReferrerByIdProvider);
    final now = DateTime.now();
    final loading = !reportsAsync.hasValue || !studiesAsync.hasValue;

    final studyById = {for (final s in studiesAsync.value ?? const <RadStudy>[]) s.id: s};
    final items = <(RadReport, RadStudy)>[
      for (final r in reportsAsync.value ?? const <RadReport>[])
        if (studyById[r.studyId] != null) (r, studyById[r.studyId]!),
    ]..sort((a, b) => b.$1.updatedAt.compareTo(a.$1.updatedAt));

    final weekStart =
        DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final drafts = items.where((e) => e.$1.status == RadReportStatus.draft).toList();
    final prelim = items.where((e) => e.$1.status == RadReportStatus.preliminary).toList();
    final signedWeek = items
        .where((e) => e.$1.signedAt != null && !e.$1.signedAt!.isBefore(weekStart))
        .length;
    final sent = items.where((e) => e.$1.sharedAt != null).toList();
    final sentWeek = sent.where((e) => !e.$1.sharedAt!.isBefore(weekStart)).length;

    final q = _query.trim().toLowerCase();
    final shown = items.where((e) {
      final (r, s) = e;
      final okFilter = switch (_filter) {
        _ReportFilter.all => true,
        _ReportFilter.drafts => r.status == RadReportStatus.draft,
        _ReportFilter.preliminary => r.status == RadReportStatus.preliminary,
        _ReportFilter.finalised => r.status == RadReportStatus.finalised,
      };
      if (!okFilter) return false;
      if (q.isEmpty) return true;
      final by = referrers[s.referrerId];
      return s.patientName.toLowerCase().contains(q) ||
          r.title.toLowerCase().contains(q) ||
          s.modality.short.toLowerCase().contains(q) ||
          (by?.display.toLowerCase().contains(q) ?? false);
    }).toList();

    // Grouped by the day each was last worked on, newest first.
    final groups = <String, List<(RadReport, RadStudy)>>{};
    for (final e in shown) {
      (groups[DentalFormat.day(e.$1.updatedAt, now)] ??= []).add(e);
    }

    Widget cell(String label, String value, Widget caption) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [GlanceLabel(label), GlanceMetric(value), GlanceCaption(caption)],
        );

    final open = drafts.length + prelim.length;
    return Padding(
      padding: CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(
            title: 'Reports',
            subtitle: loading
                ? 'Your radiology reports'
                : open == 0
                    ? (items.isEmpty
                        ? 'Your radiology reports'
                        : 'Nothing left to finish · ${DashFormat.plural(items.length, 'report')}')
                    : '${DashFormat.plural(open, 'report')} to finish',
            actions: [
              CruButton(
                label: 'Templates',
                icon: RadIcons.template,
                kind: CruButtonKind.secondary,
                onPressed: () => showRadTemplateManager(context),
              ),
              CruButton(
                label: 'Phrases',
                icon: RadIcons.phrase,
                kind: CruButtonKind.secondary,
                onPressed: () => showRadPhraseLibrary(context),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          if (loading)
            const SkeletonCard(rows: 1, rowHeight: 72)
          else
            GlanceStrip(
              semanticLabel: 'Reports at a glance',
              cells: [
                cell(
                  'Drafts',
                  '${drafts.length}',
                  drafts.isEmpty
                      ? const Text('None half-written')
                      : Text('Oldest: ${RadFormat.ago(drafts.last.$1.updatedAt, now)}'),
                ),
                cell(
                  'Awaiting signature',
                  '${prelim.length}',
                  prelim.isEmpty
                      ? const Text('None waiting')
                      : Text('Preliminary, not signed',
                          style: CruType.caption.tint(c.amberText)),
                ),
                cell('Signed this week', '$signedWeek', const Text('Since Monday')),
                cell(
                  'Sent this week',
                  '$sentWeek',
                  Text(sent.isEmpty ? 'None sent yet' : '${sent.length} sent in all'),
                ),
              ],
            ),
          const SizedBox(height: CruSpace.cardGap),
          Row(
            children: [
              CruSegmentedControl<_ReportFilter>(
                semanticLabel: 'Show',
                segments: const [
                  CruSegment(_ReportFilter.all, 'All'),
                  CruSegment(_ReportFilter.drafts, 'Drafts'),
                  CruSegment(_ReportFilter.preliminary, 'Preliminary'),
                  CruSegment(_ReportFilter.finalised, 'Final'),
                ],
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
              const Spacer(),
              SizedBox(
                width: 280,
                child: DentalSearchField(
                  controller: _search,
                  hint: 'Search patient, title or referrer',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
            child: CruCard(
              semanticLabel: 'Reports',
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: loading
                  ? const SizedBox.shrink()
                  : shown.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            child: DentalEmptyState(
                              icon: RadIcons.report,
                              title: items.isEmpty ? 'No reports yet' : 'No reports here',
                              body: items.isEmpty
                                  ? 'Open a study from the worklist and press Report. '
                                      'Drafts save as you type and show up here.'
                                  : 'Try another filter or search.',
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final g in groups.entries) ...[
                              DentalGroupLabel(g.key,
                                  trailing: DashFormat.plural(g.value.length, 'report')),
                              for (var i = 0; i < g.value.length; i++) ...[
                                if (i > 0)
                                  const CruSeparator(
                                    indent: CruSpace.s12 + CruSize.monogramRow + CruSpace.s12,
                                  ),
                                _ReportRow(
                                  report: g.value[i].$1,
                                  study: g.value[i].$2,
                                  referrer: referrers[g.value[i].$2.referrerId],
                                ),
                              ],
                            ],
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report, required this.study, required this.referrer});

  final RadReport report;
  final RadStudy study;
  final RadReferrer? referrer;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final title = report.title.trim();
    final meta = [
      title.isEmpty ? '${study.modality.label} report' : title,
      if (referrer != null) referrer!.display,
      if (report.sharedAt != null) 'Sent by ${report.sharedVia}',
    ].join(' · ');
    return DentalListRow(
      semanticLabel: '${study.patientName}, ${report.status.label}',
      onTap: () => openRadReport(context, study),
      child: Row(
        children: [
          CruMonogram(name: study.patientName),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        study.patientName.isEmpty ? 'Unnamed patient' : study.patientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CruType.callout.tint(c.label),
                      ),
                    ),
                    if (study.critical) ...[
                      const SizedBox(width: CruSpace.s6),
                      Tooltip(
                        message: 'Critical finding',
                        child: CruIcon(RadIcons.flag, size: 14, strokeWidth: 2, color: c.redText),
                      ),
                    ],
                  ],
                ),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tint(c.label2),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          RadModalityBadge(study.modality),
          const SizedBox(width: CruSpace.s12),
          SizedBox(
            width: 72,
            child: Text(
              RadFormat.time(report.updatedAt),
              textAlign: TextAlign.right,
              style: CruType.subhead.tabular.tint(c.label2),
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          SizedBox(
            width: 96,
            child: Align(
              alignment: Alignment.centerRight,
              child: radReportStatusPill(c, report.status),
            ),
          ),
        ],
      ),
    );
  }
}
