import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBindingObserver;
import 'package:logging/logging.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/data/models/api/json_coercion.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/api_client.dart';
import 'package:admin/data/services/api_exception.dart';

/// This app's bundle id on the App Store and its package name on Play — the
/// hosted endpoint checks the store-verified transaction against it.
const String kStoreBundleId = 'com.invoiceninja.admin';

/// The hosted service's in-app purchase settings for the signed-in user
/// ([IapConfig]).
const String kIapConfigPath = '/api/admin/iap/config';

/// Where a paid purchase is posted to be applied to the account.
const String kSubscriptionPath = '/api/admin/subscription';

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

  /// The hosted service refused it (409, 422): a test purchase, one already
  /// linked to another account, one posted for another account, or one it
  /// could not verify. [PurchaseActivity.message] is the server's own
  /// explanation.
  rejected,

  /// Not applied yet — the server or the network failed, the hosted service
  /// has not confirmed it takes this app's purchases, or no signed-in hosted
  /// account to apply it to. Left unfinished, so the store hands it back on
  /// the next launch.
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

/// Which store a purchase was made in, as `POST` [kSubscriptionPath] names it
/// (`source`).
enum PurchaseStore {
  appStore('app_store'),
  googlePlay('google_play');

  const PurchaseStore(this.wireName);

  final String wireName;

  static PurchaseStore of(TargetPlatform platform) =>
      platform == TargetPlatform.android ? googlePlay : appStore;
}

/// The hosted service's in-app purchase settings for the signed-in user
/// (`GET` [kIapConfigPath]). [PurchaseDelivery.config] is its one owner: it
/// asks once per signed-in user and the purchase sheet reads the same answer.
@immutable
class IapConfig {
  const IapConfig({
    required this.purchasesEnabled,
    this.appAccountToken,
    this.accountKey = '',
  });

  /// Fail-closed default: no purchases, nothing delivered.
  static const closed = IapConfig(purchasesEnabled: false);

  final bool purchasesEnabled;

  /// The account's purchase token, a UUID: sent with every purchase as
  /// Apple's `appAccountToken` / Play's `obfuscatedAccountId`, so the store
  /// (and the server notifications it sends) name the account the purchase
  /// was made for. Null when the server sent none, or not a UUID — StoreKit
  /// drops a non-UUID token without a word, and the server then refuses the
  /// paid purchase.
  final String? appAccountToken;

  /// `account_key`: the key of the account the hosted service applies this
  /// user's purchases to (`$user->account->key`), and so the `key` every
  /// delivery posts. Blank when the server sent none: such a service is not
  /// ready, and nothing is sold or delivered.
  final String accountKey;

  /// Whether a paid purchase may be posted under this answer.
  bool get canDeliver => accountKey.isNotEmpty;

  /// Whether a purchase may be started: the service takes them, there is a
  /// token to tie one to the account, and an account to apply it to.
  bool get canPurchase =>
      purchasesEnabled && appAccountToken != null && canDeliver;

  /// Whether a plan bought now would land on [session]'s active account: the
  /// hosted service applies it to the user's own account ([accountKey]), so
  /// selling one while a company of another account is active would bill for
  /// a plan that account never gets.
  bool sellsTo(AuthSession session) =>
      canPurchase && accountKey == session.accountKey;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// Reads the config response; anything of the wrong shape is [closed].
  factory IapConfig.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return closed;
    final token = json['app_account_token'];
    final key = json['account_key'];
    return IapConfig(
      purchasesEnabled: json['purchases_enabled'] == true,
      appAccountToken: token is String && _uuid.hasMatch(token.trim())
          ? token.trim()
          : null,
      accountKey: key is String ? key.trim() : '',
    );
  }
}

/// How long [PurchaseDelivery] waits before trying again a purchase it could
/// not apply yet: after the first failure, the second, and every one after.
const kPurchaseRetryBackoff = [
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 10),
];

