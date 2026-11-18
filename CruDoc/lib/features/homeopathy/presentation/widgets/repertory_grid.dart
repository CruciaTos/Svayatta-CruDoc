import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/homeopathy/data/repertory/repertory_engine.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const double _labelW = CruSize.sidebarCollapsed * 2;
const double _cellW = CruSize.actionButton + CruSpace.s16;
const double _headH = CruSize.control;
const double _rowH = CruSize.collapsedRow;
const double _footH = CruSize.control;

/// The classic repertorisation grid: one row per selected rubric, one column
/// per leading remedy, then "Covered", "Score" and "Use" rows. The rubric
/// column stays put while the remedy columns scroll sideways.
class RepertoryGrid extends StatelessWidget {
  const RepertoryGrid({
    super.key,
    required this.result,
    required this.weights,
    required this.chosen,
    required this.onChoose,
    required this.onOpenRemedy,
    required this.hasEntry,
    this.compare = const {},
    this.onToggleCompare,
  });

  final RepertorizationResult result;

  /// Rubric id to weight (1..3).
  final Map<String, int> weights;

  /// The remedy abbreviation stored as the chosen one, if any.
  final String? chosen;

  /// Tap on the "Use" cell of a column.
  final ValueChanged<String> onChoose;

  /// Tap on a column header; only called when [hasEntry] says the remedy has
  /// a Materia medica page.
  final ValueChanged<String> onOpenRemedy;
  final bool Function(String abbr) hasEntry;

  /// Remedy abbreviations picked (press and hold on the header) for compare.
  final Set<String> compare;

  /// Long press on a column header; null turns the gesture off.
  final ValueChanged<String>? onToggleCompare;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final remedies = result.remedies;
    final rule = BoxDecoration(
      border: Border(bottom: BorderSide(color: c.hairline)),
    );

    Widget labelCell(Widget child, double h) => Container(
      width: _labelW,
      height: h,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(right: CruSpace.s8),
      decoration: rule,
      child: child,
    );

    Widget cell(Widget child, double h, {Color? fill}) => Container(
      width: _cellW,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: child,
    );

    TextStyle gradeStyle(int g) => switch (g) {
      3 => CruType.callout.w700.tabular.tint(c.label),
      2 => CruType.callout.w600.tabular.tint(c.label),
      _ => CruType.callout.tabular.tint(c.label2),
    };

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labelCell(Text('Rubric', style: CruType.micro.tint(c.label3)), _headH),
        for (final r in result.rubrics)
          labelCell(
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: r.leaf,
                    style: CruType.caption.w600.tint(c.label),
                  ),
                  if ((weights[r.id] ?? 1) > 1)
                    TextSpan(
                      text: '  x${weights[r.id]}',
                      style: CruType.caption.w600.tabular.tint(c.label2),
                    ),
                  if (r.parent.isNotEmpty)
                    TextSpan(
                      text: '\n${r.parent}',
                      style: CruType.micro.tint(c.label3),
                    ),
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            _rowH,
          ),
        labelCell(
          Text('Covered', style: CruType.caption.w600.tint(c.label2)),
          _footH,
        ),
        labelCell(
          Text('Score', style: CruType.caption.w600.tint(c.label2)),
          _footH,
        ),
        labelCell(
          Text('Use this remedy', style: CruType.caption.w600.tint(c.label2)),
          _footH,
        ),
      ],
    );

    final right = Column(
      children: [
        Row(
          children: [
            for (final s in remedies)
              cell(
                CruPressable(
                  onTap: hasEntry(s.abbr) ? () => onOpenRemedy(s.abbr) : null,
                  semanticLabel: hasEntry(s.abbr)
                      ? 'Open ${s.abbr} in Materia medica'
                      : s.abbr,
                  builder: (context, hovered) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: hasEntry(s.abbr) && onToggleCompare != null
                        ? () => onToggleCompare!(s.abbr)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CruSpace.s4,
                      ),
                      child: Text(
                        s.abbr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CruType.caption.w600
                            .tint(hasEntry(s.abbr) ? c.accentText : c.label)
                            .copyWith(
                              decoration: compare.contains(s.abbr)
                                  ? TextDecoration.underline
                                  : null,
                              decorationColor: c.accentText,
                            ),
                      ),
                    ),
                  ),
                ),
                _headH,
                fill: s.abbr == chosen
                    ? c.greenTint
                    : (compare.contains(s.abbr) ? c.inset : null),
              ),
          ],
        ),
        for (final r in result.rubrics)
          Row(
            children: [
              for (final s in remedies)
                cell(
                  s.grades[r.id] == null
                      ? const SizedBox.shrink()
                      : Text(
                          '${s.grades[r.id]}',
                          style: gradeStyle(s.grades[r.id]!),
                        ),
                  _rowH,
                  fill: s.abbr == chosen ? c.greenTint : null,
                ),
            ],
          ),
        Row(
          children: [
            for (final s in remedies)
              cell(
                Text(
                  '${s.covered}',
                  style: CruType.callout.w600.tabular.tint(c.label),
                ),
                _footH,
                fill: s.abbr == chosen ? c.greenTint : null,
              ),
          ],
        ),
        Row(
          children: [
            for (final s in remedies)
              cell(
                Text(
                  '${s.score}',
                  style: CruType.callout.w600.tabular.tint(c.label),
                ),
                _footH,
                fill: s.abbr == chosen ? c.greenTint : null,
              ),
          ],
        ),
        Row(
          children: [
            for (final s in remedies)
              cell(
                CruPressable(
                  onTap: () => onChoose(s.abbr),
                  semanticLabel: s.abbr == chosen
                      ? 'Stop using ${s.abbr} as the chosen remedy'
                      : 'Use ${s.abbr} as the chosen remedy',
                  builder: (context, hovered) => Container(
                    width: CruSpace.s24,
                    height: CruSpace.s24,
                    decoration: ShapeDecoration(
                      color: s.abbr == chosen
                          ? c.greenTint
                          : (hovered ? c.inset : c.surface),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: s.abbr == chosen ? c.greenText : c.separator,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: s.abbr == chosen
                        ? CruIcon(
                            CruIcons.check,
                            size: CruSpace.s14,
                            strokeWidth: 2.4,
                            color: c.greenText,
                          )
                        : null,
                  ),
                ),
                _footH,
                fill: s.abbr == chosen ? c.greenTint : null,
              ),
          ],
        ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        left,
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: right,
          ),
        ),
      ],
    );
  }
}
