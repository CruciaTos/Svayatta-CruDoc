import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/features/subscription/presentation/feature_upgrade_sheet.dart';

/// Interactive banner on the Doctor Dashboard showing real-time plan status,
/// expiry countdown, and one-tap access to the Feature Upgrade Sheet.
class SubscriptionStatusBanner extends StatelessWidget {
  const SubscriptionStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final subscriptionService = DoctorSubscriptionService();

    return StreamBuilder<DoctorSubscriptionInfo>(
      stream: subscriptionService.watchSubscriptionInfo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final info = snapshot.data!;
        final isExp = info.isExpired;
        final days = info.daysRemaining;
        final isExpiringSoon = !isExp && days != null && days <= 5;

        // Normal state when > 5 days left — clean subtle pill
        if (!isExp && !isExpiringSoon) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF0F7FF), Color(0xFFE8F1FD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  color: Color(0xFF1E78FF),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    days != null
                        ? '${info.planName.toUpperCase()} PLAN • $days days remaining'
                        : '${info.planName.toUpperCase()} PLAN • Active',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E40AF),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => FeatureUpgradeSheet.show(
                    context,
                    subscriptionInfo: info,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E78FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.upgrade_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Upgrade',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Expired or Expiring Soon — High Priority Alert
        final bgColor = isExp ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB);
        final borderColor = isExp ? const Color(0xFFF87171) : const Color(0xFFFBBF24);
        final textColor = isExp ? const Color(0xFF991B1B) : const Color(0xFF92400E);
        final btnColor = isExp ? const Color(0xFFDC2626) : const Color(0xFFD97706);

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: btnColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isExp ? Icons.lock_clock_rounded : Icons.warning_amber_rounded,
                  color: btnColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isExp ? 'Plan Expired — Features Locked' : 'Plan Expiring Soon',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                        fontFamily: AppColors.headingFontFamily,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isExp
                          ? 'Add-on modules are locked. Tap Upgrade to pick your features.'
                          : 'Your plan expires in ${days ?? 0} day${(days ?? 0) == 1 ? '' : 's'}. Renew to keep access.',
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => FeatureUpgradeSheet.show(
                  context,
                  subscriptionInfo: info,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: btnColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  isExp ? 'Upgrade' : 'Renew',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
