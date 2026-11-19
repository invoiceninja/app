import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/data/models/api/json_coercion.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/api_client.dart';
import 'package:admin/data/services/api_exception.dart';

/// This app's bundle id on the App Store and its package name on Play — the
/// hosted endpoint checks the store-verified transaction against it.
const String kStoreBundleId = 'com.invoiceninja.admin';

/// What happened to a store purchase, as the purchase sheet and the
/// app-wide notices act on it.
enum PurchaseActivityKind {
  /// Waiting on the store: Ask to Buy, a slow card, a Play pending payment.
  pending,

  /// The store refused or failed the purchase; nothing was charged.
  failed,

  /// The user closed the store's sheet.
  canceled,

  /// Paid; being posted to the hosted service.
  delivering,

  /// The hosted service applied it (200), and it was finished with the store.
  applied,

  /// The hosted service refused it for good (403, 409, 422): a sandbox
  /// purchase, one already linked to another account, or one it could not
  /// verify. [PurchaseActivity.message] is the server's own explanation.
  rejected,

  /// Not applied yet — the server or the network failed, or no signed-in
  /// hosted account to apply it to. Left unfinished, so the store hands it
  /// back on the next launch.
  retryLater,
}

/// One update from [PurchaseDelivery.activity].
@immutable
class PurchaseActivity {
  const PurchaseActivity(this.kind, {required this.productId, this.message});

  final PurchaseActivityKind kind;
  final String productId;

  /// The server's message for [PurchaseActivityKind.rejected] (it already
  /// says the `reason` — sandbox, linked, unverified — in words), the store's
  /// error for [PurchaseActivityKind.failed]. Never a translation key.
  final String? message;

  @override
  String toString() => 'PurchaseActivity($kind, $productId)';
}

/// Which store a purchase was made in, as `POST /api/admin/subscription`
/// names it (`source`).
enum PurchaseStore {
  appStore('app_store'),
  googlePlay('google_play');

  const PurchaseStore(this.wireName);

  final String wireName;

  static PurchaseStore of(TargetPlatform platform) =>
      platform == TargetPlatform.android ? googlePlay : appStore;
}

/// Delivers paid App Store / Play purchases to the hosted service, for the
/// app's whole lifetime. Owned by `Services` and built only on a store-billing
/// build (`isStoreBillingBuild`): `InAppPurchase.instance.purchaseStream`
/// throws on web, Windows and Linux, so nothing else may touch it.
///
/// Listening starts the first time a hosted, signed-in session with an
/// account key exists, and never stops. That is what StoreKit needs to hand
/// over `Transaction.updates` — renewals, an Ask to Buy approved later, a
/// purchase interrupted by a crash — and each time such a session appears
/// (sign-in, a switch to a company of another account) the purchases the
/// stores still hold unfinished are swept and delivered too: Play's
/// unacknowledged ones, and StoreKit's `Transaction.unfinished`.
///
/// The upgrade sheet only lists products and starts a purchase; every
/// delivery comes through here, and the sheet follows [activity].
///
/// Response contract (`POST /api/admin/subscription`):
///  * 200 — applied: finish it with the store, then `auth.refresh()`.
///  * 403 / 409 / 422 — refused for good (wrong account, sandbox, already
///    linked, unverifiable). Finished on Apple, so StoreKit stops handing it
///    back; left unacknowledged on Google, so Play refunds it.
///  * anything else (5xx, no network, a 404 from a server without the route)
///    — left unfinished, and delivered again on the next launch.
class PurchaseDelivery {
  PurchaseDelivery({
    required ApiClient apiClient,
    required AuthRepository auth,
    StoreBilling? billing,
    TargetPlatform? platform,
  }) : _apiClient = apiClient,
       _auth = auth,
       billing = billing ?? StoreBilling(),
       _platform = platform ?? defaultTargetPlatform;

  final ApiClient _apiClient;
  final AuthRepository _auth;
  final TargetPlatform _platform;
  final _log = Logger('PurchaseDelivery');

  /// The store SDK. The purchase sheet uses the same instance to list
  /// products and start a purchase.
  final StoreBilling billing;

  PurchaseStore get store => PurchaseStore.of(_platform);

  final _activity = StreamController<PurchaseActivity>.broadcast();

  /// Every purchase update and delivery outcome, as it happens.
  Stream<PurchaseActivity> get activity => _activity.stream;

  StreamSubscription<List<StorePurchase>>? _sub;
  bool _started = false;
  bool _disposed = false;

  /// The hosted account the last sweep ran for (`baseUrl|accountKey`).
  String? _sweptFor;

