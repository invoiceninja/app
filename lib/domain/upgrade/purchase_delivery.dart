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
/// asks once per signed-in user and active company, and the purchase sheet
/// reads the same answer.
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
/// different user) or another company becomes active, the purchases the
/// stores still hold unfinished are swept and delivered too: Play's unacknowledged ones, and StoreKit's
/// `Transaction.unfinished`. A purchase that could not be applied yet is
/// swept again with a backoff ([kPurchaseRetryBackoff]) while the app runs,
/// and whenever the app comes back to the foreground ([onAppResumed]).
///
/// A transaction is posted until the hosted service has answered for good,
/// and never again after: once applied (200) only its finish is retried, so a
/// failed Play acknowledgement never re-posts it or refreshes the session, and
/// a resume sweep racing the purchase stream never posts it twice. One the
/// service refused but left with the store (any Google refusal, an Apple one
/// with a reason that may change) is re-posted only by the sweep of a new
/// sign-in (a launch included) and by Restore, never by a resume or a retry,
/// and the refusal is said once per signed-in user.
///
/// The upgrade sheet only lists products and starts a purchase; every
/// delivery comes through here, and the sheet follows [activity].
///
/// Nothing is posted, and nothing paid is finished, until the hosted service
/// has answered [kIapConfigPath] with a 200 that names the account
/// (`account_key`, [config]): that is how the app knows the server it posts
/// to takes this app's purchases, and which account they go to. It is asked
/// with the active company's token and answers for that company: a user who
/// does not own it, or a company of another account, gets no `account_key`.
/// A 404 (a server without the route) or any other failure leaves the
/// purchase unfinished and tried again; an answer without `account_key`
/// leaves it unfinished, not retried on a timer, until another company is
/// active, someone signs in, or the app returns to the foreground. The answer's
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

  /// The signed-in user and active company the last sweep ran for
  /// ([_scopeOf]). Cleared when the session can no longer be delivered to (a
  /// sign-out), so the next sign-in sweeps again; a switch to another company
  /// sweeps again too, since the config may answer differently there.
  String? _sweptFor;

  /// The last 200 from [kIapConfigPath], and the user and active company
  /// ([_scopeOf]) it was asked for — one without `account_key` included (the
  /// user does not own the active company, or it belongs to another account),
  /// so that answer is not asked again on every retry. Never set from a
  /// failure: that is asked again next time.
  IapConfig? _config;
  String? _configFor;

  /// The config request on the wire, for [_configScope].
  Future<IapConfig?>? _configInFlight;
  String? _configScope;

  /// Purchases being posted right now, by [_transactionKey]: the launch
  /// sweep and `Transaction.updates` can hand over the same one at once.
  final _inFlight = <String>{};

  /// Transactions the hosted service has answered for good while the app
  /// runs, by [_transactionKey]: applied (200), or refused with a final reason
  /// on Apple. Only finishing them with the store is left, so none is posted
  /// again — not by a sweep that read the store's list before the finish, not
  /// by a retry after a failed Play acknowledgement. True once the store has
  /// confirmed the finish.
  final _answered = <String, bool>{};

  /// Transactions the hosted service refused but left with the store, as
  /// `'<owner>|<transaction key>'`: a resume or retry sweep skips them, and a
  /// re-post (a sign-in's sweep, Restore) is quiet, so the refusal is said
  /// once. In memory: a cold start says it again, once.
  final _refused = <String>{};

  /// Purchases already logged as having no transaction id to post them by.
  final _loggedNoId = <String>{};

  /// The pending retry sweep, and how many have been scheduled since a
  /// purchase was last finished with the store ([kPurchaseRetryBackoff]).
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
    final scope = _scopeOf(session!);
    if (_sweptFor == scope) return;
    _sweptFor = scope;
    unawaited(_sweep(_ownerOf(session), repostRefused: true));
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

  /// The signed-in user on this server: whom a refusal has been said to
  /// ([_refused]).
  static String _ownerOf(AuthSession session) =>
      '${session.baseUrl}|${session.userId}';

  /// The user and the active company. The hosted service answers the config
  /// for the company of the token it is asked with — whether the user owns
  /// it, and whether it belongs to the user's own account decide
  /// `account_key` — so the config is per active company, not per user.
  static String _scopeOf(AuthSession session) =>
      '${_ownerOf(session)}|${session.currentCompanyId}';

  static bool _canDeliverTo(AuthSession? session) =>
      session != null && session.isHosted;

  /// Delivers what the store still holds unfinished. A purchase already
  /// answered for good is only finished; one refused but left with the store
  /// is posted again only when [repostRefused] (a new sign-in's sweep).
  Future<void> _sweep(String owner, {bool repostRefused = false}) async {
    try {
      final all = await billing.unfinishedPurchases();
      if (all.isEmpty) {
        _retries = 0;
        return;
      }
      final unfinished = <StorePurchase>[];
      for (final p in all) {
        final key = _transactionKey(p);
        if (key != null && _answered.containsKey(key)) {
          await _finishAnswered(p, key);
        } else if (key != null &&
            !repostRefused &&
            _refused.contains('$owner|$key')) {
          continue;
        } else {
          unfinished.add(p);
        }
      }
      if (unfinished.isEmpty) return;
      final answer = await _configAnswer();
      if (answer == null) {
        // Left unfinished, and swept again on the next session update (a
        // refresh, a sign-in), the next retry and the next resume.
        final session = _auth.session.value;
        if (session != null && _sweptFor == _scopeOf(session)) {
          _sweptFor = null;
        }
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
      if (!answer.canDeliver) {
        // An answer, not a failure: nothing to retry until the company
        // changes, someone signs in, or the app returns to the foreground.
        _log.info(
          'iap config names no account here, ${unfinished.length} '
          'unfinished purchase(s) left for another company',
        );
        for (final p in unfinished) {
          _emit(PurchaseActivityKind.retryLater, p);
        }
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

  /// The hosted service's answer to [kIapConfigPath] for the signed-in user
  /// and the active company, or null while nothing may be delivered under it:
  /// signed out, self-hosted, any failure, or a 200 without `account_key`
  /// (the user does not own the active company, or it belongs to another
  /// account, or the service is not ready to take purchases). Asked once per
  /// user and company and kept; asked again after any failure, after a
  /// sign-out, on a switch to another company, and when the app returns to
  /// the foreground.
  Future<IapConfig?> config() async {
    final answer = await _configAnswer();
    return answer != null && answer.canDeliver ? answer : null;
  }

  /// [config]'s 200 as it came, one without `account_key` included; null on
  /// a failure (or no hosted session).
  Future<IapConfig?> _configAnswer() async {
    final session = _auth.session.value;
    if (!_canDeliverTo(session)) return null;
    final scope = _scopeOf(session!);
    if (_configFor == scope && _config != null) return _config;
    if (_configScope == scope && _configInFlight != null) {
      return _configInFlight!;
    }
    _configScope = scope;
    final request = _askConfig(scope);
    _configInFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_configInFlight, request)) {
        _configInFlight = null;
        _configScope = null;
      }
    }
  }

  Future<IapConfig?> _askConfig(String scope) async {
    final IapConfig answer;
    try {
      answer = IapConfig.fromJson(await _apiClient.getOne(kIapConfigPath));
    } catch (e) {
      _log.info('iap config unavailable, purchases left unfinished: $e');
      return null;
    }
    if (!answer.canDeliver) {
      _log.warning('iap config names no account_key here, purchases off');
    } else if (answer.purchasesEnabled && answer.appAccountToken == null) {
      _log.warning('iap config has no usable app_account_token');
    }
    // Answered for the user and company it was asked under, and only if they
    // are still the current ones.
    final now = _auth.session.value;
    if (now == null || _scopeOf(now) != scope) return null;
    _config = answer;
    _configFor = scope;
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

  /// Finishes [p] with the store; true once the store has confirmed it (or
  /// there was nothing to finish). A Google acknowledgement the store did not
  /// confirm is logged and swept again: Play refunds a purchase nobody
  /// acknowledges within three days.
  Future<bool> _finish(StorePurchase p) async {
    if (!p.pendingCompletePurchase) return true;
    try {
      if (await billing.completePurchase(p)) return true;
      _log.warning(
        'the store did not confirm finishing ${p.productId}, '
        'sweeping it again',
      );
    } catch (e) {
      _log.warning('completePurchase failed: $e');
    }
    _scheduleRetry();
    return false;
  }

  /// Finishes a purchase the hosted service has answered for good
  /// ([_answered]) — the only thing left to do with it. The backoff starts
  /// over only once the store confirms: a reset before that made every retry
  /// of a failed Play acknowledgement the first, 30 second, step.
  Future<void> _finishAnswered(StorePurchase p, String key) async {
    if (_answered[key] == true) return;
    if (await _finish(p)) {
      _answered[key] = true;
      _retries = 0;
    }
  }

  /// The id that names this one transaction, never shared with a renewal: the
  /// store's own per-transaction id (Apple's transaction id, Play's order id),
  /// else the id it is posted under. Null when it has neither.
  static String? _transactionKey(StorePurchase p) {
    final id = p.purchaseId;
    if (id != null && id.isNotEmpty) return id;
    final posted = inAppTransactionId(p);
    return (posted == null || posted.isEmpty) ? null : posted;
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
    final key = _transactionKey(p);
    // Answered for good already (a sweep that read the store's list before
    // the purchase stream's delivery finished it, a retry after a failed
    // acknowledgement): only the finish is left, never a second post.
    if (key != null && _answered.containsKey(key)) {
      await _finishAnswered(p, key);
      return;
    }
    final session = _auth.session.value;
    if (!_canDeliverTo(session)) {
      // Signed out, or self-hosted (the POST would reach the wrong server):
      // keep it for a later delivery.
      _log.info(
        'no hosted account to deliver ${p.productId} to, left unfinished',
      );
      _emit(PurchaseActivityKind.retryLater, p);
      return;
    }
    final owner = _ownerOf(session!);
    // Nothing paid is posted or finished until the hosted service has
    // confirmed it takes this app's purchases, and for which account.
    final config = await _configAnswer();
    if (config == null) {
      _log.info('iap config not confirmed, ${p.productId} left unfinished');
      _retryLater(p);
      return;
    }
    if (!config.canDeliver) {
      // No account to apply it to under this company: said, never retried
      // on a timer (asking again would get the same answer).
      _log.info('iap config names no account here, ${p.productId} left');
      _emit(PurchaseActivityKind.retryLater, p);
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
    // account): not this user's to apply, and not ours to finish. Only when
    // the config names this account's token: without one there is nothing to
    // compare, and the server checks the token itself (`token_mismatch`) —
    // skipping it would never deliver a renewal (purchases_enabled gates only
    // the sale, never a delivery).
    final token = purchaseAccountToken(p, store);
    final mine = config.appAccountToken;
    if (token != null &&
        mine != null &&
        token.toLowerCase() != mine.toLowerCase()) {
      _log.info('${p.productId} was bought for another account, left alone');
      _emit(PurchaseActivityKind.retryLater, p);
      return;
    }
    // The hosted endpoint requires `inapp_transaction_id`. Play can hand over
    // a purchase with no order id yet: never posted (it would be a 422) and
    // never acknowledged, so Play refunds it if it never gets one; a later
    // hand-over may carry it.
    final purchaseId = inAppTransactionId(p);
    if (key == null || purchaseId == null || purchaseId.isEmpty) {
      final logKey = p.serverVerificationData.isNotEmpty
          ? p.serverVerificationData
          : p.productId;
      if (_loggedNoId.add(logKey)) {
        _log.warning('no transaction id for ${p.productId}, left unfinished');
      }
      _retryLater(p);
      return;
    }
    if (!_inFlight.add(key)) return;
    // Refused before for this user: re-posted (a sign-in, Restore) without a
    // word, so the refusal is said once.
    final refusedKey = '$owner|$key';
    final quiet = _refused.contains(refusedKey);
    if (!quiet) _emit(PurchaseActivityKind.delivering, p);
    final verification = p.serverVerificationData;
    try {
      await _apiClient.postJson(
        kSubscriptionPath,
        body: {
          'inapp_transaction_id': purchaseId,
          'key': config.accountKey,
          'plan': planSlugOf(p.productId),
          if (verification.isNotEmpty) 'verification_data': verification,
          'source': store.wireName,
          'bundle_id': kStoreBundleId,
        },
      );
    } catch (e) {
      _inFlight.remove(key);
      if (isPermanentRejection(e)) {
        _log.warning('subscription refused (${rejectionReason(e)}): $e');
        // StoreKit hands an unfinished transaction back on every launch and
        // refuses a new purchase of the same product while it waits, so
        // Apple's is finished once the refusal is final. Google's stays
        // unacknowledged: Play refunds it.
        if (store == PurchaseStore.appStore && finishesOnRejection(e)) {
          _refused.remove(refusedKey);
          _answered[key] = false;
          await _finishAnswered(p, key);
        } else {
          _refused.add(refusedKey);
        }
        if (quiet) {
          _log.info('${p.productId} refused again, already said');
          return;
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
    _inFlight.remove(key);
    _refused.remove(refusedKey);
    _answered[key] = false;
    // The server has it: finish it even if the refresh below fails.
    await _finishAnswered(p, key);
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
