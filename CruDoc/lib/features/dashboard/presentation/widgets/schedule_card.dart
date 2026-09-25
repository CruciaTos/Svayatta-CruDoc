import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

enum ScheduleFilter { all, waiting, done }

/// Today's schedule: every booked visit and queue token, in time order.
class ScheduleCard extends StatefulWidget {
  const ScheduleCard({super.key, required this.items, required this.now});

  final List<ScheduleItem> items;
  final DateTime now;

  @override
  State<ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<ScheduleCard> {
  ScheduleFilter _filter = ScheduleFilter.all;
  bool _showDone = false;
  bool _showLater = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final items = widget.items;
    final now = widget.now;
    final done = items.where((i) => i.status == ScheduleStatus.done).toList();
    final waiting =
        items.where((i) => i.status == ScheduleStatus.waiting).toList();

    final subtitle = items.isEmpty
        ? 'Nothing booked yet'
        : '${DashFormat.plural(items.length, 'appointment')} · '
            '${DashFormat.timeRange(items.first.time, items.last.time)}';

    return CruCard(
      semanticLabel: "Today's schedule",
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: CruSpace.s12,
              spacing: CruSpace.s16,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text("Today's schedule",
                          style: CruType.headline.tint(c.label)),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(subtitle, style: CruType.subhead.tabular.tint(c.label2)),
                  ],
                ),
                if (items.isNotEmpty)
                  CruSegmentedControl<ScheduleFilter>(
                    semanticLabel: 'Filter schedule',
                    selected: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                    segments: [
                      const CruSegment(ScheduleFilter.all, 'All'),
                      CruSegment(ScheduleFilter.waiting, 'Waiting ${waiting.length}'),
                      CruSegment(ScheduleFilter.done, 'Done ${done.length}'),
                    ],
                  ),
              ],
            ),
          ),
          if (items.isEmpty)
            _EmptySchedule()
          else
            AnimatedSize(
              duration: CruMotion.of(context),
              curve: CruMotion.curve,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _body(context, items, done, waiting, now),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    List<ScheduleItem> items,
    List<ScheduleItem> done,
    List<ScheduleItem> waiting,
    DateTime now,
  ) {
    switch (_filter) {
      case ScheduleFilter.waiting:
        return waiting.isEmpty
            ? [const _Note('No one is waiting right now.')]
            : _rows(waiting);
      case ScheduleFilter.done:
        return done.isEmpty
            ? [const _Note('No one has been seen yet today.')]
            : _rows(done);
      case ScheduleFilter.all:
        break;
    }

    final c = context.cru;
    final eveningStart = DateTime(now.year, now.month, now.day,
        kEveningSessionStartHour);
    final inEvening = !now.isBefore(eveningStart);
    final open = items.where((i) => i.status != ScheduleStatus.done).toList();
    // A later session (the evening while it's still day) collapses too.
    final later = inEvening
        ? const <ScheduleItem>[]
        : open.where((i) => !i.time.isBefore(eveningStart)).toList();
    final current = open.where((i) => !later.contains(i)).toList();

    // In the evening, label where the evening session begins when earlier
    // rows sit above it.
    final morningOpen = current.where((i) => i.time.isBefore(eveningStart));
    final eveningOpen = current.where((i) => !i.time.isBefore(eveningStart));
    final showDivider = inEvening &&
        eveningOpen.isNotEmpty &&
        (done.isNotEmpty || morningOpen.isNotEmpty);

    final out = <Widget>[];
    if (done.isNotEmpty) {
      out.add(_CollapsedRow(
        leading: const CruDoneBadge(),
        title: '${done.length} seen ${now.hour < 12 ? 'this morning' : 'today'}',
        detail: DashFormat.names(done.map((i) => i.firstName).toList()),
        expanded: _showDone,
        onToggle: () => setState(() => _showDone = !_showDone),
      ));
      // 6 px before a row; the session divider brings its own spacing.
      if (_showDone || !showDivider || morningOpen.isNotEmpty) {
        out.add(const SizedBox(height: CruSpace.s6));
      }
      if (_showDone) out.addAll(_rows(done));
    }

    if (showDivider) {
      out.addAll(_rows(morningOpen.toList()));
      out.add(_SessionDivider(
        range: DashFormat.timeRange(eveningOpen.first.time, eveningOpen.last.time),
      ));
      out.addAll(_rows(eveningOpen.toList()));
    } else {
      out.addAll(_rows(current));
    }

    if (later.isNotEmpty) {
      out.add(const SizedBox(height: CruSpace.s6));
      out.add(_CollapsedRow(
        leading: CruIcon(CruIcons.moon, size: 20, strokeWidth: 1.8, color: c.label2),
        title: 'Evening session · ${later.length} booked',
        detail: '${DashFormat.names(later.map((i) => i.firstName).toList(), max: 3)}'
            ' · ${DashFormat.timeRange(later.first.time, later.last.time)}',
        expanded: _showLater,
        onToggle: () => setState(() => _showLater = !_showLater),
      ));
      if (_showLater) out.addAll(_rows(later));
    }

    if (c.isEvening && current.isNotEmpty && later.isEmpty) {
      out.add(const _LastBooking());
    }
    return out;
  }

  /// Rows with separators inset to the text column, skipped next to the
  /// highlighted "now" row.
  List<Widget> _rows(List<ScheduleItem> rows) {
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0 && !rows[i].status.isNow && !rows[i - 1].status.isNow) {
        out.add(const CruSeparator(
          indent: CruSize.scheduleTextInset,
          endIndent: CruSpace.s12,
        ));
      }
      out.add(ScheduleRow(item: rows[i]));
    }
    return out;
  }
}

