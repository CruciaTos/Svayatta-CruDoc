import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/inventory/data/providers/inventory_providers.dart';

/// Dismissible low-stock / expiring-soon alert banner shown at the top of
/// the Dashboard, in the same rounded-card surface language as the other
/// dashboard cards.
///
/// Purely presentational — dismissing it just hides the banner for this
/// session; it reappears next launch as long as the underlying counts are
/// still non-zero. The actual "don't alert twice" dedup for the reactive
/// snackbar/badge lives in [InventoryAlertListener] via
/// `lowStockNotifiedAt` / `expiryNotifiedAt`.
class LowStockBanner extends ConsumerStatefulWidget {
  const LowStockBanner({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  ConsumerState<LowStockBanner> createState() => _LowStockBannerState();
}

class _LowStockBannerState extends ConsumerState<LowStockBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final lowStockAsync = ref.watch(lowStockMedicinesProvider);
    final expiringAsync = ref.watch(expiringMedicinesProvider);

    final lowStockCount = lowStockAsync.maybeWhen(
      data: (data) => data.length,
      orElse: () => 0,
    );
    final expiringCount = expiringAsync.maybeWhen(
      data: (data) => data.length,
      orElse: () => 0,
    );
    final total = lowStockCount + expiringCount;

    if (total == 0) return const SizedBox.shrink();

    final parts = <String>[
      if (lowStockCount > 0)
        '$lowStockCount medicine${lowStockCount == 1 ? '' : 's'} low on stock',
      if (expiringCount > 0)
        '$expiringCount expiring soon',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    parts.join(' • '),
                    style: AppColors.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _dismissed = true),
                  child: const Icon(Icons.close, size: 18, color: AppColors.silver),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
