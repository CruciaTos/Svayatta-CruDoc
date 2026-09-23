import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_format.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// 14 daily bars, oldest first. A day with nothing dispensed is a flat
/// stub; today is Ink Blue. The first day, a week ago and today carry
/// their day of the month.
class InventoryUsageBars extends StatelessWidget {
  const InventoryUsageBars({
    super.key,
    required this.usage,
    required this.days,
    required this.unit,
  });

  final List<int> usage;
  final List<DateTime> days;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final max = usage.fold<int>(0, (a, b) => a > b ? a : b);
    const labelGap = CruSpace.s4 + 1;
    const barMax = InventorySize.usageChartHeight -
        InventorySize.usageLabelHeight -
        labelGap;
    final last = usage.length - 1;
    final labelled = {0, last - 7, last};
    final todayColor = c.isEvening ? c.accentText : c.accent;

    return SizedBox(
      height: InventorySize.usageChartHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < usage.length; i++) ...[
            if (i > 0) const SizedBox(width: InventorySize.usageBarGap),
            Expanded(
              child: Semantics(
                label: '${DashFormat.shortDate(days[i])}: '
                    '${InventoryFormat.quantity(usage[i], unit)}',
                excludeSemantics: true,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Bar(
                      height: usage[i] <= 0 || max <= 0
                          ? InventorySize.usageStub
                          : (usage[i] / max * barMax)
                              .clamp(CruSpace.s4, barMax),
                      stub: usage[i] <= 0,
                      color: i == last
                          ? todayColor
                          : (usage[i] <= 0 ? c.track : inventoryChartGrey(c)),
                    ),
                    const SizedBox(height: labelGap),
                    SizedBox(
                      height: InventorySize.usageLabelHeight,
                      child: labelled.contains(i)
                          ? Text(
                              '${days[i].day}',
                              style: (i == last
                                      ? CruType.micro.w600
                                      : CruType.micro)
                                  .tabular
                                  .tint(i == last ? c.accentText : c.label3),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.stub, required this.color});

  final double height;
  final bool stub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: height),
      duration: CruMotion.of(context),
      curve: CruMotion.curve,
      builder: (context, h, _) => Container(
        height: h,
        decoration: ShapeDecoration(
          color: color,
          shape: cruShape(stub ? CruRadius.barStub : CruRadius.thinBar),
        ),
      ),
    );
  }
}