/// Delivers paid App Store / Play purchases to the hosted service, for the
/// app's whole lifetime. Owned by `Services` and built only on a
/// store-billing build (`isStoreBillingBuild`):
/// `InAppPurchase.instance.purchaseStream` throws on web, Windows and Linux,
/// so nothing else may touch it.
///
/// Listening starts the first time a hosted, signed-in session exists, and
/// never stops. That is what StoreKit needs to hand over
/// `Transaction.updates`: renewals, an Ask to Buy approved later, a purchase
/// interrupted by a crash. Each time a signed-in user appears (a sign-in, a
/// different user) the purchases the stores still hold unfinished are swept
/// and delivered too: Play's unacknowledged ones, and StoreKit's
/// `Transaction.unfinished`. A purchase that could not be applied yet is
/// swept again with a backoff ([kPurchaseRetryBackoff]) while the app runs,
/// and whenever the app comes back to the foreground ([onAppResumed]).
///
/// The upgrade sheet only lists products and starts a purchase; every
/// delivery comes through here, and the sheet follows [activity].
///
/// Nothing is posted, and nothing paid is finished, until the hosted service
/// has answered [kIapConfigPath] with a 200 that names the account
/// (`account_key`, [config]): that is how the app knows the server it posts
/// to takes this app's purchases, and which account they go to. A 404 (a
/// server without the route), an answer without `account_key`, or any other
/// failure leaves the purchase unfinished for a later try. The answer's
/// `purchases_enabled` gates only the sale, never a delivery: a purchase
/// already paid for is always applied.
///
/// Response contract (`POST` [kSubscriptionPath]):
///  * 200: applied. Finish it with the store, then `auth.refresh()`.
///  * 409 / 422 with a final `reason` ([kFinalRejectionReasons]: a test
///    purchase, one expired, revoked or upgraded, one already linked to
///    another account): finished on Apple, so StoreKit stops handing it back;
///    left unacknowledged on Google, so Play refunds it.
///  * any other 409 / 422 (`account`, `token_mismatch`, `no_token`,
///    `unverified`, no reason at all): refused for now, left unfinished.
///  * anything else (403 for a stale or locked token, 429, 5xx, no network, a
///    404 from a server without the route): left unfinished and tried again.
class PurchaseDelivery {
  PurchaseDelivery({
    required ApiClient apiClient,
    required AuthRepository auth,
    StoreBilling? billing,
    TargetPlatform? platform,
    Timer Function(Duration, void Function())? timer,
  }) : _apiClient = apiClient,
       _auth = auth,
       billing = billing ?? StoreBilling(),
       _platform = platform ?? defaultTargetPlatform,
       _timer = timer ?? Timer.new;

  final ApiClient _apiClient;
  final AuthRepository _auth;
  final TargetPlatform _platform;
  final Timer Function(Duration, void Function()) _timer;
  final _log = Logger('PurchaseDelivery');

  /// The store SDK. The purchase sheet uses the same instance to list
  /// products and start a purchase.
  final StoreBilling billing;

  PurchaseStore get store => PurchaseStore.of(_platform);

  late final _activity = StreamController<PurchaseActivity>.broadcast(
    onListen: _flushUnheard,
  );

  /// Every purchase update and delivery outcome, as it happens. What happens
  /// before anything listens (the first sweep can finish before the app-wide
  /// `PurchaseNotices` subscribes) is held, and handed to the first listener.
  Stream<PurchaseActivity> get activity => _activity.stream;

  /// Outcomes emitted before the first listener ([activity]); null once one
  /// has listened.
  List<PurchaseActivity>? _unheard = [];

  /// At most this many are held for the first listener.
  static const _maxUnheard = 20;

  void _flushUnheard() {
    final held = _unheard;
    _unheard = null;
    if (held == null) return;
    for (final a in held) {
      _activity.add(a);
    }
  }

  StreamSubscription<List<StorePurchase>>? _sub;
  bool _started = false;
  bool _disposed = false;

  /// The signed-in user the last sweep ran for ([_ownerOf]). Cleared when the
  /// session can no longer be delivered to (a sign-out), so the next sign-in
  /// sweeps again.
  String? _sweptFor;

  /// The last [kIapConfigPath] answer that named an account, and the user
  /// ([_ownerOf]) it was asked for. Never set from a failure or from an
  /// answer without `account_key`: those are asked again next time.
  IapConfig? _config;
  String? _configFor;

  /// The config request on the wire, for [_configOwner].
  Future<IapConfig?>? _configInFlight;
  String? _configOwner;

  /// Purchases being posted right now, by transaction id: the launch sweep
  /// and `Transaction.updates` can hand over the same one at once.
  final _inFlight = <String>{};

