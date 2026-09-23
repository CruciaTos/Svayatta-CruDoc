import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_builder.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_format.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_actions.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_usage_bars.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_vial.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The 384 px panel beside (or, below 1200 px, over) the list: status,
/// stock, the last two weeks of use, batch, a reorder suggestion and
/// Adjust stock.
class InventoryItemPanel extends ConsumerWidget {
  const InventoryItemPanel({
    super.key,
    required this.item,
    required this.now,
    required this.hasUsage,
    this.onClose,
  });

  final InventoryItem item;
  final DateTime now;

  /// False when no item has usage: the usage chart and "Lasts" are hidden.
  final bool hasUsage;

  /// Shown as × when the panel is a sheet (Esc also closes it).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showSuggestion =
        item.usualOrder != null && (item.low || item.runsOutThisWeek);
    final showBatch = item.batch != null || item.medicine.expiryDate != null;

    final blocks = <Widget>[
      _Head(item: item, now: now, hasUsage: hasUsage, onClose: onClose),
      _StockBlock(item: item),
      if (hasUsage) ...[
        _UsageBlock(item: item),
        const CruSeparator(),
      ],
      if (showBatch) _BatchBlock(item: item),
      if (showSuggestion) _Suggestion(item: item),
      CruButton(
        label: 'Adjust stock',
        kind: CruButtonKind.inset,
        expand: true,
        onPressed: () =>
            InventoryActions.adjustStock(context, ref, item.medicine),
      ),
    ];

    return InventoryPanelFrame(
      label: item.name,
      child: AnimatedSwitcher(
        duration: CruMotion.of(context, CruMotion.fast),
        switchInCurve: CruMotion.curve,
        switchOutCurve: CruMotion.curve,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: Column(
          key: ValueKey(item.id),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < blocks.length; i++) ...[
              if (i > 0) const SizedBox(height: CruSpace.s14),
              blocks[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// The panel's card: surface, radius 24, hairline, scrolls when taller
/// than the window.
class InventoryPanelFrame extends StatelessWidget {
  const InventoryPanelFrame({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      container: true,
      label: label,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.surface,
          shape: cruShape(CruRadius.card, side: BorderSide(color: c.hairline)),
          shadows: c.cardShadow,
        ),
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.all(CruSpace.s20),
          child: child,
        ),
      ),
    );
  }
}

/// Loading placeholder with the panel's proportions.
class InventoryPanelSkeleton extends StatelessWidget {
  const InventoryPanelSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return InventoryPanelFrame(
      label: 'Loading item',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 140, height: 12),
          const SizedBox(height: CruSpace.s10),
          const SkeletonBox(width: 220, height: 20),
          const SizedBox(height: CruSpace.s8),
          const SkeletonBox(width: 160, height: 12),
          const SizedBox(height: CruSpace.s14),
          Container(
            height: InventorySize.panelVialHeight + 2 * CruSpace.s14,
            decoration: ShapeDecoration(
              color: c.inset,
              shape: cruShape(CruRadius.strip),
            ),
          ),
          const SizedBox(height: CruSpace.s14),
          const SkeletonBox(width: 180, height: 14),
          const SizedBox(height: CruSpace.s14),
          const SkeletonBox(height: InventorySize.usageChartHeight),
          const SizedBox(height: CruSpace.s14),
          const SkeletonBox(height: CruSize.control),
        ],
      ),
    );
  }
}

class _Head extends ConsumerWidget {
  const _Head({
    required this.item,
    required this.now,
    required this.hasUsage,
    required this.onClose,
  });

  final InventoryItem item;
  final DateTime now;
  final bool hasUsage;
  final VoidCallback? onClose;

  /// Amber "Runs out in about N days" when low, amber "Expires in Oct"
  /// when expiring, otherwise grey "Lasts about N weeks".
  (String, bool)? _eyebrow() {
    final daysLeft = hasUsage ? item.daysLeft : null;
    final expiry = item.medicine.expiryDate;
    if (item.outOfStock) return ('Out of stock', true);
    if (item.low) {
      if (daysLeft == null) return ('Low stock', true);
      if (daysLeft < 1) return ('Runs out today', true);
      return ('Runs out in about ${InventoryFormat.span(daysLeft)}', true);
    }
    if (item.expiringSoon && expiry != null && item.daysToExpiry != null) {
      return (InventoryFormat.expiresIn(expiry, item.daysToExpiry!, now), true);
    }
    if (daysLeft != null) {
      return ('Lasts about ${InventoryFormat.span(daysLeft)}', false);
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final eyebrow = _eyebrow();
    final subtitle = [
      InventoryFormat.form(item.unit),
      ?item.category,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null)
                Text(
                  eyebrow.$1,
                  style: CruType.subhead.w600
                      .tint(eyebrow.$2 ? c.amberText : c.label2),
                ),
              Semantics(
                header: true,
                child: Text(
                  item.name,
                  style: CruType.title2.tint(c.label),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: CruType.subhead.tint(c.label2)),
            ],
          ),
        ),
        const SizedBox(width: CruSpace.s12),
        _MoreMenu(item: item),
        if (onClose != null)
          CruIconButton(
            icon: CruIcons.close,
            size: CruSize.squareButton,
            iconSize: 18,
            semanticLabel: 'Close',
            tooltip: 'Close',
            onPressed: onClose,
          ),
      ],
    );
  }
}