  /// Purchases being posted right now, by transaction id: the launch sweep
  /// and `Transaction.updates` can hand over the same one at once.
  final _inFlight = <String>{};

  /// How many purchase sheets are open. While one is, it says what happened;
  /// otherwise the app-wide notices do (`PurchaseNotices`).
  int _sheets = 0;
  bool get sheetOpen => _sheets > 0;

  /// The purchase sheet holds this while it is open; call the result to let go.
  VoidCallback holdSheet() {
    _sheets++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _sheets--;
    };
  }

  /// Follows the session from now on. Idempotent.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _auth.session.addListener(_onSession);
    _onSession();
  }

  void _onSession() {
    final session = _auth.session.value;
    if (!_canDeliverTo(session)) return;
    _sub ??= billing.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => _log.warning('purchaseStream error: $e'),
    );
    final owner = '${session!.baseUrl}|${session.accountKey}';
    if (_sweptFor == owner) return;
    _sweptFor = owner;
    unawaited(_sweep());
  }

  static bool _canDeliverTo(AuthSession? session) =>
      session != null && session.isHosted && session.accountKey.isNotEmpty;

  /// Delivers what the store still holds unfinished.
  Future<void> _sweep() async {
    try {
      final unfinished = await billing.unfinishedPurchases();
      if (unfinished.isEmpty) return;
      _log.info('delivering ${unfinished.length} unfinished purchase(s)');
      await _onPurchases(unfinished);
    } catch (e) {
      _log.warning('unfinished purchase sweep failed: $e');
    }
  }

  Future<void> _onPurchases(List<StorePurchase> list) async {
    for (final p in list) {
      if (_disposed) return;
      switch (p.status) {
        case StorePurchaseStatus.pending:
          _emit(PurchaseActivityKind.pending, p);
        case StorePurchaseStatus.error:
          _log.warning('purchase error: ${p.error}');
          _emit(PurchaseActivityKind.failed, p, message: p.error);
          await _finish(p);
        case StorePurchaseStatus.canceled:
          _emit(PurchaseActivityKind.canceled, p);
          await _finish(p);
        case StorePurchaseStatus.purchased:
        case StorePurchaseStatus.restored:
          // Play's Restore hands back every subscription the Google account
          // owns; an acknowledged one was applied when it was bought, so only
          // the unacknowledged are delivered. StoreKit 2 never marks a
          // restored transaction finishable, and Restore is how a purchase
          // reaches an account on a new device, so Apple's all go.
          if (store == PurchaseStore.googlePlay && !p.pendingCompletePurchase) {
            continue;
          }
          await _deliver(p);
      }
    }
  }

  void _emit(PurchaseActivityKind kind, StorePurchase p, {String? message}) {
    if (_disposed) return;
    _activity.add(
      PurchaseActivity(kind, productId: p.productId, message: message),
    );
  }

  Future<void> _finish(StorePurchase p) async {
    if (!p.pendingCompletePurchase) return;
    try {
      await billing.completePurchase(p);
    } catch (e) {
      _log.warning('completePurchase failed: $e');
    }
  }

  /// Posts [p] to the hosted service and acts on the answer (see the class
  /// doc). A purchase is finished with the store only once the server has
  /// answered for good: a finished Apple transaction is never handed back,
  /// and Google never refunds an acknowledged one.
  Future<void> _deliver(StorePurchase p) async {
    final purchaseId = inAppTransactionId(p);
    if (purchaseId == null || purchaseId.isEmpty) {
      // The server requires a non-empty string; posting null just 422s, and
      // no retry would ever have one.
      _log.warning('no transaction id for ${p.productId}, skipping delivery');
      await _finish(p);
      return;
    }
    final session = _auth.session.value;
    if (!_canDeliverTo(session)) {
      // Signed out, self-hosted (the POST would reach the wrong server), or a
      // cache with no account key yet: keep it for a later delivery.
      _log.info(
        'no hosted account to deliver ${p.productId} to, left unfinished',
      );
      _emit(PurchaseActivityKind.retryLater, p);
      return;
    }
    if (!_inFlight.add(purchaseId)) return;
    _emit(PurchaseActivityKind.delivering, p);
    try {
      final verification = p.serverVerificationData;
      await _apiClient.postJson(
        '/api/admin/subscription',
        body: {
          'inapp_transaction_id': purchaseId,
          'key': session!.accountKey,
          'plan': planSlugOf(p.productId),
          if (verification.isNotEmpty) 'verification_data': verification,
          'source': store.wireName,
          'bundle_id': kStoreBundleId,
        },
      );
    } catch (e) {
      _inFlight.remove(purchaseId);
      if (isPermanentRejection(e)) {
        _log.warning('subscription refused: $e');
        // StoreKit hands an unfinished transaction back on every launch and
        // refuses a new purchase of the same product while it waits, so
        // Apple's is finished. Google's stays unacknowledged: Play refunds it.
        if (store == PurchaseStore.appStore) await _finish(p);
        _emit(
          PurchaseActivityKind.rejected,
          p,
          message: e is ApiException ? e.message : null,
        );
      } else {
        _log.warning('subscription deliver failed, left unfinished: $e');
        _emit(PurchaseActivityKind.retryLater, p);
      }
      return;
    }
    _inFlight.remove(purchaseId);
    // The server has it: finish it even if the refresh below fails.
    await _finish(p);
    try {
      // Full session snapshot — flips the plan slug everywhere.
      await _auth.refresh();
    } catch (e) {
      _log.warning('refresh after subscription deliver failed: $e');
    }
    _emit(PurchaseActivityKind.applied, p);
  }

  Future<void> dispose() async {
    _disposed = true;
    if (_started) _auth.session.removeListener(_onSession);
    await _sub?.cancel();
    await _activity.close();
  }
}

