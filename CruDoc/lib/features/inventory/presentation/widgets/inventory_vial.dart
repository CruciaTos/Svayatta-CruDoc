import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';

/// A vertical vial: a track that fills to stock ÷ usual order, coloured by
/// [StockState] (green, blue, amber, red), with a 2 px notch at the
/// reorder level.
/// Without a usual order (GAP for that item) the fill and notch are
/// hidden and only the empty track shows.
class InventoryVial extends StatelessWidget {
  const InventoryVial({
    super.key,
    required this.width,
    required this.height,
    required this.fill,
    required this.notch,
    required this.state,
  });

  final double width;
  final double height;

  /// 0–1, or null to hide the fill.
  final double? fill;

  /// 0–1, or null to hide the notch.
  final double? notch;

  final StockState state;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fillColor = stockFill(c, state);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width / 2),
        child: SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: c.track,
            child: Stack(
              children: [
                if (fill != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: fill!),
                      duration: CruMotion.of(context),
                      curve: CruMotion.curve,
                      builder: (context, f, _) => Container(
                        height: height * f,
                        color: fillColor,
                      ),
                    ),
                  ),
                if (notch != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: (height * notch! - InventorySize.notch / 2)
                        .clamp(0.0, height - InventorySize.notch),
                    height: InventorySize.notch,
                    child: ColoredBox(color: c.surface),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 96 × 4 bar under a list row's stock quantity.
class InventoryLevelBar extends StatelessWidget {
  const InventoryLevelBar({
    super.key,
    required this.value,
    required this.state,
  });

  final double value;
  final StockState state;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    const w = InventorySize.levelBarWidth;
    const h = InventorySize.levelBarHeight;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(h / 2),
        child: SizedBox(
          width: w,
          height: h,
          child: ColoredBox(
            color: c.track,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: value.clamp(0.0, 1.0)),
                duration: CruMotion.of(context),
                curve: CruMotion.curve,
                builder: (context, v, _) => Container(
                  width: w * v,
                  height: h,
                  decoration: BoxDecoration(
                    color: stockFill(c, state),
                    borderRadius: BorderRadius.circular(h / 2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
