import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/files/lan/lan_client.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Notifier tracking active LAN file transfers in the app.
class ActiveTransfersNotifier extends Notifier<Map<String, TransferProgress>> {
  @override
  Map<String, TransferProgress> build() => const {};

  void updateProgress(TransferProgress p) {
    if (p.isDone || p.error != null) {
      final updated = Map<String, TransferProgress>.from(state)
        ..remove(p.offerId);
      state = updated;
    } else {
      final updated = Map<String, TransferProgress>.from(state)
        ..[p.offerId] = p;
      state = updated;
    }
  }

  void cancel(String offerId) {
    LanClient.instance.cancelTransfer(offerId);
    final updated = Map<String, TransferProgress>.from(state)..remove(offerId);
    state = updated;
  }
}

final activeTransfersProvider =
    NotifierProvider<ActiveTransfersNotifier, Map<String, TransferProgress>>(
      ActiveTransfersNotifier.new,
    );

/// A tray at the bottom of the Files screen showing real-time LAN transfer progress (Task N6).
class TransferProgressTray extends ConsumerWidget {
  const TransferProgressTray({super.key});

  static String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    final mb = bytesPerSec / (1024 * 1024);
    if (mb >= 1.0) return '${mb.toStringAsFixed(1)} MB/s';
    final kb = bytesPerSec / 1024;
    return '${kb.toStringAsFixed(0)} KB/s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final active = ref.watch(activeTransfersProvider);
    if (active.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: CruSpace.s16,
      left: CruSpace.s20,
      right: CruSpace.s20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in active.entries)
            _buildTransferItem(context, ref, entry.value, c),
        ],
      ),
    );
  }

  Widget _buildTransferItem(
    BuildContext context,
    WidgetRef ref,
    TransferProgress p,
    CruColors c,
  ) {
    final speed = _formatSpeed(p.bytesPerSecond);

    return Container(
      margin: const EdgeInsets.only(top: CruSpace.s8),
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s12,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.accent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_tethering, color: c.accent, size: 24),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.fileName,
                        style: CruType.body.w600.tint(c.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: CruSpace.s8),
                    Text(
                      '${p.percent}% ${speed.isNotEmpty ? '· $speed' : ''}',
                      style: CruType.caption.tint(c.label2),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: p.fraction,
                    backgroundColor: c.accentWash,
                    color: c.accent,
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Cancel',
            onPressed: () =>
                ref.read(activeTransfersProvider.notifier).cancel(p.offerId),
          ),
        ],
      ),
    );
  }
}
