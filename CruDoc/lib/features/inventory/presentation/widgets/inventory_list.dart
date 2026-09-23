import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/inventory/domain/inventory_format.dart';
import 'package:doctor_management_app/features/inventory/domain/inventory_models.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_style.dart';
import 'package:doctor_management_app/features/inventory/presentation/widgets/inventory_vial.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

typedef InventoryItemTap = void Function(InventoryItem item);

/// List view: the card with Item / In stock / Lasts / Next expiry
/// columns, 64 px rows and "Showing N of M".
class InventoryList extends StatelessWidget {
  const InventoryList({
    super.key,
    required this.view,
    required this.selectedId,
    required this.onTap,
    this.selectedKey,
    this.empty,
  });

  final InventoryView view;

  /// Highlighted row (accent wash + ring); null for none.
  final String? selectedId;
  final InventoryItemTap onTap;

  /// Put on the selected row so keyboard moves can scroll it into view.
  final GlobalKey? selectedKey;

  /// Shown instead of rows when nothing matches.
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final showLasts = view.hasUsage;
    final rows = view.visible;
    final children = <Widget>[
      _Columns(
        showLasts: showLasts,
        height: CruSize.tableHeader,
        item: _headerText(context, 'Item'),
        stock: _headerText(context, 'In stock'),
        lasts: _headerText(context, 'Lasts'),
        expiry: _headerText(context, 'Next expiry'),
        chevron: const SizedBox.shrink(),
      ),
      const CruSeparator(),
      const SizedBox(height: CruSpace.s6),
      if (rows.isEmpty && empty != null) empty!,
    ];
    for (var i = 0; i < rows.length; i++) {
      final item = rows[i];
      final selected = item.id == selectedId;
      if (i > 0) {
        final prevSelected = rows[i - 1].id == selectedId;
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
      final row = InventoryRow(
        item: item,
        now: view.now,
        showLasts: showLasts,
        selected: selected,
        onTap: () => onTap(item),
      );
      children.add(
        selected && selectedKey != null
            ? KeyedSubtree(key: selectedKey, child: row)
            : row,
      );
    }
    if (rows.isNotEmpty) {
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
                  'Showing ${InventoryFormat.count(rows.length)} of '
                  '${InventoryFormat.count(view.rows.length)}',
                  style: CruType.subhead.tabular.tint(c.label3),
                ),
              ),
              if (rows.length < view.rows.length)
                Text('Scroll for more', style: CruType.subhead.tint(c.label3)),
            ],
          ),
        ),
      );
    }

    return CruCard(
      semanticLabel: 'Items',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        CruSpace.s6,
        CruSpace.s12,
        CruSpace.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _headerText(BuildContext context, String text) => Text(
        text,
        style: CruType.caption.w600.tint(context.cru.label2),
        maxLines: 1,
      );
}

/// The fixed column grid shared by the header and rows.
class _Columns extends StatelessWidget {
  const _Columns({
    required this.showLasts,
    required this.height,
    required this.item,
    required this.stock,
    required this.lasts,
    required this.expiry,
    required this.chevron,
  });

  final bool showLasts;
  final double height;
  final Widget item;
  final Widget stock;
  final Widget lasts;
  final Widget expiry;
  final Widget chevron;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: InventorySize.columnGap);
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
        child: Row(
          children: [
            Expanded(child: item),
            gap,
            SizedBox(width: InventorySize.stockColumn, child: stock),
            if (showLasts) ...[
              gap,
              SizedBox(width: InventorySize.lastsColumn, child: lasts),
            ],
            gap,
            SizedBox(width: InventorySize.expiryColumn, child: expiry),
            gap,
            SizedBox(width: CruSize.tableChevronColumn, child: chevron),
          ],
        ),
      ),
    );
  }
}

/// One 64 px item row.
class InventoryRow extends StatelessWidget {
  const InventoryRow({
    super.key,
    required this.item,
    required this.now,
    required this.showLasts,
    required this.selected,
    required this.onTap,
  });