  /// The pending retry sweep, and how many have been scheduled since the last
  /// purchase was applied ([kPurchaseRetryBackoff]).
  Timer? _retry;
  int _retries = 0;

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
    if (!_canDeliverTo(session)) {
      // Signed out (or self-hosted): the next hosted session, even the same
      // user's, sweeps and asks for the config afresh.
      _sweptFor = null;
      _config = null;
      _configFor = null;
      _retry?.cancel();
      _retry = null;
      _retries = 0;
      return;
    }
    _sub ??= billing.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => _log.warning('purchaseStream error: $e'),
    );
    final owner = _ownerOf(session!);
    if (_sweptFor == owner) return;
    _sweptFor = owner;
    unawaited(_sweep(owner));
  }

  /// The app is back in the foreground: ask the config afresh (support may
  /// have switched purchases on or off) and sweep what the stores still hold
  /// unfinished. Wired by [PurchaseResumeObserver].
  void onAppResumed() {
    if (_disposed || !_started) return;
    final session = _auth.session.value;
    if (!_canDeliverTo(session)) return;
    _config = null;
    _configFor = null;
    unawaited(_sweep(_ownerOf(session!)));
  }

  /// Purchases are applied to the signed-in user's own account, whichever
  /// company is active, so the config (and its `account_key`) belongs to the
  /// user on this server, not to the active company.
  static String _ownerOf(AuthSession session) =>
      '${session.baseUrl}|${session.userId}';

  static bool _canDeliverTo(AuthSession? session) =>
      session != null && session.isHosted;

  /// Delivers what the store still holds unfinished.
  Future<void> _sweep(String owner) async {
    try {
      final unfinished = await billing.unfinishedPurchases();
      if (unfinished.isEmpty) {
        _retries = 0;
        return;
      }
      if (await config() == null) {
        // Left unfinished, and swept again on the next session update (a
        // refresh, a sign-in), the next retry and the next resume.
        if (_sweptFor == owner) _sweptFor = null;
        _log.info(
          'iap config not confirmed, ${unfinished.length} unfinished '
          'purchase(s) left for later',
        );
        for (final p in unfinished) {
          _emit(PurchaseActivityKind.retryLater, p);
        }
        _scheduleRetry();
        return;
      }
      _log.info('delivering ${unfinished.length} unfinished purchase(s)');
      await _onPurchases(unfinished);
    } catch (e) {
      _log.warning('unfinished purchase sweep failed: $e');
    }
  }

  /// Sweeps again after the next [kPurchaseRetryBackoff] step, unless one is
  /// already waiting.
  void _scheduleRetry() {
    if (_disposed || _retry != null) return;
    if (!_canDeliverTo(_auth.session.value)) return;
    final step = _retries < kPurchaseRetryBackoff.length
        ? kPurchaseRetryBackoff[_retries]
        : kPurchaseRetryBackoff.last;
    _retries++;
    _retry = _timer(step, () {
      _retry = null;
      final session = _auth.session.value;
      if (_disposed || !_canDeliverTo(session)) return;
      unawaited(_sweep(_ownerOf(session!)));
    });
  }

  /// The hosted service's answer to [kIapConfigPath] for the signed-in user,
  /// or null while it is unknown: signed out, self-hosted, any failure, or a
  /// 200 without `account_key` (a service not ready to take purchases).
  /// Asked once per user and kept; asked again after any failure, after a
  /// sign-out, and when the app returns to the foreground.
  Future<IapConfig?> config() async {
    final session = _auth.session.value;
    if (!_canDeliverTo(session)) return null;
    final owner = _ownerOf(session!);
    if (_configFor == owner && _config != null) return _config;
    if (_configOwner == owner && _configInFlight != null) {
      return _configInFlight!;
    }
    _configOwner = owner;
    final request = _askConfig(owner);
    _configInFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_configInFlight, request)) {
        _configInFlight = null;
        _configOwner = null;
      }
    }
  }

  Future<IapConfig?> _askConfig(String owner) async {
    final IapConfig answer;
    try {
      answer = IapConfig.fromJson(await _apiClient.getOne(kIapConfigPath));
    } catch (e) {
      _log.info('iap config unavailable, purchases left unfinished: $e');
      return null;
    }
    if (!answer.canDeliver) {
      _log.warning('iap config names no account_key, purchases off');
      return null;
    }
    if (answer.purchasesEnabled && answer.appAccountToken == null) {
      _log.warning('iap config has no usable app_account_token');
    }
    // Answered for the session it was asked under, and only if that session
    // is still the current one.
    final now = _auth.session.value;
    if (now == null || _ownerOf(now) != owner) return null;
    _config = answer;
    _configFor = owner;
    return answer;
  }

  /// Asks the store to hand back this account's purchases (Restore); each one
  /// arrives on the purchase stream and is delivered like any other, so only
  /// once the hosted config has been confirmed. Never gated on
  /// `purchases_enabled`: it re-delivers purchases already paid for.
  Future<void> restore() async {
    try {
      await billing.restorePurchases();
    } catch (e) {
      _log.warning('restorePurchases: $e');
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
    final a = PurchaseActivity(kind, productId: p.productId, message: message);
    final held = _unheard;
    if (held != null && !_activity.hasListener) {
      if (held.length < _maxUnheard) held.add(a);
      return;
    }
    _activity.add(a);
  }

  /// Finishes [p] with the store. A Google acknowledgement the store did not
  /// confirm is logged and swept again: Play refunds a purchase nobody
  /// acknowledges within three days, and the server takes a re-post.
  Future<void> _finish(StorePurchase p) async {
    if (!p.pendingCompletePurchase) return;
    try {
      if (!await billing.completePurchase(p)) {
        _log.warning(
          'the store did not confirm finishing ${p.productId}, '
          'sweeping it again',
        );
        _scheduleRetry();
      }
    } catch (e) {
      _log.warning('completePurchase failed: $e');
      _scheduleRetry();
    }
  }

  /// Not applied yet: left unfinished, said so, and tried again later.
  void _retryLater(StorePurchase p) {
    _emit(PurchaseActivityKind.retryLater, p);
    _scheduleRetry();
  }

  /// Posts [p] to the hosted service and acts on the answer (see the class
  /// doc). A purchase is finished with the store only once the server has
  /// answered for good: a finished Apple transaction is never handed back,
  /// and Google never refunds an acknowledged one.
  Future<void> _deliver(StorePurchase p) async {
    if (!_canDeliverTo(_auth.session.value)) {
      // Signed out, or self-hosted (the POST would reach the wrong server):
      // keep it for a later delivery.
      _log.info(
        'no hosted account to deliver ${p.productId} to, left unfinished',
      );
      _emit(PurchaseActivityKind.retryLater, p);
      return;
    }
    // Nothing paid is posted or finished until the hosted service has
    // confirmed it takes this app's purchases, and for which account.
    final config = await this.config();
    if (config == null) {
      _log.info('iap config not confirmed, ${p.productId} left unfinished');
      _retryLater(p);
      return;
    }
    // A refunded or upgraded-away Apple transaction has nothing to apply.
    if (store == PurchaseStore.appStore &&
        appleTransactionIsClosed(p.localVerificationData)) {
      _log.info('${p.productId} was revoked or upgraded, finished unposted');
      await _finish(p);
      return;
    }
    // Bought for another account (another user on this Apple ID or Google
    // account): not this user's to apply, and not ours to finish.
    final token = purchaseAccountToken(p, store);
    if (token != null &&
        token.toLowerCase() != config.appAccountToken?.toLowerCase()) {
      _log.info('${p.productId} was bought for another account, left alone');
      return;
    }
    final purchaseId = inAppTransactionId(p);
    final verification = p.serverVerificationData;
    final hasId = purchaseId != null && purchaseId.isNotEmpty;
    // Play can hand over a purchase with no order id yet; its purchase token
    // still names it, and the server verifies it from that.
    final byToken =
        !hasId && store == PurchaseStore.googlePlay && verification.isNotEmpty;
    if (!hasId && !byToken) {
      // Nothing to name it by. Never finished: a later hand-over may carry
      // an id, and Play would refund it the moment it was acknowledged.
      _log.warning('no transaction id for ${p.productId}, left unfinished');
      _retryLater(p);
      return;
    }
    final flightKey = hasId ? purchaseId : verification;
    if (!_inFlight.add(flightKey)) return;
    _emit(PurchaseActivityKind.delivering, p);
    try {
      await _apiClient.postJson(
        kSubscriptionPath,
        body: {
          if (hasId) 'inapp_transaction_id': purchaseId,
          'key': config.accountKey,
          'plan': planSlugOf(p.productId),
          if (verification.isNotEmpty) 'verification_data': verification,
          'source': store.wireName,
          'bundle_id': kStoreBundleId,
        },
      );
    } catch (e) {
      _inFlight.remove(flightKey);
      if (isPermanentRejection(e)) {
        _log.warning('subscription refused (${rejectionReason(e)}): $e');
        // StoreKit hands an unfinished transaction back on every launch and
        // refuses a new purchase of the same product while it waits, so
        // Apple's is finished once the refusal is final. Google's stays
        // unacknowledged: Play refunds it.
        if (store == PurchaseStore.appStore && finishesOnRejection(e)) {
          await _finish(p);
        }
        _emit(
          PurchaseActivityKind.rejected,
          p,
          message: e is ApiException ? e.message : null,
        );
      } else {
        _log.warning('subscription deliver failed, left unfinished: $e');
        _retryLater(p);
      }
      return;
    }
    _inFlight.remove(flightKey);
    _retries = 0;
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
    _retry?.cancel();
    _retry = null;
    if (_started) _auth.session.removeListener(_onSession);
    await _sub?.cancel();
    await _activity.close();
  }
}