class ScheduleRow extends StatelessWidget {
  const ScheduleRow({super.key, required this.item});

  final ScheduleItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final isNow = item.status.isNow;
    final (hm, ampm) = DashFormat.timeParts(item.time);
    final timeColor = isNow ? c.accentText : c.label;

    return CruPressable(
      onTap: item.patient == null
          ? null
          : () => DashboardActions.openPatient(context, item.patient!),
      semanticLabel: '${DashFormat.time(item.time)}, ${item.name}, '
          '${_statusText(item)}',
      scaleOnPress: false,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        height: CruSize.scheduleRow,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
        decoration: ShapeDecoration(
          color: isNow
              ? c.accentWash
              : (hovered ? c.inset : c.inset.withValues(alpha: 0)),
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            SizedBox(
              width: CruSize.timeColumn,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: hm, style: CruType.row.tabular.tint(timeColor)),
                  TextSpan(
                    text: ' $ampm',
                    style: CruType.micro.tint(isNow ? c.accentText : c.label3),
                  ),
                ]),
                // "11:30 AM" is a hair wider than the 64 px column; let it
                // run into the gap (as the reference does) instead of
                // dropping AM/PM.
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
            const SizedBox(width: CruSpace.s14),
            CruStatusDot(_dotKind(item.status)),
            const SizedBox(width: CruSpace.s14),
            CruMonogram(
              name: item.name,
              background: isNow ? (c.isEvening ? c.track : c.surface) : c.inset,
            ),
            const SizedBox(width: CruSpace.s14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: item.name, style: CruType.row.tint(c.label)),
                      if (item.ageSex != null)
                        TextSpan(
                          text: ' ${item.ageSex}',
                          style: CruType.subhead.tabular.tint(c.label2),
                        ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_secondLine(item) != null)
                    Text(
                      _secondLine(item)!,
                      style: CruType.subhead.tint(c.label2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            _StatusLabel(item: item),
          ],
        ),
      ),
    );
  }

  static String? _secondLine(ScheduleItem i) {
    final parts = [?i.reason, ?i.kindLabel];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static CruDotKind _dotKind(ScheduleStatus s) => switch (s) {
        ScheduleStatus.inConsultation || ScheduleStatus.called => CruDotKind.now,
        ScheduleStatus.waiting => CruDotKind.waiting,
        ScheduleStatus.booked => CruDotKind.booked,
        ScheduleStatus.done => CruDotKind.done,
        ScheduleStatus.missed || ScheduleStatus.skipped => CruDotKind.inactive,
      };
}

