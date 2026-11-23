import 'package:flutter/foundation.dart';

/// Whether the hosted service offers an in-app purchase to the active account
/// right now ([inAppPurchasesOffered], upgrade_route.dart), for the screens
/// that decide whether to show a way to buy at all.
///
/// [PurchaseDelivery] owns the one instance (store-billing builds only) and
/// sets it from the hosted config it already asks once per signed-in user and
/// active company (`GET kIapConfigPath`). It reads false until an answer for
/// the current user and company says yes, so a server without the route (a
/// 404), an error or no network all leave purchases off: fails closed.
///
/// Provided at the app root (`main.dart`) and read as `PurchaseOffer?`
/// through `purchasesWithheld` (upgrade_launcher.dart), so a screen and its
/// tests work without one (docs/in-app-purchases.md).
class PurchaseOffer extends ChangeNotifier {
  bool _offered = false;

  /// True only once the hosted config has said purchases are on for the
  /// active account.
  bool get offered => _offered;

  /// Set by [PurchaseDelivery]; notifies only on a change.
  void update(bool offered) {
    if (_offered == offered) return;
    _offered = offered;
    notifyListeners();
  }
}
