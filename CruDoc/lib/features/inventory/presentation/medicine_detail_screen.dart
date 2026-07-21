import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/models/stock_transaction_model.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';
import 'package:doctor_management_app/features/inventory/presentation/add_edit_medicine_form.dart';
import 'package:doctor_management_app/features/inventory/presentation/stock_adjustment_dialog.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';

/// Full detail view for a single medicine: current stock, expiry, and the
/// complete transaction history, newest first.
class MedicineDetailScreen extends ConsumerWidget {
  const MedicineDetailScreen({super.key, required this.medicine});

  final MedicineModel medicine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(
      medicineTransactionsProvider(medicine.id),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopBar(
                  title: medicine.name,
                  onEdit: () =>
                      showAddEditMedicineForm(context, medicine: medicine),
                ),
                const SizedBox(height: 16),
                _SummaryCard(medicine: medicine),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Transaction History',
                      style: AppColors.pageHeading.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          showStockAdjustmentDialog(context, medicine: medicine),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.chartBarLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swap_vert, color: Colors.white, size: 18),
                            SizedBox(width: 4),
                            Text(
                              'Adjust',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: transactionsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(
                      child: Text(
                        'Error loading history: $error',
                        style: AppColors.bodyMedium,
                      ),
                    ),
                    data: (transactions) {
                      if (transactions.isEmpty) {
                        return Center(
                          child: Text(
                            'No transactions yet — tap Adjust to log one',
                            style: AppColors.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: EdgeInsets.zero,
                        physics: const ClampingScrollPhysics(),
                        itemCount: transactions.length,
                        itemBuilder: (context, index) =>
                            _TransactionTile(transaction: transactions[index]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onEdit});

  final String title;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.textPrimary,
            size: 20,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
          onPressed: onEdit,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.medicine});

  final MedicineModel medicine;

  @override
  Widget build(BuildContext context) {
    final expiry = medicine.expiryDate;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatColumn(
                  label: 'Current Stock',
                  value: '${medicine.currentStock} ${medicine.unit}',
                  valueColor: medicine.isLowStock
                      ? Colors.redAccent
                      : AppColors.positiveGreen,
                ),
              ),
              Expanded(
                child: _StatColumn(
                  label: 'Reorder At',
                  value: '${medicine.reorderThreshold} ${medicine.unit}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFDDE6F0)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatColumn(
                  label: 'Category',
                  value: medicine.category.isEmpty ? '—' : medicine.category,
                ),
              ),
              Expanded(
                child: _StatColumn(
                  label: 'Expiry',
                  value: expiry == null
                      ? '—'
                      : '${expiry.day}/${expiry.month}/${expiry.year}',
                  valueColor: medicine.isExpiringSoon ? Colors.redAccent : null,
                ),
              ),
            ],
          ),
          if (medicine.supplierName != null || medicine.batchNumber != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFDDE6F0)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _StatColumn(
                    label: 'Supplier',
                    value: medicine.supplierName ?? '—',
                  ),
                ),
                Expanded(
                  child: _StatColumn(
                    label: 'Batch',
                    value: medicine.batchNumber ?? '—',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppColors.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppColors.bodyLarge.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});

  final StockTransactionModel transaction;

  IconData _icon() {
    switch (transaction.type) {
      case StockTransactionType.restock:
        return Icons.add_circle_outline;
      case StockTransactionType.dispense:
        return Icons.remove_circle_outline;
      case StockTransactionType.adjustment:
        return Icons.tune;
      case StockTransactionType.expiredWriteoff:
        return Icons.delete_outline;
    }
  }

  String _label() {
    switch (transaction.type) {
      case StockTransactionType.restock:
        return 'Restocked';
      case StockTransactionType.dispense:
        return 'Dispensed';
      case StockTransactionType.adjustment:
        return 'Adjusted';
      case StockTransactionType.expiredWriteoff:
        return 'Written off (expired)';
    }
  }

  bool get _isIncrease => transaction.type == StockTransactionType.restock;

  @override
  Widget build(BuildContext context) {
    final dt = transaction.createdAt;
    final timeLabel = '${dt.day}/${dt.month}/${dt.year}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(_icon(), color: AppColors.silver, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_label()} • ${_isIncrease ? '+' : '-'}${transaction.quantity}',
                    style: AppColors.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (transaction.note != null && transaction.note!.isNotEmpty)
                    Text(transaction.note!, style: AppColors.bodySmall),
                  Text(
                    'Stock after: ${transaction.resultingStock} · $timeLabel',
                    style: AppColors.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
