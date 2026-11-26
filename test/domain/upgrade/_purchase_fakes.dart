// Fakes shared by the in-app purchase tests: the store SDK, the API client
// and the auth repository, as `PurchaseDelivery` / `PurchaseService` see them.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/api_client.dart';

/// A UUID the hosted config hands out as `app_account_token`.
const kTestAccountToken = '6f1c2a54-9d0e-5b7f-8a3c-1e2d3f4a5b6c';

/// A trimmed but realistic `Transaction.jsonRepresentation` payload — the
/// StoreKit 2 value the plugin surfaces as `localVerificationData`.
String appleTransactionJson({
  Object? originalTransactionId = '2000000111111',
  String? appAccountToken,
  Map<String, Object?> extra = const {},
}) {
  return jsonEncode({
    'transactionId': '2000000999999',
    if (originalTransactionId != null)
      'originalTransactionId': originalTransactionId,
    'appAccountToken': ?appAccountToken,
    ...extra,
    'bundleId': 'com.invoiceninja.admin',
    'productId': 'pro_plan',
    'purchaseDate': 1751000000000,
    'type': 'Auto-Renewable Subscription',
    'environment': 'Production',
  });
}

/// A paid StoreKit 2 purchase, as the purchase stream hands it over.
/// [transactionId] is this one transaction's id; a renewal or a second
/// purchase has its own.
StorePurchase applePurchase({
  String productId = 'pro_plan',
  StorePurchaseStatus status = StorePurchaseStatus.purchased,
  String? appAccountToken,
  Map<String, Object?> extra = const {},
  String transactionId = '2000000999999',
}) => StorePurchase(
  productId: productId,
  status: status,
  purchaseId: transactionId,
  localVerificationData: appleTransactionJson(
    appAccountToken: appAccountToken,
    extra: extra,
  ),
  serverVerificationData: 'eyJhbGciOiJFUzI1NiJ9.apple-jws.sig',
  // StoreKit 2 marks only a `purchased` transaction finishable.
  pendingCompletePurchase: status == StorePurchaseStatus.purchased,
);

/// A paid Play purchase, as the purchase stream hands it over.
StorePurchase googlePurchase({
  String productId = 'pro_plan',
  StorePurchaseStatus status = StorePurchaseStatus.purchased,
  bool acknowledged = false,
  String? orderId = 'GPA.3123-4567-8901-23456',
  String? obfuscatedAccountId,
}) => StorePurchase(
  productId: productId,
  status: status,
  purchaseId: orderId,
  localVerificationData: jsonEncode({
    'orderId': ?orderId,
    'obfuscatedAccountId': ?obfuscatedAccountId,
  }),
  serverVerificationData: 'play-purchase-token',
  pendingCompletePurchase: !acknowledged,
);

/// The store SDK — `implements`, so the real `InAppPurchase.instance` is
/// never touched.
class FakeBilling implements StoreBilling {
  final purchases = StreamController<List<StorePurchase>>.broadcast();
  final completed = <StorePurchase>[];
  final bought = <(StoreProduct, String?)>[];
  int restores = 0;
  int streamListens = 0;

  /// What [unfinishedPurchases] answers — the launch sweep.
  List<StorePurchase> unfinished = const [];

  /// What [activeSubscriptionProductIds] answers.
  Set<String> entitlements = const {};

  /// Thrown by [buyNonConsumable] when set — a purchase that never starts.
  Object? buyError;

  List<StoreProduct> products = const [
    StoreProduct(
      id: 'pro_plan',
      title: 'Pro',
      description: 'Pro plan',
      price: r'$12.00',
    ),
    StoreProduct(
      id: 'enterprise_plan_annual_5',
      title: 'Enterprise (5 users)',
      description: '',
      price: r'$180.00',
    ),
  ];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Stream<List<StorePurchase>> get purchaseStream {
    streamListens++;
    return purchases.stream;
  }

