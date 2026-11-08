import 'package:doctor_management_app/core/utils/app_notice.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/callable_client.dart';
import 'package:doctor_management_app/core/widgets/legal_links_row.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/subscription/data/apple_iap_service.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The Apple Store purchase list for iPhone, iPad, and Mac.
/// Replaces the UPI checkout on Apple platforms per App Review 3.1.1.
class AppleCheckoutList extends ConsumerStatefulWidget {
  const AppleCheckoutList({super.key});

  @override
  ConsumerState<AppleCheckoutList> createState() => _AppleCheckoutListState();
}

class _AppleCheckoutListState extends ConsumerState<AppleCheckoutList> {
  final DoctorSubscriptionService _subscriptionService =
      DoctorSubscriptionService();
  late final AppleIapService _iapService;

  Map<String, ProductDetails> _products = {};
  bool _loading = true;
  String? _purchasingProductId;

  @override
  void initState() {
    super.initState();
    _iapService = AppleIapService(verify: _verifyApplePurchase);
    _iapService.listen(_onPurchaseResult);
    _loadProducts();
  }

  @override
  void dispose() {
    _iapService.dispose();
    super.dispose();
  }

  Future<void> _verifyApplePurchase(PurchaseDetails purchase) async {
    await CallableClient().call('verifyApplePurchase', {
      'productId': purchase.productID,
      'transactionId': purchase.purchaseID ?? '',
      'receipt': purchase.verificationData.serverVerificationData,
    });
  }

  void _onPurchaseResult(PurchaseDetails purchase, String? error) {
    if (!mounted) return;
    setState(() => _purchasingProductId = null);
    if (error != null) {
      ScaffoldMessenger.of(context).showIsland(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    } else {
      ref.invalidate(doctorEnabledModulesStreamProvider);
      ref.invalidate(clinicAccessProvider);
      ScaffoldMessenger.of(context).showIsland(
        const SnackBar(
          content: Text('Plan updated'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    try {
      final prods = await _iapService.products();
      if (mounted) {
        setState(() {
          _products = prods;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _buy(ProductDetails product) async {
    setState(() => _purchasingProductId = product.id);
    try {
      await _iapService.buy(product);
    } catch (e) {
      if (mounted) {
        setState(() => _purchasingProductId = null);
        ScaffoldMessenger.of(context).showIsland(
          SnackBar(
            content: Text('Could not start purchase: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _restore() async {
    try {
      await _iapService.restore();
      if (mounted) {
        ScaffoldMessenger.of(context).showIsland(
          const SnackBar(
            content: Text('Restoring purchases…'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showIsland(
          SnackBar(
            content: Text('Could not restore purchases: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _manageSubscriptions() async {
    final uri = Uri.parse('https://apps.apple.com/account/subscriptions');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(CruSpace.s32),
        child: Center(
          child: SizedBox.square(
            dimension: CruSpace.s24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(CruSpace.s32),
        child: Center(
          child: Text(
            "Purchases aren't available right now.",
            style: CruType.text.tint(c.label2),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return StreamBuilder<DoctorSubscriptionInfo>(
      stream: _subscriptionService.watchSubscriptionInfo(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final availableCatalogItems = [
          for (final item in featureCatalog)
            if (!item.isBaseModule && _products.containsKey(item.moduleKey))
              item,
        ];

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CruCard(
                padding: const EdgeInsets.all(CruSpace.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Available Modules',
                      style: CruType.title2.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s4),
                    Text(
                      'Subscribe to unlock additional capabilities for your clinic.',
                      style: CruType.caption.tint(c.label2),
                    ),
                    const SizedBox(height: CruSpace.s16),
                    for (var i = 0; i < availableCatalogItems.length; i++) ...[
                      if (i > 0) ...[
                        const SizedBox(height: CruSpace.s12),
                        const CruSeparator(),
                        const SizedBox(height: CruSpace.s12),
                      ],
                      _buildModuleRow(
                        c,
                        availableCatalogItems[i],
                        _products[availableCatalogItems[i].moduleKey]!,
                        info?.isModuleUnlocked(
                              availableCatalogItems[i].moduleKey,
                            ) ??
                            false,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: CruSpace.s20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _restore,
                    child: Text(
                      'Restore purchases',
                      style: CruType.caption.tint(c.accentText),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s16),
                  TextButton(
                    onPressed: _manageSubscriptions,
                    child: Text(
                      'Manage subscriptions',
                      style: CruType.caption.tint(c.accentText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
                child: Text(
                  'Subscriptions renew every month until you cancel. Cancel at least '
                  '24 hours before the end of the period in your Apple ID settings. '
                  'Payment is charged to your Apple ID.',
                  textAlign: TextAlign.center,
                  style: CruType.caption.tint(c.label3),
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              const Center(child: LegalLinksRow()),
              const SizedBox(height: CruSpace.s24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModuleRow(
    CruColors c,
    FeaturePricingItem item,
    ProductDetails product,
    bool isUnlocked,
  ) {
    final inFlight = _purchasingProductId == product.id;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: CruType.callout.w600.tint(c.label)),
              const SizedBox(height: CruSpace.s2),
              Text(
                item.description,
                style: CruType.caption.tint(c.label2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: CruSpace.s12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${product.price} / mo',
              style: CruType.callout.w600.tabular.tint(c.label),
            ),
            const SizedBox(height: CruSpace.s4),
            if (isUnlocked)
              CruPill(
                text: 'Active',
                icon: CruIcons.check,
                background: c.greenTint,
                foreground: c.greenText,
              )
            else if (inFlight)
              SizedBox.square(
                dimension: CruSpace.s20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.accent,
                ),
              )
            else
              CruButton(
                label: 'Buy',
                kind: CruButtonKind.inset,
                onPressed: _purchasingProductId != null
                    ? null
                    : () => _buy(product),
              ),
          ],
        ),
      ],
    );
  }
}
