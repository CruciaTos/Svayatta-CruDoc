import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/features/subscription/presentation/feature_upgrade_sheet.dart';

class MobileFeatureDisabledView extends StatelessWidget {
  final String featureTitle;
  final IconData icon;
  final VoidCallback? onBackToDashboard;

  const MobileFeatureDisabledView({
    super.key,
    required this.featureTitle,
    required this.icon,
    this.onBackToDashboard,
  });

  @override
  Widget build(BuildContext context) {
    final subscriptionService = DoctorSubscriptionService();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.cardSurface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.slateBlue.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: StreamBuilder<DoctorSubscriptionInfo>(
            stream: subscriptionService.watchSubscriptionInfo(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              final isExp = info?.isExpired ?? false;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isExp
                              ? Colors.redAccent.withValues(alpha: 0.12)
                              : Colors.amber.withValues(alpha: 0.12),
                          border: Border.all(
                            color: isExp
                                ? Colors.redAccent.withValues(alpha: 0.4)
                                : Colors.amber.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                      ),
                      Icon(
                        icon,
                        size: 38,
                        color: isExp ? Colors.redAccent : Colors.amber.shade700,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isExp ? Colors.redAccent : const Color(0xFF1E78FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '$featureTitle is Locked',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFamily: AppColors.headingFontFamily,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isExp
                        ? 'Your 1-month clinical subscription has expired. Customize your plan and upgrade to unlock $featureTitle and all advanced modules.'
                        : 'This module is not active in your current plan. Tap Upgrade below to select this feature and activate it for your clinic.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.9),
                      fontSize: 13.5,
                      height: 1.45,
                      fontFamily: AppColors.bodyFontFamily,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Upgrade Action Button
                  if (info != null)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => FeatureUpgradeSheet.show(
                          context,
                          subscriptionInfo: info,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E78FF),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.workspace_premium_rounded, size: 19),
                        label: const Text(
                          'Upgrade & Unlock Feature',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                  if (onBackToDashboard != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton.icon(
                        onPressed: onBackToDashboard,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.slateBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.dashboard_rounded, size: 16),
                        label: const Text(
                          'Back to Dashboard',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
