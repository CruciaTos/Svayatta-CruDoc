import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/providers/storage_sync_providers.dart';
import 'package:doctor_management_app/core/services/storage_sync_queue.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One quiet line in the sidebar saying how many files are waiting to reach
/// the cloud, or that some need attention. Shows nothing when all is synced.
class SyncStatusLine extends ConsumerWidget {
  const SyncStatusLine({super.key, required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingUploadCountProvider).value ?? 0;
    final failed = ref.watch(failedUploadCountProvider).value ?? 0;
    if (pending == 0 && failed == 0) return const SizedBox.shrink();

    final c = context.cru;
    final needsAttention = failed > 0;
    final text = needsAttention
        ? '$failed ${failed == 1 ? 'file' : 'files'} failed to sync'
        : '$pending ${pending == 1 ? 'file' : 'files'} waiting to sync';
    final tip = needsAttention ? '$text — tap for details' : text;
    final color = needsAttention ? c.amberText : c.label2;

    return Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s8),
      child: CruPressable(
        onTap: needsAttention ? () => showSyncIssuesDialog(context) : null,
        semanticLabel: tip,
        tooltip: collapsed ? tip : null,
        builder: (context, hovered) => Container(
          height: CruSize.collapsedRow - CruSpace.s8,
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : CruSpace.s10,
          ),
          alignment: collapsed ? Alignment.center : Alignment.centerLeft,
          decoration: ShapeDecoration(
            color: hovered ? c.hoverFill : Colors.transparent,
            shape: cruShape(CruRadius.control),
          ),
          child: Row(
            mainAxisSize: collapsed ? MainAxisSize.min : MainAxisSize.max,
            children: [
              CruStatusDot(
                needsAttention ? CruDotKind.waiting : CruDotKind.now,
                size: CruSize.smallDot + 2,
              ),
              if (!collapsed) ...[
                const SizedBox(width: CruSpace.s10),
                Expanded(
                  child: Text(
                    needsAttention ? tip : text,
                    style: CruType.caption.tabular.tint(color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Lists the files that could not be uploaded, with the reason, and lets
/// the doctor retry or discard each one.
Future<void> showSyncIssuesDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _SyncIssuesDialog(),
);

class _SyncIssuesDialog extends ConsumerWidget {
  const _SyncIssuesDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final items = ref.watch(failedUploadsProvider);

    return Dialog(
      backgroundColor: c.surface,
      shape: cruShape(CruRadius.card),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sync issues',
                      style: CruType.title2.tint(c.label),
                    ),
                  ),
                  CruIconButton(
                    icon: CruIcons.close,
                    semanticLabel: 'Close',
                    size: CruSize.squareButton,
                    iconSize: 16,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                'These files are saved on this computer but could not be '
                'copied to the cloud.',
                style: CruType.subhead.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s16),
              Flexible(
                child: items.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(CruSpace.s24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text(
                    'Could not load the list.',
                    style: CruType.subhead.tint(c.label2),
                  ),
                  data: (list) => list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(CruSpace.s16),
                          child: Text(
                            'Nothing needs attention.',
                            style: CruType.subhead.tint(c.label2),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: CruSpace.s8),
                          itemBuilder: (_, i) => _IssueRow(item: list[i]),
                        ),
                ),
              ),
              if ((items.value?.length ?? 0) > 1) ...[
                const SizedBox(height: CruSpace.s16),
                Align(
                  alignment: Alignment.centerRight,
                  child: CruButton(
                    label: 'Retry all',
                    onPressed: () async {
                      await StorageSyncQueue.instance.retryAllFailed();
                      ref.invalidate(failedUploadsProvider);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IssueRow extends ConsumerWidget {
  const _IssueRow({required this.item});

  final PendingUpload item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.all(CruSpace.s12),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${uploadKindLabel(item.kind)} · '
                  '${DateFormat('d MMM, h:mm a').format(item.createdAt)}',
                  style: CruType.subhead.w600.tabular.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  item.lastError ?? 'Could not be uploaded.',
                  style: CruType.caption.tint(c.label2),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruCapsuleButton(
            label: 'Retry',
            onPressed: () async {
              await StorageSyncQueue.instance.retry(item.id);
              ref.invalidate(failedUploadsProvider);
            },
          ),
          const SizedBox(width: CruSpace.s6),
          CruCapsuleButton(
            label: 'Discard',
            onPressed: () async {
              await StorageSyncQueue.instance.cancel(item.id);
              ref.invalidate(failedUploadsProvider);
            },
          ),
        ],
      ),
    );
  }
}

/// Plain-language name for a kind, for lists shown to the doctor.
String uploadKindLabel(UploadKind kind) => switch (kind) {
  UploadKind.patientAvatar => 'Patient photo',
  UploadKind.prescriptionPdf => 'Prescription',
  UploadKind.invoicePdf => 'Invoice',
  UploadKind.treatmentPlanPdf => 'Treatment plan',
  UploadKind.clinicalXray => 'X-ray',
  UploadKind.clinicalPhoto => 'Clinical photo',
  UploadKind.clinicalLab => 'Lab report',
  UploadKind.voiceDictation => 'Voice recording',
  UploadKind.brandingLogo => 'Clinic logo',
  UploadKind.brandingSignature => 'Signature',
  UploadKind.inventoryReceipt => 'Inventory receipt',
  UploadKind.sterilizationStrip => 'Sterilization strip',
  UploadKind.databaseBackup => 'Cloud backup',
  UploadKind.revenueCsv => 'Revenue export',
};