/// Tells [PurchaseDelivery] the app came back to the foreground, so it sweeps
/// what the stores still hold unfinished. Registered by the app root.
class PurchaseResumeObserver with WidgetsBindingObserver {
  PurchaseResumeObserver(this.delivery);

  final PurchaseDelivery delivery;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) delivery.onAppResumed();
  }
}

/// The `reason`s on a 409 / 422 that are the hosted service's final word on a
/// purchase, so an Apple one is finished: a test purchase, one that has
/// expired, been refunded or upgraded away, and one already linked to another
/// account. Every other refusal may change (`account`, `token_mismatch`,
/// `no_token`, `unverified`, none given) and leaves it unfinished.
const kFinalRejectionReasons = {
  'sandbox',
  'expired',
  'revoked',
  'upgraded',
  'linked',
};

/// Whether a failed `POST` [kSubscriptionPath] is a refusal of the purchase
/// itself: a 409 or a 422. Everything else may succeed on a later try — a
/// 403 above all, which is what the server's token check answers for a stale
/// or invalid token or a locked user. Likewise a 429, a 5xx, no network, or a
/// server without the route.
@visibleForTesting
bool isPermanentRejection(Object e) => switch (e) {
  // A 400 "no query results for model" — not an answer about the purchase.
  NotFoundException() => false,
  ConflictException() => true,
  ValidationException() => true,
  _ => false,
};

