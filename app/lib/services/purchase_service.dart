import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config.dart';

/// غلاف بسيط حول RevenueCat. معرّف المستخدم عندهم = معرّف المستخدم في خادمنا،
/// فيعرف الخادم من اشترى عبر Webhook.
class PurchaseService {
  static bool get enabled => AppConfig.revenueCatKey.isNotEmpty;
  static bool _configured = false;

  static Future<void> init(int userId) async {
    if (!enabled) return;
    final id = userId.toString();
    if (!_configured) {
      await Purchases.configure(
          PurchasesConfiguration(AppConfig.revenueCatKey)..appUserID = id);
      _configured = true;
    } else {
      await Purchases.logIn(id);
    }
  }

  static Future<List<Package>> packages() async {
    final offerings = await Purchases.getOfferings();
    return offerings.current?.availablePackages ?? [];
  }

  /// يعيد true عند نجاح الشراء، وfalse إن ألغى المستخدم. غير ذلك يرمي خطأ.
  static Future<bool> buy(Package package) async {
    try {
      await Purchases.purchasePackage(package);
      return true;
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      rethrow;
    }
  }

  static Future<void> restore() async {
    await Purchases.restorePurchases();
  }

  static Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
  }
}