  final InventoryItem item;
  final DateTime now;
  final bool showLasts;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final dash = Text('—', style: CruType.text.tabular.tint(c.label3));
    final form = InventoryFormat.form(item.unit);

    // Item: tile, name, form (a GAP: the unit stands in).
    final itemCell = Row(
      children: [
        CruIconTile(
          icon: inventoryItemIcon(item),
          tone: item.low ? CruTileTone.amber : CruTileTone.neutral,
        ),
        const SizedBox(width: CruSpace.s12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: CruType.row.tint(c.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (form.isNotEmpty)
                Text(
                  form,
                  style: CruType.subhead.tint(c.label2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );

    // In stock: quantity + unit, level bar against the usual order.
    final unit = InventoryFormat.unitFor(item.unit, item.stock);
    final level = item.level;
    final stockCell = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: InventoryFormat.count(item.stock),
                style: CruType.callout.tabular
                    .tint(item.low ? c.amberText : c.label),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: CruType.text.tint(c.label2),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (level != null) ...[
          const SizedBox(height: CruSpace.s6),
          InventoryLevelBar(value: level, low: item.low),
        ],
      ],
    );

    // Lasts: bold amber at a week or less.
    final daysLeft = item.daysLeft;
    final Widget lastsCell;
    if (daysLeft == null) {
      lastsCell = dash;
    } else {
      final urgent = daysLeft <= 7;
      lastsCell = Text(
        InventoryFormat.lasts(daysLeft, outOfStock: item.outOfStock),
        style: (urgent ? CruType.text.w600 : CruType.text)
            .tabular
            .tint(urgent ? c.amberText : c.label),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Next expiry: amber with "in 5 weeks" under it within 60 days.
    final expiry = item.medicine.expiryDate;
    final Widget expiryCell;
    if (expiry == null) {
      expiryCell = dash;
    } else if (item.expiringSoon) {
      expiryCell = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            InventoryFormat.monthYear(expiry),
            style: CruType.text.w600.tabular.tint(c.amberText),
            maxLines: 1,
          ),
          Text(
            InventoryFormat.inTime(item.daysToExpiry ?? 0),
            style: CruType.caption.tabular.tint(c.label2),
            maxLines: 1,
          ),
        ],
      );
    } else {
      expiryCell = Text(
        InventoryFormat.monthYear(expiry),
        style: CruType.text.tabular.tint(c.label),
        maxLines: 1,
      );
    }

    final label = [
      item.name,
      InventoryFormat.quantity(item.stock, item.unit),
      if (item.low) 'low stock',
      if (showLasts && daysLeft != null)
        'lasts ${InventoryFormat.lasts(daysLeft, outOfStock: item.outOfStock)}',
      if (expiry != null) 'expires ${InventoryFormat.monthYear(expiry)}',
    ].join(', ');

    return Semantics(
      selected: selected,
      child: CruPressable(
        onTap: onTap,
        scaleOnPress: false,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.tableRow,
          decoration: ShapeDecoration(
            color: selected
                ? c.accentWash
                : (hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0)),
            shape: cruShape(CruRadius.control),
          ),
          // The ring is a foreground so it never changes the padding.
          foregroundDecoration: ShapeDecoration(
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(
                color: selected ? c.accent : c.accent.withValues(alpha: 0),
                width: InventorySize.rowRing,
              ),
            ),
          ),
          child: _Columns(
            showLasts: showLasts,
            height: CruSize.tableRow,
            item: itemCell,
            stock: stockCell,
            lasts: Align(alignment: Alignment.centerLeft, child: lastsCell),
            expiry: Align(alignment: Alignment.centerLeft, child: expiryCell),
            chevron: CruIcon(
              CruIcons.chevronRight,
              size: 16,
              strokeWidth: 2,
              color: c.label3,
            ),
          ),
        ),
      ),
    );
  }
}
