import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/features/subscription/data/upgrade_request_model.dart';
import 'package:doctor_management_app/features/subscription/presentation/payment_checkout_sheet.dart';

/// Modal bottom sheet that lets doctors view available features,
/// calculate monthly totals, and submit an upgrade request.
class FeatureUpgradeSheet extends StatefulWidget {
  final DoctorSubscriptionInfo subscriptionInfo;

  const FeatureUpgradeSheet({
    super.key,
    required this.subscriptionInfo,
  });

  static Future<void> show(
    BuildContext context, {
    required DoctorSubscriptionInfo subscriptionInfo,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeatureUpgradeSheet(subscriptionInfo: subscriptionInfo),
    );
  }

  @override
  State<FeatureUpgradeSheet> createState() => _FeatureUpgradeSheetState();
}

class _FeatureUpgradeSheetState extends State<FeatureUpgradeSheet> {
  final DoctorSubscriptionService _subscriptionService =
      DoctorSubscriptionService();
  final Set<String> _selectedModuleKeys = {};
  bool _isSubmitting = false;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    // Pre-select modules that are currently enabled
    for (final item in DoctorSubscriptionService.availableFeatures) {
      if (item.isBaseModule ||
          widget.subscriptionInfo.enabledModules.contains(item.moduleKey)) {
        _selectedModuleKeys.add(item.moduleKey);
      }
    }
  }

  double get _calculatedTotal {
    double total = 0;
    for (final item in DoctorSubscriptionService.availableFeatures) {
      if (_selectedModuleKeys.contains(item.moduleKey)) {
        total += item.monthlyPriceInr;
      }
    }
    return total;
  }

  IconData _getIconForName(String name) {
    switch (name) {
      case 'dashboard':
        return Icons.grid_view_rounded;
      case 'groups':
        return Icons.groups_rounded;
      case 'calendar':
        return Icons.calendar_today_rounded;
      case 'inventory':
        return Icons.inventory_2_rounded;
      case 'payments':
        return Icons.payments_rounded;
      case 'home':
        return Icons.home_work_rounded;
      case 'chat':
        return Icons.mark_chat_unread_rounded;
      case 'smart_toy':
        return Icons.smart_toy_rounded;
      case 'phone':
        return Icons.phone_in_talk_rounded;
      case 'devices':
        return Icons.devices_rounded;
      default:
        return Icons.stars_rounded;
    }
  }

  Future<void> _launchPaymentCheckout() async {
    if (_selectedModuleKeys.isEmpty) return;

    final selectedList = _selectedModuleKeys.toList();
    final result = await PaymentCheckoutSheet.show(
      context,
      selectedModules: selectedList,
      totalAmount: _calculatedTotal,
    );

    if (result == true && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '🎉 Selected clinical features unlocked and active for 30 days!',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _submitRequest() async {
    if (_selectedModuleKeys.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final selectedList = _selectedModuleKeys.toList();
      await _subscriptionService.submitUpgradeRequest(
        requestedModules: selectedList,
        totalMonthlyPrice: _calculatedTotal,
        currentPlan: widget.subscriptionInfo.planName,
      );

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _successMessage =
              'Upgrade request submitted successfully! Please complete offline payment via UPI/Bank Transfer. Super Admin will verify and activate your modules.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E78FF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Color(0xFF1E78FF),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Customize & Upgrade Plan',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFamily: AppColors.headingFontFamily,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select modules you need for your clinical practice',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Content body
          Expanded(
            child: _successMessage != null
                ? _buildSuccessView()
                : StreamBuilder<List<UpgradeRequest>>(
                    stream: _subscriptionService.watchMyUpgradeRequests(),
                    builder: (context, snapshot) {
                      final requests = snapshot.data ?? [];
                      final pendingRequest = requests.cast<UpgradeRequest?>().firstWhere(
                            (r) => r?.status == UpgradeRequestStatus.pending,
                            orElse: () => null,
                          );

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                        children: [
                          if (pendingRequest != null)
                            _buildPendingRequestBanner(pendingRequest, currencyFormatter),

                          _buildCurrentPlanCard(),
                          const SizedBox(height: 18),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'AVAILABLE CLINICAL MODULES',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                  color: AppColors.slateBlue,
                                ),
                              ),
                              Text(
                                '${_selectedModuleKeys.length} Selected',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E78FF),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          ...DoctorSubscriptionService.availableFeatures.map(
                            (item) => _buildModuleCard(item, currencyFormatter),
                          ),

                          const SizedBox(height: 16),
                          _buildOfflinePaymentInfoCard(),
                        ],
                      );
                    },
                  ),
          ),

          // Bottom Bar with Subtotal & Submit
          if (_successMessage == null)
            _buildBottomBar(currencyFormatter),
        ],
      ),
    );
  }

  Widget _buildCurrentPlanCard() {
    final info = widget.subscriptionInfo;
    final isExp = info.isExpired;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isExp
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExp
              ? const Color(0xFFFCA5A5)
              : const Color(0xFF86EFAC),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isExp ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: isExp ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Plan: ${info.planName.toUpperCase()} (${isExp ? 'EXPIRED' : 'ACTIVE'})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isExp ? const Color(0xFF991B1B) : const Color(0xFF166534),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.expiresDate != null
                      ? (isExp
                          ? 'Expired on ${DateFormat('dd MMM yyyy').format(info.expiresDate!)}'
                          : 'Valid until ${DateFormat('dd MMM yyyy').format(info.expiresDate!)} (${info.daysRemaining ?? 0} days remaining)')
                      : 'Standard account configuration',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isExp ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRequestBanner(
    UpgradeRequest request,
    NumberFormat currencyFormatter,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.hourglass_top_rounded,
            color: Color(0xFFD97706),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pending Upgrade Request',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Submitted for ${currencyFormatter.format(request.totalMonthlyPrice)}/mo (${request.requestedModules.length} features). Awaiting Super Admin activation.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleCard(
    FeaturePricingItem item,
    NumberFormat currencyFormatter,
  ) {
    final isSelected = _selectedModuleKeys.contains(item.moduleKey);
    final isBase = item.isBaseModule;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0F7FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF1E78FF)
              : const Color(0xFFE2E8F0),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isBase
            ? null
            : () {
                setState(() {
                  if (isSelected) {
                    _selectedModuleKeys.remove(item.moduleKey);
                  } else {
                    _selectedModuleKeys.add(item.moduleKey);
                  }
                });
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF1E78FF)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getIconForName(item.iconName),
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (isBase) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ALWAYS FREE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.description,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isBase
                        ? 'Included'
                        : '${currencyFormatter.format(item.monthlyPriceInr)}/mo',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isBase
                          ? const Color(0xFF16A34A)
                          : (isSelected
                              ? const Color(0xFF1E78FF)
                              : AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Checkbox(
                    value: isBase ? true : isSelected,
                    onChanged: isBase
                        ? null
                        : (val) {
                            setState(() {
                              if (val == true) {
                                _selectedModuleKeys.add(item.moduleKey);
                              } else {
                                _selectedModuleKeys.remove(item.moduleKey);
                              }
                            });
                          },
                    activeColor: const Color(0xFF1E78FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflinePaymentInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF64748B)),
              SizedBox(width: 8),
              Text(
                'How Activation Works',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '1. Select desired modules and tap "Submit Upgrade Request".\n'
            '2. Complete the payment offline via UPI (PhonePe / GPay / Paytm) or Bank Transfer.\n'
            '3. Super Admin verifies payment and unlocks the selected modules in real time for 1 month.',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(NumberFormat currencyFormatter) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'MONTHLY TOTAL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: AppColors.slateBlue,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  currencyFormatter.format(_calculatedTotal),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E78FF),
                    fontFamily: AppColors.headingFontFamily,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 18),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _selectedModuleKeys.isEmpty
                      ? null
                      : _launchPaymentCheckout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 20),
                  label: Text(
                    'Pay & Activate Features (${_selectedModuleKeys.length})',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF16A34A),
              size: 44,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Request Submitted!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFamily: AppColors.headingFontFamily,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _successMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF64748B),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E78FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