/// "…": Edit item, Archive.
class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final itemShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(CruRadius.control - CruSpace.s6),
    );
    ButtonStyle style() => ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, CruSize.control)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: CruSpace.s12),
          ),
          shape: WidgetStatePropertyAll(itemShape),
          overlayColor:
              WidgetStatePropertyAll(c.hoverFill.withValues(alpha: 0)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? c.hoverFill
                : c.surface,
          ),
        );
    return MenuAnchor(
      alignmentOffset: const Offset(0, CruSpace.s6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor:
            WidgetStatePropertyAll(c.surface.withValues(alpha: 0)),
        shadowColor: WidgetStatePropertyAll(c.label.withValues(alpha: 0.18)),
        elevation: WidgetStatePropertyAll(c.isEvening ? 0 : 8),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(CruSpace.s6)),
        shape: WidgetStatePropertyAll(
          RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(CruRadius.control),
            side: BorderSide(color: c.hairline),
          ),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          style: style(),
          onPressed: () =>
              InventoryActions.editItem(context, ref, item.medicine),
          child: Text('Edit item', style: CruType.text.w500.tint(c.label)),
        ),
        MenuItemButton(
          style: style(),
          onPressed: () =>
              InventoryActions.archive(context, ref, item.medicine),
          child: Text('Archive', style: CruType.text.w500.tint(c.label)),
        ),
      ],
      builder: (context, controller, _) => CruIconButton(
        icon: CruIcons.more,
        size: CruSize.squareButton,
        iconSize: 18,
        semanticLabel: 'More actions for ${item.name}',
        tooltip: 'More actions',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Vial, big quantity, reorder level + usual order, price + supplier.
class _StockBlock extends StatelessWidget {
  const _StockBlock({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final unit = InventoryFormat.unitFor(item.unit, item.stock);
    final reorder = [
      'Reorder at ${InventoryFormat.count(item.reorderLevel)}',
      if (item.usualOrder != null)
        'usual order ${InventoryFormat.count(item.usualOrder!)}',
    ].join(' · ');
    final price = item.medicine.unitPrice;
    final priceLine = [
      if (price != null)
        '${InventoryFormat.rupees(price)} a '
            '${InventoryFormat.singular(item.unit.trim().toLowerCase())}',
      ?item.supplier,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s14,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.strip),
      ),
      child: Row(
        children: [
          InventoryVial(
            width: InventorySize.panelVialWidth,
            height: InventorySize.panelVialHeight,
            fill: item.level,
            notch: item.notch,
            low: item.low,
          ),
          const SizedBox(width: CruSpace.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: InventoryFormat.count(item.stock),
                        style: CruType.largeTitle.tabular
                            .tint(item.low ? c.amberText : c.label),
                      ),
                      TextSpan(
                        text: unit.isEmpty ? ' in stock' : ' $unit in stock',
                        style: CruType.text.tint(c.label2),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  reorder,
                  style: CruType.subhead.tabular.tint(c.label2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (priceLine.isNotEmpty)
                  Text(
                    priceLine,
                    style: CruType.subhead.tabular.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Used in the last 2 weeks": 14 bars and "37 strips · about 3 a day".
class _UsageBlock extends StatelessWidget {
  const _UsageBlock({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Used in the last 2 weeks',
                  style: CruType.row.tint(c.label),
                ),
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            Text(
              InventoryFormat.usageSummary(
                item.usageTotal,
                InventoryBuilder.usageWindowDays,
                item.unit,
              ),
              style: CruType.subhead.tabular.tint(c.label2),
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s14),
        InventoryUsageBars(
          usage: item.usage,
          days: item.usageDays,
          unit: item.unit,
        ),
      ],
    );
  }
}

/// One batch row from the item's batch code and expiry. Several batches,
/// per-batch quantity and "Use first" are a GAP.
class _BatchBlock extends StatelessWidget {
  const _BatchBlock({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final expiry = item.medicine.expiryDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Batches', style: CruType.row.tint(c.label)),
        ),
        const SizedBox(height: CruSpace.s2),
        SizedBox(
          height: CruSize.collapsedRow,
          child: Row(
            children: [
              SizedBox(
                width: InventorySize.batchCodeColumn,
                child: Text(
                  item.batch ?? '—',
                  style: CruType.profileName.tabular
                      .tint(item.batch == null ? c.label3 : c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Text(
                  expiry == null
                      ? 'No expiry date'
                      : 'Expires ${InventoryFormat.monthYear(expiry)}',
                  style: (item.expiringSoon
                          ? CruType.chip.w600.tint(c.amberText)
                          : CruType.chip.tint(c.label2))
                      .tabular,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Order 50 strips from Mehta Pharma" / "₹1,500" on accent wash. The
/// arrival clause (lead time) and the Order button are a GAP.
class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final qty = InventoryFormat.quantity(item.usualOrder!, item.unit);
    final supplier = item.supplier;
    final cost = item.orderCost;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s14,
      ),
      decoration: ShapeDecoration(
        color: c.accentWash,
        shape: cruShape(CruRadius.strip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            supplier == null ? 'Order $qty' : 'Order $qty from $supplier',
            style: CruType.callout.tabular.tint(c.label),
          ),
          if (cost != null) ...[
            const SizedBox(height: CruSpace.s2),
            Text(
              InventoryFormat.rupees(cost),
              style: CruType.caption.tabular.tint(c.label2),
            ),
          ],
        ],
      ),
    );
  }
}
