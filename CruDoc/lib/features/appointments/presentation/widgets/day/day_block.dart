import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/appt_status_style.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/day_grid_metrics.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One visit on the Day grid. 20 minutes or less: one line (name,
/// " · reason", start time on the right). Longer: name with "start to
/// end", then the reason.
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

    return Semantics(
      button: true,
      selected: widget.ringed,
      label: '${item.name}, ${ApptFormat.time(item.start)}'
          '${item.reason == null ? '' : ', ${item.reason}'}',
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
  }
}

TextStyle _nameStyle(ApptStatusStyle s) => CruType.chip.w600.copyWith(
      color: s.text,
      decoration: s.strike ? TextDecoration.lineThrough : null,
      decorationColor: s.text,
    );

TextStyle _reasonStyle(ApptStatusStyle s) => CruType.caption.tint(s.subText);

TextStyle _timeStyle(ApptStatusStyle s) =>
    CruType.groupLabel.copyWith(fontWeight: FontWeight.w400).tabular.tint(s.subText);

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
                TextSpan(text: _detail(item), style: _reasonStyle(style)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
        const SizedBox(width: CruSpace.s8),
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
    final detail = _detail(item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (style.check) const _Check(),
            Expanded(
              child: Text(
                item.name,
                style: _nameStyle(style),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
            const SizedBox(width: CruSpace.s8),
            Text(
              ApptFormat.blockRange(item.start, item.end),
              style: _timeStyle(style),
            ),
          ],
        ),
        if (detail.isNotEmpty)
          Text(
            // Drop the leading " · " on its own line.
            detail.substring(3),
            style: _reasonStyle(style),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
      ],
    );
  }
}