/// The `reason` a 409 / 422 gave, or null.
@visibleForTesting
String? rejectionReason(Object e) {
  final body = switch (e) {
    NotFoundException() => null,
    ConflictException(:final body) => body,
    ValidationException(:final body) => body,
    _ => null,
  };
  final reason = body?['reason'];
  return reason is String && reason.trim().isNotEmpty ? reason.trim() : null;
}

/// Whether a refusal is final ([kFinalRejectionReasons]), so an Apple
/// purchase is finished on it.
@visibleForTesting
bool finishesOnRejection(Object e) =>
    isPermanentRejection(e) &&
    kFinalRejectionReasons.contains(rejectionReason(e));

/// The account token the purchase was made under — StoreKit 2's
/// `appAccountToken` in Apple's transaction JSON, Play's
/// `obfuscatedAccountId` in Google's purchase JSON — or null when it carries
/// none (a purchase made before tokens were sent, or by the Legacy app).
@visibleForTesting
String? purchaseAccountToken(StorePurchase p, PurchaseStore store) {
  final json = _jsonObject(p.localVerificationData);
  if (json == null) return null;
  final token = jsonScalarToString(
    json[store == PurchaseStore.appStore
        ? 'appAccountToken'
        : 'obfuscatedAccountId'],
  );
  return (token == null || token.trim().isEmpty) ? null : token.trim();
}

/// Whether Apple's transaction JSON says it has been refunded or revoked
/// (`revocationDate`) or replaced by an upgrade (`isUpgraded`): nothing to
/// apply, so it is finished without a post.
@visibleForTesting
bool appleTransactionIsClosed(String localVerificationData) {
  final json = _jsonObject(localVerificationData);
  if (json == null) return false;
  return json['revocationDate'] != null || json['isUpgraded'] == true;
}

Map<String, dynamic>? _jsonObject(String raw) {
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

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