  @override
  Future<StoreProductQuery> queryProducts(Set<String> ids) async {
    queried.add(ids);
    return StoreProductQuery(products: products);
  }

  /// Every id set [queryProducts] was asked for, in order.
  final List<Set<String>> queried = [];

  @override
  Future<void> buyNonConsumable(
    StoreProduct product, {
    String? applicationUserName,
  }) async {
    final error = buyError;
    if (error != null) throw error;
    bought.add((product, applicationUserName));
  }

  @override
  Future<List<StorePurchase>> unfinishedPurchases() async => unfinished;

  @override
  Future<Set<String>> activeSubscriptionProductIds() async => entitlements;

  @override
  Future<void> restorePurchases() async => restores++;

  /// What [completePurchase] answers — false is Play refusing the
  /// acknowledgement.
  bool completeResult = true;

  @override
  Future<bool> completePurchase(StorePurchase purchase) async {
    completed.add(purchase);
    return completeResult;
  }
}

/// The retry timers `PurchaseDelivery` schedules, fired by hand: the test
/// clock (`fake_async` is not a dependency).
class FakeTimers {
  final scheduled = <(Duration, void Function())>[];

  Timer call(Duration d, void Function() callback) {
    scheduled.add((d, callback));
    return _FakeTimer();
  }

  List<Duration> get delays => [for (final (d, _) in scheduled) d];

  /// Fires the most recent timer.
  void fireLast() => scheduled.last.$2();
}

class _FakeTimer implements Timer {
  bool _active = true;

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

class FakeApi implements ApiClient {
  final posts = <(String, Map<String, dynamic>?)>[];

  /// Thrown by [postJson] when set — the server did not apply the purchase.
  Object? postError;

  /// Held by [postJson] until completed, when set — a request on the wire.
  Completer<void>? postGate;

  /// What `GET /api/admin/iap/config` answers; thrown when it is an error.
  Object? iapConfig = const {
    'purchases_enabled': true,
    'app_account_token': kTestAccountToken,
    'account_key': 'acct-key',
  };
  final gets = <String>[];

  /// Holds [getOne]'s answer, read when the request was made, until
  /// completed, when set: a config request on the wire.
  Completer<void>? getGate;

  @override
  Future<dynamic> getOne(String path) async {
    gets.add(path);
    final answer = iapConfig;
    await getGate?.future;
    if (answer is Exception) throw answer;
    return answer;
  }

  @override
  Future<dynamic> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool readOnly = false,
    bool requiresPassword = false,
    Duration? timeout,
    bool unauthorizedIsAnswer = false,
  }) async {
    posts.add((path, body));
    await postGate?.future;
    final error = postError;
    if (error != null) throw error;
    return {'message': 'ok'};
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// A hosted session. [userAccountKey] — the key of the signed-in user's own
/// account — defaults to [accountKey] (the active company's): the user is in
/// their own account.
AuthSession testSession({
  String accountKey = 'acct-key',
  String? userAccountKey,
  bool isHosted = true,
  String baseUrl = 'https://invoicing.co',
  String userId = 'me',
  String companyId = 'co',
}) => AuthSession(
  baseUrl: baseUrl,
  isHosted: isHosted,
  accountId: 'acct',
  accountKey: accountKey,
  userAccountKey: userAccountKey ?? accountKey,
  companies: const [],
  currentCompanyId: companyId,
  userId: userId,
);

class FakeAuth implements AuthRepository {
  FakeAuth([AuthSession? initial])
    : session = ValueNotifier<AuthSession?>(initial ?? testSession());

  int refreshes = 0;

  /// Thrown by [refresh] when set.
  Object? refreshError;

  @override
  final ValueNotifier<AuthSession?> session;

  @override
  Future<void> refresh({bool fullSync = false}) async {
    refreshes++;
    final error = refreshError;
    if (error != null) throw error;
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