String _statusText(ScheduleItem i) => switch (i.status) {
      ScheduleStatus.inConsultation => 'In consultation',
      ScheduleStatus.called => 'Called in',
      ScheduleStatus.waiting => 'Waiting · ${DashFormat.minutes(i.waitMinutes ?? 0)}',
      ScheduleStatus.booked => 'Booked',
      ScheduleStatus.done => 'Seen',
      ScheduleStatus.missed => 'Missed',
      ScheduleStatus.skipped => 'Skipped',
    };

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.item});
  final ScheduleItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final text = _statusText(item);
    return switch (item.status) {
      ScheduleStatus.inConsultation || ScheduleStatus.called => CruPill(
          text: text,
          background: c.accentTint,
          foreground: c.accentText,
        ),
      ScheduleStatus.waiting =>
        Text(text, style: CruType.subhead.w600.tabular.tint(c.amberText)),
      ScheduleStatus.done =>
        Text(text, style: CruType.subhead.w500.tint(c.greenText)),
      _ => Text(text, style: CruType.subhead.w500.tint(c.label3)),
    };
  }
}

/// 48 px inset row that collapses a group ("5 seen this morning").
class _CollapsedRow extends StatelessWidget {
  const _CollapsedRow({
    required this.leading,
    required this.title,
    required this.detail,
    required this.expanded,
    required this.onToggle,
  });

  final Widget leading;
  final String title;
  final String detail;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onToggle,
      semanticLabel: '$title. ${expanded ? 'Hide' : 'Show'}',
      scaleOnPress: false,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        height: CruSize.collapsedRow,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(c.inset, c) : c.inset,
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: CruSpace.s12),
            Text(title, style: CruType.callout.tabular.tint(c.label)),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Text(
                detail,
                style: CruType.subhead.tabular.tint(c.label2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: CruSpace.s8),
            Text(expanded ? 'Hide' : 'Show',
                style: CruType.subhead.w600.tint(c.accentText)),
            const SizedBox(width: CruSpace.s4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: CruMotion.of(context),
              curve: CruMotion.curve,
              child: CruIcon(CruIcons.chevronDown,
                  size: 14, strokeWidth: 2.2, color: c.accentText),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionDivider extends StatelessWidget {
  const _SessionDivider({required this.range});
  final String range;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
      child: Row(
        children: [
          Text('Evening session', style: CruType.groupLabel.tint(c.label2)),
          const SizedBox(width: CruSpace.s10),
          Text(range, style: CruType.groupLabel.w500.copyWith(
            fontWeight: FontWeight.w400,
            color: c.label3,
            fontFeatures: CruType.tabular,
          )),
          const SizedBox(width: CruSpace.s10),
          Expanded(child: SizedBox(height: 1, child: ColoredBox(color: c.separator))),
        ],
      ),
    );
  }
}

class _LastBooking extends StatelessWidget {
  const _LastBooking();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CruSeparator(
          indent: CruSize.scheduleTextInset,
          endIndent: CruSpace.s12,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              CruSize.scheduleTextInset, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text("That's the last booking for today.",
                    style: CruType.subhead.tint(c.label2)),
              ),
              CruLink(
                label: 'Add a walk-in',
                onPressed: () => DashboardActions.newVisit(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Booked visits and walk-ins you check in will appear here.',
              style: CruType.subhead.tint(c.label2),
            ),
          ),
          CruLink(
            label: 'Add a walk-in',
            onPressed: () => DashboardActions.newVisit(context),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Text(text, style: CruType.subhead.tint(context.cru.label2)),
      );
}
