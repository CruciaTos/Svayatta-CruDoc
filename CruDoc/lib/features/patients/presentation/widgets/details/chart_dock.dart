import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/charting_records.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Phone Patient details' chart dock (dentists): one icon tile per chart
/// record this patient has, in a fixed order so a tile is always where the
/// hand expects it. The tile shows the record's status under its icon and
/// opens the record; a trailing + opens the records not shown (not started,
/// or past the first four). Nothing is shown until a record has data.
class PatientChartDock extends StatelessWidget {
  const PatientChartDock({super.key, required this.clusters});

  /// `chartRecords(...)`'s result.
  final List<RecordCluster> clusters;

  /// Tiles before the +.
  static const int _tiles = 4;

  /// Fixed order of the dock (lab cases are `lab` in the records).
  static const _order = [
    'perio',
    'endo',
    'pain',
    'ortho',
    'eruption',
    'srp',
    'checklist',
    'sedation',
    'consent',
    'lab',
    'referral',
    'forms',
  ];

  /// Whether any record has data (else the dock is not shown at all).
  static bool hasData(List<RecordCluster> clusters) => clusters.any(
    (cluster) => cluster.records.any((r) => !r.action && r.status != null),
  );

  static int _rank(ChartRecord r) {
    final i = _order.indexOf(r.id);
    return i < 0 ? _order.length : i;
  }

  static MobileTone _tone(RecordTone t) => switch (t) {
    RecordTone.plain => MobileTone.slate,
    RecordTone.warn => MobileTone.amber,
    RecordTone.done => MobileTone.green,
  };

  @override
  Widget build(BuildContext context) {
    final all = [
      for (final cluster in clusters)
        for (final r in cluster.records)
          if (!r.action) r,
    ];
    // Records outside the list keep the shelf's order (Dart's sort is not
    // stable, so the shelf position breaks ties).
    final withData =
        [
          for (final r in all)
            if (r.status != null) r,
        ]..sort((a, b) {
          final byRank = _rank(a).compareTo(_rank(b));
          return byRank != 0
              ? byRank
              : all.indexOf(a).compareTo(all.indexOf(b));
        });
    if (withData.isEmpty) return const SizedBox.shrink();

    final shown = withData.take(_tiles).toList();
    final more = [
      ...withData.skip(_tiles),
      for (final r in all)
        if (r.status == null) r,
    ];

    void openMore() => showMobileActionSheet(
      context,
      title: 'Chart records',
      actions: [
        for (final r in more)
          MobileSheetAction(
            label: r.title ?? r.label,
            detail: r.status,
            icon: r.icon,
            tone: _tone(r.tone),
            onTap: r.onOpen,
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MobileGroupTitle('Chart', onBackground: true),
        const SizedBox(height: CruSpace.s8),
        Row(
          children: [
            for (var i = 0; i < _tiles + 1; i++) ...[
              if (i > 0) const SizedBox(width: CruSpace.s8),
              Expanded(
                child: i < shown.length
                    ? _RecordTile(record: shown[i])
                    : (i == _tiles && more.isNotEmpty)
                    ? _MoreTile(onTap: openMore)
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final ChartRecord record;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      label: '${record.label}, ${record.status}',
      button: true,
      excludeSemantics: true,
      onTap: record.onOpen,
      child: Tooltip(
        message: record.label,
        child: MobileCard(
          onTap: record.onOpen,
          padding: const EdgeInsets.symmetric(
            vertical: CruSpace.s12,
            horizontal: CruSpace.s4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MobileIconTile(
                icon: record.icon,
                tone: PatientChartDock._tone(record.tone),
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(height: CruSpace.s8),
              Text(
                record.dockLabel ?? record.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: MobileType.micro.w600.tint(c.label),
              ),
              Text(
                record.status!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: MobileType.micro.tabular.tint(c.label2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'More chart records',
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: MobileCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          vertical: CruSpace.s12,
          horizontal: CruSpace.s4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MobileIconTile(
              icon: CruIcons.plus,
              tone: MobileTone.blue,
              size: 36,
              iconSize: 18,
            ),
            // Same lines as its neighbours (name + status), so all tiles match.
            const SizedBox(height: CruSpace.s8),
            Text('More', style: MobileType.micro.w600.tint(context.cru.label)),
            Text(' ', style: MobileType.micro.tabular),
          ],
        ),
      ),
    );
  }
}
