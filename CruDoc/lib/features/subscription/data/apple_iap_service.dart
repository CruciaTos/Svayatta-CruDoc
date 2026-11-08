import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:crudoc_shared/subscription/feature_catalog.dart';

/// The product id Apple sells a module under.
String appleProductId(String moduleKey) => 'com.crudoc.app.$moduleKey.monthly';

class AppleIapService {
  AppleIapService({InAppPurchase? store, required this.verify})
    : _store = store ?? InAppPurchase.instance;

  final InAppPurchase _store;

  /// Sends a purchase to the server (the `verifyApplePurchase` callable).
  /// Throws if the server refuses.
  final Future<void> Function(PurchaseDetails purchase) verify;

  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Apple's products for every paid module, by module key.
  Future<Map<String, ProductDetails>> products() async {
    if (!await _store.isAvailable()) return const {};
    final paid = [
      for (final f in featureCatalog)
        if (!f.isBaseModule) f.moduleKey,
    ];
    final response = await _store.queryProductDetails({
      for (final k in paid) appleProductId(k),
    });
    return {
      for (final p in response.productDetails)
        for (final k in paid)
          if (p.id == appleProductId(k)) k: p,
    };
  }

  /// Starts listening for purchase updates (call once, before any buy or
  /// restore). [onResult] gets (purchase, errorMessage?) per update.
  void listen(void Function(PurchaseDetails, String?) onResult) {
    _sub ??= _store.purchaseStream.listen((list) async {
      for (final p in list) {
        if (p.status == PurchaseStatus.pending) continue;
        if (p.status == PurchaseStatus.error ||
            p.status == PurchaseStatus.canceled) {
          if (p.pendingCompletePurchase) await _store.completePurchase(p);
          onResult(
            p,
            p.status == PurchaseStatus.canceled ? null : p.error?.message,
          );
          continue;
        }
        // purchased or restored: the server must agree before we finish it.
        try {
          await verify(p);
          if (p.pendingCompletePurchase) await _store.completePurchase(p);
          onResult(p, null);
        } catch (e) {
          onResult(p, '$e');
        }
      }
    });
  }

  Future<void> buy(ProductDetails product) => _store.buyNonConsumable(
    purchaseParam: PurchaseParam(productDetails: product),
  );

  Future<void> restore() => _store.restorePurchases();

  void dispose() => _sub?.cancel();
}
