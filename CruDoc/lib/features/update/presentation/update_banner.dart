// lib/features/update/presentation/update_banner.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/update/models/update_check_result.dart';
import 'package:doctor_management_app/features/update/controllers/update_controller.dart';
import 'package:doctor_management_app/features/update/presentation/update_available_dialog.dart';
import 'package:doctor_management_app/features/update/providers/update_providers.dart';

/// Soft, dismissible inline alternative to [UpdateAvailableDialog].
///
/// Mount once near the top of Shell's content — same idea as
/// `InventoryAlertListener`, but this is a plain reactive widget rather
/// than a wrapper, so just place it above whatever it should sit over:
/// ```dart
/// Column(children: [const UpdateBanner(), Expanded(child: ...)])
/// ```
/// Renders nothing when there's no update, the user already dismissed
/// this release with Later/Skip, or the release is a force update — a
/// force update always uses the non-dismissible dialog instead, since a
/// soft banner would defeat the point of "required".
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkResult = ref.watch(updateCheckResultProvider);
    final dismissedForSession =
        ref.watch(updateControllerProvider).dismissedForSession;

    if (checkResult is! UpdateAvailable) return const SizedBox.shrink();

    final release = checkResult.release;
    final forceUpdate = release.manifest?.forceUpdate ?? false;
    if (forceUpdate || dismissedForSession) return const SizedBox.shrink();

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.chartBarLight.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  color: AppColors.chartBarLight,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Update available',
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Version ${release.version} is ready to install.',
                      style: AppColors.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => showUpdateAvailableDialog(context, release),
                child: const Text(
                  'Update',
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontWeight: FontWeight.w600,
                    color: AppColors.chartBarLight,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    size: 18, color: AppColors.textSecondary),
                tooltip: 'Dismiss',
                onPressed: () =>
                    ref.read(updateControllerProvider.notifier).remindLater(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}