/// Whether a failed `POST /api/admin/subscription` is the hosted service's
/// final word on the purchase: 403 (the token is not this account's), 409
/// (`sandbox`, `linked`) or 422 (`unverified`). Everything else — a 5xx, no
/// network, a server without the route — may succeed on a later try.
@visibleForTesting
bool isPermanentRejection(Object e) => switch (e) {
  // A 400 "no query results for model" — not an answer about the purchase.
  NotFoundException() => false,
  ConflictException() => true,
  ValidationException() => true,
  ServerException(statusCode: 403) => true,
  _ => false,
};

/// The plan slug the hosted endpoint is sent alongside the transaction: the
/// product id with `-` as `_`, and without the `v2_` prefix the new Apple
/// record's ids may carry (the server derives the plan from the store-verified
/// product anyway).
String planSlugOf(String productId) =>
    productId.replaceAll('-', '_').replaceFirst(RegExp('^v2_'), '');

/// The value the hosted endpoint stores as `accounts.inapp_transaction_id`.
///
/// Apple keys its renewal / cancellation / refund notifications on the
/// subscription's **original** transaction id and the server matches that
/// exactly, so storing a per-transaction id silently orphans the account —
/// later notifications find no match and the plan stops being extended. For
/// an initial purchase the two are identical; they diverge on restore and on
/// renewals, which both reach here.
///
/// Google is the opposite: its notifications resolve to the `orderId` that
/// already arrives as [StorePurchase.purchaseId], so Android falls through
/// unchanged.
@visibleForTesting
String? inAppTransactionId(StorePurchase p) {
  if (p.isStoreKit1) {
    // StoreKit 1 — only reached if `enableStoreKit1()` is ever called.
    // The original transaction is populated for restored transactions only.
    final original = p.storeKit1OriginalTransactionId;
    if (original != null) return original;
  } else {
    // StoreKit 2 (the plugin default) drops `originalId` when it builds
    // SK2PurchaseDetails, but Apple's own transaction JSON is passed through
    // as `localVerificationData` and still carries it. Google's equivalent
    // JSON has no such key, so Android returns null here and falls back to
    // `purchaseID`.
    final original = appleOriginalTransactionId(p.localVerificationData);
    if (original != null) return original;
  }
  return p.purchaseId;
}

/// Pulls Apple's `originalTransactionId` out of a StoreKit 2 transaction's
/// `localVerificationData` — Apple's `Transaction.jsonRepresentation`.
///
/// Returns `null` when the payload is empty, isn't a JSON object, or carries no
/// usable `originalTransactionId`, so callers can fall back to `purchaseID`.
/// Never throws: this runs inside the purchase-stream callback, where an
/// exception would take down delivery of a paid purchase.
@visibleForTesting
String? appleOriginalTransactionId(String localVerificationData) {
  if (localVerificationData.isEmpty) return null;
  try {
    final decoded = jsonDecode(localVerificationData);
    if (decoded is! Map<String, dynamic>) return null;
    // Apple documents the field as a string, but encodes some numeric ids as
    // JSON numbers — same coercion hazard as the invoice line-item payloads.
    final id = jsonScalarToString(decoded['originalTransactionId']);
    return (id == null || id.isEmpty) ? null : id;
  } catch (_) {
    return null;
  }
}
