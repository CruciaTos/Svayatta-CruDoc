import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/appt_status_style.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/day_grid_metrics.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/visits/home_visit_pill.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_context_region.dart';

/// One visit on the Day grid. 20 minutes or less: one line (name,
/// " · reason", start time on the right). Longer: name with "start to
/// end", then the reason. Home visits carry a house icon, a blue left
/// edge and their address on the second line.
class DayBlock extends StatefulWidget {
  const DayBlock({
    super.key,
    required this.item,
    required this.ringed,
    required this.onTap,
    required this.onDoubleTap,
  });

  final ApptItem item;

  /// 2 px accent ring: the selected block, or every block of a selected
  /// overlap group.
  final bool ringed;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  State<DayBlock> createState() => _DayBlockState();
}

class _DayBlockState extends State<DayBlock> {
  bool _hovered = false;

  /// A second click within [kDoubleTapTimeout] opens the visit. Detected
  /// here so a single click selects without the double-tap delay.
  DateTime? _lastTap;

  void _handleTap() {
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null && now.difference(last) <= kDoubleTapTimeout) {
      _lastTap = null;
      widget.onDoubleTap();
      return;
    }
    _lastTap = now;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final item = widget.item;
    final style = ApptStatusStyle.of(item.status, c);
    final oneLine = item.durationMinutes <= DayGridMetrics.oneLineMaxMinutes;
    final fill = _hovered ? cruHoverShade(style.fill, c) : style.fill;

    final border = widget.ringed
        ? Border.all(
            color: c.accent,
            width: DayGridMetrics.ring,
            strokeAlign: BorderSide.strokeAlignOutside,
          )
        : style.border == null
        ? null
        : Border.all(color: style.border!);

    final block = Semantics(
      button: true,
      selected: widget.ringed,
      label:
          '${item.name}, ${ApptFormat.time(item.start)}'
          '${item.isHomeVisit ? ', home visit' : ''}'
          '${item.detailLine == null ? '' : ', ${item.detailLine}'}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: AnimatedContainer(
            duration: CruMotion.of(context, CruMotion.fast),
            curve: CruMotion.curve,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(DayGridMetrics.blockRadius),
              border: border,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: CruSpace.s12,
              vertical: oneLine ? 0 : CruSpace.s6,
            ),
            // Short visits clip their text instead of overflowing.
            child: ClipRect(
              child: OverflowBox(
                alignment: oneLine ? Alignment.centerLeft : Alignment.topLeft,
                minHeight: 0,
                maxHeight: double.infinity,
                child: oneLine
                    ? _OneLine(item: item, style: style)
                    : _TwoLines(item: item, style: style),
              ),
            ),
          ),
        ),
      ),
    );
    if (!item.isHomeVisit) return ApptContextRegion(item: item, child: block);
    // Home visit: a blue edge down the left side.
    final quiet =
        item.status == ApptStatus.done || item.status == ApptStatus.missed;
    return ApptContextRegion(
      item: item,
      child: Stack(
        children: [
          Positioned.fill(child: block),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: DayGridMetrics.homeEdge,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: quiet ? c.track : c.homeVisit,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(DayGridMetrics.blockRadius),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _quiet(ApptStatusStyle s) => s.check || s.strike;

/// The house after a home visit's name: the house colour, grey once the
/// visit is seen or missed.
class _Home extends StatelessWidget {
  const _Home({required this.style});

  final ApptStatusStyle style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: CruSpace.s4),
    child: CruIcon(
      CruIcons.home,
      size: 13,
      strokeWidth: 2.2,
      color: _quiet(style) ? style.subText : context.cru.homeVisit,
    ),
  );
}

/// "Visit" on the right of a home-visit block, before the time.
List<Widget> _visitPill(ApptItem item, ApptStatusStyle style) => [
  if (item.isHomeVisit) ...[
    HomeVisitPill(quiet: _quiet(style)),
    const SizedBox(width: CruSpace.s8),
  ],
];

TextStyle _nameStyle(ApptStatusStyle s) => CruType.chip.w600.copyWith(
  color: s.text,
  decoration: s.strike ? TextDecoration.lineThrough : null,
  decorationColor: s.text,
);

TextStyle _reasonStyle(ApptStatusStyle s) => CruType.caption.tint(s.subText);

TextStyle _timeStyle(ApptStatusStyle s) => CruType.groupLabel
    .copyWith(fontWeight: FontWeight.w400)
    .tabular
    .tint(s.subText);

/// " · Fever for 3 days · New".
String _detail(ApptItem item) => [
  if (item.reason != null) item.reason!,
  if (item.isNewPatient) 'New',
].map((s) => ' · $s').join();

class _Check extends StatelessWidget {
  const _Check();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: CruSpace.s6),
    child: CruIcon(
      CruIcons.check,
      size: 14,
      strokeWidth: 2.4,
      color: context.cru.green,
    ),
  );
}

class _OneLine extends StatelessWidget {
  const _OneLine({required this.item, required this.style});

  final ApptItem item;
  final ApptStatusStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (style.check) const _Check(),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: item.name,
              style: _nameStyle(style),
              children: [
                if (item.isHomeVisit)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: _Home(style: style),
                  ),
                TextSpan(text: _detail(item), style: _reasonStyle(style)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
        const SizedBox(width: CruSpace.s8),
        ..._visitPill(item, style),
        Text(ApptFormat.clock(item.start), style: _timeStyle(style)),
      ],
    );
  }
}

class _TwoLines extends StatelessWidget {
  const _TwoLines({required this.item, required this.style});

  final ApptItem item;
  final ApptStatusStyle style;

  @override
  Widget build(BuildContext context) {
    // Home visits show the address under the reason.
    final second = item.isHomeVisit
        ? item.detailLine
        : (_detail(item).isEmpty ? null : _detail(item).substring(3));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (style.check) const _Check(),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      item.name,
                      style: _nameStyle(style),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  if (item.isHomeVisit) _Home(style: style),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s8),
            ..._visitPill(item, style),
            Text(
              ApptFormat.blockRange(item.start, item.end),
              style: _timeStyle(style),
            ),
          ],
        ),
        if (second != null)
          Text(
            second,
            style: _reasonStyle(style),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
      ],
    );
  }
}
