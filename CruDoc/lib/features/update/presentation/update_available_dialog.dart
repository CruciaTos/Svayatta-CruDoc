// lib/features/update/presentation/update_available_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/update/models/app_release.dart';
import 'package:doctor_management_app/core/update/models/update_progress.dart';
import 'package:doctor_management_app/features/update/controllers/update_controller.dart';
import 'package:doctor_management_app/features/update/presentation/update_progress_sheet.dart';

/// Opens [UpdateAvailableDialog] for [release].
///
/// Non-dismissible (no tap-outside, no back button) when
/// `release.manifest?.forceUpdate` is true — design principle #5 in the
/// architecture doc: no unattended overwriting, but a clearly-flagged
/// force path for critical fixes is allowed to block the user from
/// continuing on an unpatched version.
Future<void> showUpdateAvailableDialog(
  BuildContext context,
  AppRelease release,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !_isForceUpdate(release),
    builder: (_) => UpdateAvailableDialog(release: release),
  );
}

bool _isForceUpdate(AppRelease release) =>
    release.manifest?.forceUpdate ?? false;

/// Modal shown when [UpdateController] finds a newer release: version,
/// changelog, and Update now / Later / Skip actions. Later and Skip are
/// hidden entirely for a force update — there's nothing to defer.
class UpdateAvailableDialog extends ConsumerWidget {
  const UpdateAvailableDialog({super.key, required this.release});

  final AppRelease release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forceUpdate = _isForceUpdate(release);

    // Guards against reopening this dialog (e.g. from UpdateBanner)
    // while a previous "Update now" tap is still downloading.
    final progress = ref.watch(updateControllerProvider).progress;
    final isBusy =
        progress != null && progress.state != UpdateProgressState.failed;

    return PopScope(
      canPop: !forceUpdate,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppColors.cardSurface,
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.chartBarLight.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.system_update_rounded,
                color: AppColors.chartBarLight,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Update available',
                style: AppColors.sectionHeading.copyWith(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                'Version ${release.version} is ready to install.',
                style: AppColors.bodyLarge,
              ),
              if (forceUpdate) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.priority_high_rounded,
                        size: 16, color: Colors.redAccent),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'This update is required to keep using CruDoc.',
                        style: TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (release.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  "What's new",
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(release.notes, style: AppColors.bodyMedium),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
        actions: [
          if (!forceUpdate)
            TextButton(
              onPressed: isBusy
                  ? null
                  : () {
                      ref
                          .read(updateControllerProvider.notifier)
                          .skipThisVersion();
                      Navigator.pop(context);
                    },
              child: const Text(
                'Skip',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          if (!forceUpdate)
            TextButton(
              onPressed: isBusy
                  ? null
                  : () {
                      ref
                          .read(updateControllerProvider.notifier)
                          .remindLater();
                      Navigator.pop(context);
                    },
              child: const Text(
                'Later',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: AppColors.slateBlue,
                ),
              ),
            ),
          FilledButton(
            onPressed: isBusy
                ? null
                : () {
                    Navigator.pop(context);
                    showUpdateProgressSheet(context, release);
                  },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.chartBarLight,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text(
              'Update now',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}