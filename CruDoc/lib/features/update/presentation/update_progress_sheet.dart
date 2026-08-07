// lib/features/update/presentation/update_progress_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/update/models/app_release.dart';
import 'package:doctor_management_app/core/update/models/update_progress.dart';
import 'package:doctor_management_app/features/update/controllers/update_controller.dart';
import 'package:doctor_management_app/features/update/providers/update_providers.dart';

/// Opens [UpdateProgressSheet] and starts downloading + installing
/// [release]. This is the only call site for `UpdateController.startUpdate`
/// — [UpdateAvailableDialog]'s "Update now" button opens this sheet
/// rather than starting the download itself.
Future<void> showUpdateProgressSheet(
  BuildContext context,
  AppRelease release,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    backgroundColor: AppColors.cardSurface,
    builder: (_) => UpdateProgressSheet(release: release),
  );
}

/// Download/verify/install progress UI shown after "Update now". Watches
/// [updateProgressProvider] and re-renders as `startUpdate`'s stream
/// comes in; offers a Retry button on [UpdateProgressState.failed].
class UpdateProgressSheet extends ConsumerStatefulWidget {
  const UpdateProgressSheet({super.key, required this.release});

  final AppRelease release;

  @override
  ConsumerState<UpdateProgressSheet> createState() =>
      _UpdateProgressSheetState();
}

class _UpdateProgressSheetState extends ConsumerState<UpdateProgressSheet> {
  @override
  void initState() {
    super.initState();
    ref.read(updateControllerProvider.notifier).startUpdate(widget.release);
  }

  void _retry() {
    ref.read(updateControllerProvider.notifier).startUpdate(widget.release);
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(updateProgressProvider);
    final state = progress?.state ?? UpdateProgressState.idle;
    final canDismiss = state == UpdateProgressState.failed ||
        state == UpdateProgressState.idle;

    return PopScope(
      canPop: canDismiss,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Version ${widget.release.version}',
                  style: AppColors.sectionHeading.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(_labelFor(state), style: AppColors.bodyMedium),
                const SizedBox(height: 20),
                switch (state) {
                  UpdateProgressState.downloading =>
                    _DownloadingBody(progress: progress),
                  UpdateProgressState.verifying =>
                    const _SpinnerRow(label: 'Verifying download…'),
                  UpdateProgressState.readyToInstall =>
                    const _SpinnerRow(label: 'Ready to install…'),
                  UpdateProgressState.installing =>
                    const _SpinnerRow(label: 'Installing…'),
                  UpdateProgressState.failed => _FailedBody(onRetry: _retry),
                  UpdateProgressState.idle =>
                    const _SpinnerRow(label: 'Starting download…'),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _labelFor(UpdateProgressState state) => switch (state) {
        UpdateProgressState.idle => 'Preparing…',
        UpdateProgressState.downloading => 'Downloading update',
        UpdateProgressState.verifying => 'Verifying integrity',
        UpdateProgressState.readyToInstall => 'Ready to install',
        UpdateProgressState.installing => 'Installing',
        UpdateProgressState.failed => 'Update failed',
      };
}

class _DownloadingBody extends StatelessWidget {
  const _DownloadingBody({required this.progress});

  final UpdateProgress? progress;

  @override
  Widget build(BuildContext context) {
    final downloaded = progress?.bytesDownloaded ?? 0;
    final total = progress?.totalBytes ?? 0;
    final percent = _clamp01(progress?.percent ?? 0.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: total > 0 ? percent : null,
            minHeight: 8,
            backgroundColor: AppColors.divider,
            valueColor: const AlwaysStoppedAnimation(AppColors.chartBarLight),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          total > 0
              ? '${_formatBytes(downloaded)} of ${_formatBytes(total)} · '
                  '${(percent * 100).toStringAsFixed(0)}%'
              : _formatBytes(downloaded),
          style: AppColors.bodySmall,
        ),
      ],
    );
  }
}

class _SpinnerRow extends StatelessWidget {
  const _SpinnerRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.chartBarLight,
          ),
        ),
        const SizedBox(width: 12),
        Text(label, style: AppColors.bodyMedium),
      ],
    );
  }
}

class _FailedBody extends StatelessWidget {
  const _FailedBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Something went wrong. You can try again, or check for '
                'updates later from Profile.',
                style: AppColors.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.chartBarLight,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

/// Simplified for installer-sized downloads (tens of MB) — no KB/GB
/// branching needed.
String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  const mb = 1024 * 1024;
  return '${(bytes / mb).toStringAsFixed(1)} MB';
}

/// `num.clamp` returns `num`, not `double` — this avoids the implicit
/// downcast that would otherwise fail analysis.
double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);