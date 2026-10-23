import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/presentation/desktop_add_edit_medicine_dialog.dart';
import 'package:doctor_management_app/features/inventory/presentation/stock_adjustment_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

final _rupees = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);
final _day = DateFormat('d MMM yyyy');

/// One item's page (double-click or Enter in Inventory): its details and
/// the full stock history, newest first. Edit opens the same item dialog
/// as Add item.
class MedicineDetailScreen extends ConsumerWidget {
  const MedicineDetailScreen({super.key, required this.medicine});

  final MedicineModel medicine;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDental(
      context,
      title: 'Delete ${medicine.name}?',
      body: 'It leaves the inventory and its stock history goes with it.',
      action: 'Delete',
    );
    if (!ok) return;
    await ref.read(inventoryRepositoryProvider).deleteMedicine(medicine.id);
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${medicine.name} deleted')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    // The live item, so Edit and Adjust stock show here straight away.
    final medicine =
        ref
            .watch(medicinesStreamProvider)
            .value
            ?.where((m) => m.id == this.medicine.id)
            .firstOrNull ??
        this.medicine;
    final history = ref.watch(medicineTransactionsProvider(medicine.id));
    final phone = cruIsPhone(context);
    final subtitle = [
      if (medicine.category.isNotEmpty) medicine.category,
      medicine.unit,
    ].join(' · ');

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Padding(
          padding: phone
              ? CruSpace.mainPaddingPhone
              : const EdgeInsets.all(CruSpace.s32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: CruSize.formDialog + CruSize.rightColumn,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CruLink(
                      label: 'Inventory',
                      leading: CruIcon(
                        CruIcons.chevronLeft,
                        size: 16,
                        color: c.accentText,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(height: CruSpace.s12),
                  DentalPageHeader(
                    title: medicine.name,
                    subtitle: subtitle,
                    actions: [
                      CruButton(
                        label: 'Delete',
                        kind: CruButtonKind.inset,
                        onPressed: () => _delete(context, ref),
                      ),
                      CruButton(
                        label: 'Edit',
                        kind: CruButtonKind.secondary,
                        icon: CruIcons.pen,
                        onPressed: () => showDesktopAddEditMedicineDialog(
                          context,
                          medicine: medicine,
                        ),
                      ),
                      CruButton(
                        label: 'Adjust stock',
                        icon: CruIcons.importExport,
                        onPressed: () => showStockAdjustmentDialog(
                          context,
                          medicine: medicine,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CruSpace.cardGap),
                  _Summary(medicine: medicine),
                  const SizedBox(height: CruSpace.cardGap),
                  Expanded(child: _History(history: history)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stock, reorder level, expiry and the rest, in a grid of facts. Amber
/// marks what needs attention (low stock, expiring soon).
class _Summary extends StatelessWidget {
  const _Summary({required this.medicine});

  final MedicineModel medicine;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final m = medicine;
    final expiry = m.expiryDate;
    final facts = <(String, String, Color?)>[
      (
        'In stock',
        '${m.currentStock} ${m.unit}',
        m.isLowStock ? c.amberText : null,
      ),
      ('Reorder at', '${m.reorderThreshold} ${m.unit}', null),
      (
        'Expiry',
        expiry == null ? '—' : _day.format(expiry),
        m.isExpiringSoon ? c.amberText : null,
      ),
      if (m.supplierName != null) ('Supplier', m.supplierName!, null),
      if (m.batchNumber != null) ('Batch', m.batchNumber!, null),
      if (m.unitPrice != null) ...[
        ('Unit price', _rupees.format(m.unitPrice!), null),
        ('Stock value', _rupees.format(m.unitPrice! * m.currentStock), null),
      ],
    ];

    return CruCard(
      semanticLabel: 'Item details',
      padding: const EdgeInsets.all(CruSpace.s20),
      child: LayoutBuilder(
        builder: (context, box) {
          final columns = box.maxWidth >= 720
              ? 4
              : box.maxWidth >= 420
              ? 3
              : 2;
          final width = (box.maxWidth - CruSpace.s16 * (columns - 1)) / columns;
          return Wrap(
            spacing: CruSpace.s16,
            runSpacing: CruSpace.s16,
            children: [
              for (final (label, value, color) in facts)
                SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: CruType.subhead.tint(c.label2)),
                      const SizedBox(height: CruSpace.s4),
                      Text(
                        value,
                        style: CruType.headline.tabular.tint(color ?? c.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.history});

  final AsyncValue<List<StockTransactionModel>> history;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'Stock history',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s20,
        CruSpace.s20,
        CruSpace.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Stock history', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s12),
          Expanded(
            child: history.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              error: (e, _) => Center(
                child: Text(
                  "Couldn't load the history: $e",
                  style: CruType.text.tint(c.label2),
                ),
              ),
              data: (rows) => rows.isEmpty
                  ? Center(
                      child: Text(
                        'No stock changes yet. Adjust stock to log one.',
                        style: CruType.text.tint(c.label2),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const CruSeparator(
                        indent: CruSize.attentionTextInset,
                      ),
                      itemBuilder: (_, i) => _HistoryRow(rows[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.t);

  final StockTransactionModel t;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (CruIconData icon, String label, bool adds) = switch (t.type) {
      StockTransactionType.restock => (CruIcons.plus, 'Restocked', true),
      StockTransactionType.dispense => (
        CruIcons.arrowUpRight,
        'Dispensed',
        false,
      ),
      StockTransactionType.adjustment => (
        CruIcons.importExport,
        'Adjusted',
        false,
      ),
      StockTransactionType.expiredWriteoff => (
        CruIcons.warning,
        'Written off (expired)',
        false,
      ),
    };
    final note = t.note;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s10),
      child: Row(
        children: [
          CruIconTile(icon: icon, tone: CruTileTone.neutral),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label ${adds ? '+' : '−'}${t.quantity}',
                  style: CruType.callout.tabular.tint(c.label),
                ),
                if (note != null && note.isNotEmpty)
                  Text(
                    note,
                    style: CruType.subhead.tint(c.label2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${t.resultingStock} left',
                style: CruType.subhead.tabular.tint(c.label),
              ),
              Text(
                _day.format(t.createdAt),
                style: CruType.caption.tabular.tint(c.label3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
