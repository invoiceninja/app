import 'package:decimal/decimal.dart';

import 'package:admin/data/models/value/money.dart';

/// The in-person card payment endpoints' answers (docs/in-person-payments.md).
///
/// Read online and never stored: the server owns every figure, so these are
/// plain values, not Drift rows. Money is a [Decimal] as the server sent it —
/// sums like `amount + fee_gross` arrive as PHP floats (`103.30000000000001`),
/// so a figure is shown through `Formatter`, which rounds, and compared only
/// in minor units ([TerminalFinalize.amountMinor]).

String _string(Object? raw) => raw == null ? '' : '$raw';

bool _bool(Object? raw) => raw == true || raw == 1 || raw == '1';

Map<String, dynamic> _map(Object? raw) =>
    raw is Map<String, dynamic> ? raw : const {};

/// `GET /terminal/config`: whether this company can take a card, and with
/// which Stripe gateways.
class TerminalConfig {
  const TerminalConfig({
    required this.enabled,
    required this.planOk,
    required this.gateways,
    this.setupGateways = const [],
    this.companyCountry = '',
    this.declineReceipts = true,
  });

  factory TerminalConfig.fromJson(Map<String, dynamic> json) => TerminalConfig(
    enabled: _bool(json['enabled']),
    planOk: _bool(json['plan_ok']),
    gateways: [
      for (final g in json['gateways'] is List ? json['gateways'] as List : [])
        if (g is Map<String, dynamic>) TerminalGatewayConfig.fromJson(g),
    ],
    // Both are newer than the route: an older server leaves them out.
    setupGateways: [
      for (final g
          in json['setup_gateways'] is List
              ? json['setup_gateways'] as List
              : [])
        if (g is Map<String, dynamic>) TerminalSetupGateway.fromJson(g),
    ],
    companyCountry: _string(json['company_country']).toUpperCase(),
    declineReceipts: json.containsKey('setup_gateways'),
  );

  /// The platform switch (`NINJA_TERMINAL_ENABLED`) — also the release flag
  /// for Tap to Pay on iPhone.
  final bool enabled;

  /// False on a hosted plan below Pro.
  final bool planOk;

  /// The Stripe gateways with Card present on: the only ones a card is ever
  /// taken on.
  final List<TerminalGatewayConfig> gateways;

  /// Stripe gateways in a Tap to Pay country with Card present still off
  /// (`setup_gateways`): an admin can turn it on, from the iPhone. Never
  /// collected on.
  final List<TerminalSetupGateway> setupGateways;

  /// The company's country (ISO 3166 alpha-2, upper case), for a company
  /// with no Stripe gateway yet; '' from a server that doesn't say.
  final String companyCountry;

  /// Whether the server can email a decline receipt. It learned that in the
  /// release that added `setup_gateways`, so the key's presence is the
  /// signal: an older server's `receipt` refuses a declined collection, and
  /// "Send decline receipt" stays hidden there.
  final bool declineReceipts;

  /// The gateway a collection uses: the first one Stripe lets take cards.
  TerminalGatewayConfig? get usableGateway {
    for (final g in gateways) {
      if (g.cardPaymentsActive) return g;
    }
    return null;
  }

  /// The gateway that can charge in [currencyCode] (ISO 4217, any case):
  /// Stripe Terminal charges only in the account's own currency, and the
  /// server refuses any other (`unsupported_currency`). With [currencyCode]
  /// unknown, [usableGateway]; null when no gateway takes that currency.
  TerminalGatewayConfig? gatewayFor(String? currencyCode) {
    final code = currencyCode?.toLowerCase() ?? '';
    if (code.isEmpty) return usableGateway;
    for (final g in gateways) {
      if (g.cardPaymentsActive && g.defaultCurrency == code) return g;
    }
    return null;
  }
}

class TerminalGatewayConfig {
  const TerminalGatewayConfig({
    required this.companyGatewayId,
    required this.label,
    required this.livemode,
    required this.accountCountry,
    required this.defaultCurrency,
    required this.cardPaymentsActive,
    required this.surcharge,
    required this.locations,
  });

  factory TerminalGatewayConfig.fromJson(Map<String, dynamic> json) =>
      TerminalGatewayConfig(
        companyGatewayId: _string(json['company_gateway_id']),
        label: _string(json['label']),
        livemode: _bool(json['livemode']),
        accountCountry: _string(json['account_country']).toUpperCase(),
        defaultCurrency: _string(json['default_currency']).toLowerCase(),
        cardPaymentsActive: _bool(json['card_payments_active']),
        surcharge: TerminalSurchargeConfig.fromJson(_map(json['surcharge'])),
        locations: [
          for (final l
              in json['locations'] is List ? json['locations'] as List : [])
            if (l is Map<String, dynamic>) TerminalLocation.fromJson(l),
        ],
      );

  final String companyGatewayId;
  final String label;

  /// False for a Stripe test-mode account: the screen shows TEST MODE, and
  /// only then may a simulated reader be used.
  final bool livemode;

  /// ISO 3166 alpha-2, upper case.
  final String accountCountry;

  /// ISO 4217, lower case, as Stripe reports it.
  final String defaultCurrency;
  final bool cardPaymentsActive;
  final TerminalSurchargeConfig surcharge;
  final List<TerminalLocation> locations;
}

/// A Stripe gateway with Card present off (`setup_gateways`): enough to
/// offer turning it on, nothing to collect with.
class TerminalSetupGateway {
  const TerminalSetupGateway({
    required this.companyGatewayId,
    required this.label,
    required this.accountCountry,
    this.cardPaymentsActive = true,
  });

  factory TerminalSetupGateway.fromJson(Map<String, dynamic> json) =>
      TerminalSetupGateway(
        companyGatewayId: _string(json['company_gateway_id']),
        label: _string(json['label']),
        accountCountry: _string(json['account_country']).toUpperCase(),
        // Optional: a server that doesn't say is taken as active.
        cardPaymentsActive:
            json['card_payments_active'] == null ||
            _bool(json['card_payments_active']),
      );

  final String companyGatewayId;
  final String label;

  /// ISO 3166 alpha-2, upper case.
  final String accountCountry;

  /// Stripe lets the account take cards; false while Stripe is still
  /// reviewing a just-connected account (approval pending).
  final bool cardPaymentsActive;
}

class TerminalSurchargeConfig {
  const TerminalSurchargeConfig({
    required this.allowed,
    required this.reason,
    required this.feePercent,
    required this.feeAmount,
  });

  factory TerminalSurchargeConfig.fromJson(Map<String, dynamic> json) =>
      TerminalSurchargeConfig(
        allowed: _bool(json['allowed']),
        reason: json['reason'] == null ? null : _string(json['reason']),
        feePercent: parseMoney(json['fee_percent']),
        feeAmount: parseMoney(json['fee_amount']),
      );

  final bool allowed;

  /// Why not: `not_configured`, `not_acknowledged`, `region`,
  /// `adjust_fee_percent`, … (an invoice-specific reason only comes with a
  /// quote).
  final String? reason;
  final Decimal feePercent;
  final Decimal feeAmount;

  /// An admin can switch it on by acknowledging the rules.
  bool get needsAcknowledgement => reason == 'not_acknowledged';
}

class TerminalLocation {
  const TerminalLocation({required this.id, required this.displayName});

  factory TerminalLocation.fromJson(Map<String, dynamic> json) =>
      TerminalLocation(
        id: _string(json['id']),
        displayName: _string(json['display_name']),
      );

  final String id;
  final String displayName;
}

/// `GET /invoices/{id}/terminal/quote`: what the customer will be asked for.
class TerminalQuote {
  const TerminalQuote({
    required this.amount,
    required this.feeGross,
    required this.total,
    required this.surchargeAllowed,
    required this.reason,
    this.currencyId = '',
  });

  factory TerminalQuote.fromJson(Map<String, dynamic> json) => TerminalQuote(
    amount: parseMoney(json['amount']),
    feeGross: parseMoney(json['fee_gross']),
    total: parseMoney(json['total']),
    surchargeAllowed: _bool(json['surcharge_allowed']),
    reason: json['reason'] == null ? null : _string(json['reason']),
    currencyId: _string(json['currency_id']),
  );

  final Decimal amount;
  final Decimal feeGross;
  final Decimal total;
  final bool surchargeAllowed;
  final String? reason;

  /// The currency the card is charged in — the client's, resolved by the
  /// server through its group and the company. Every figure on the screen
  /// is shown in it; '' from a server that didn't say.
  final String currencyId;
}

/// `POST /invoices/{id}/terminal/payment_intents`: the collection's
/// PaymentIntent. [clientSecret] is the only secret the app holds; it never
/// leaves memory and [toString] leaves it out.
class TerminalIntent {
  const TerminalIntent({
    required this.collectionId,
    required this.paymentIntentId,
    required this.clientSecret,
    required this.amount,
    required this.feeGross,
    required this.total,
    required this.currency,
    required this.livemode,
  });

  factory TerminalIntent.fromJson(Map<String, dynamic> json) => TerminalIntent(
    collectionId: _string(json['collection_id']),
    paymentIntentId: _string(json['payment_intent_id']),
    clientSecret: _string(json['client_secret']),
    amount: parseMoney(json['amount']),
    feeGross: parseMoney(json['fee_gross']),
    total: parseMoney(json['total']),
    currency: _string(json['currency']).toLowerCase(),
    livemode: _bool(json['livemode']),
  );

  final String collectionId;
  final String paymentIntentId;
  final String clientSecret;
  final Decimal amount;
  final Decimal feeGross;
  final Decimal total;
  final String currency;
  final bool livemode;

  @override
  String toString() => 'TerminalIntent($paymentIntentId)';
}

/// `POST /terminal/payment_intents/{pi}/finalize`, after every read: whether
/// to read the card again, and the amount a confirm must match.
class TerminalFinalize {
  const TerminalFinalize({
    required this.path,
    required this.recollect,
    required this.funding,
    required this.amount,
    required this.amountMinor,
    required this.surcharge,
  });

  factory TerminalFinalize.fromJson(Map<String, dynamic> json) =>
      TerminalFinalize(
        path: _string(json['path']),
        recollect: _bool(json['recollect']),
        funding: json['funding'] == null ? null : _string(json['funding']),
        amount: parseMoney(json['amount']),
        amountMinor: switch (json['amount_minor']) {
          final int v => v,
          final num v => v.round(),
          final String v => int.tryParse(v) ?? -1,
          _ => -1,
        },
        surcharge: parseMoney(json['surcharge']),
      );

  /// `recollect` when the surcharge raised the PaymentIntent, else `none`.
  final String path;

  /// The PaymentIntent changed: read the card again before confirming.
  final bool recollect;
  final String? funding;
  final Decimal amount;

  /// The PaymentIntent's amount in the currency's minor units; -1 when the
  /// server sent none, which no read can match.
  final int amountMinor;

  /// The surcharge kept on this read, 0 when none.
  final Decimal surcharge;
}

/// `POST /terminal/payment_intents/{pi}/complete` (and `cancel`): what the
/// server recorded.
class TerminalCompletion {
  const TerminalCompletion({
    required this.status,
    required this.paymentId,
    required this.applied,
    required this.unapplied,
    required this.invoiceBalance,
    required this.brand,
    required this.last4,
    required this.receiptUrl,
    this.declined = false,
  });

  factory TerminalCompletion.fromJson(Map<String, dynamic> json) =>
      TerminalCompletion(
        status: _string(json['status']),
        paymentId: _string(json['payment_id']),
        applied: parseMoney(json['applied']),
        unapplied: parseMoney(json['unapplied']),
        invoiceBalance: json['invoice_balance'] == null
            ? null
            : parseMoney(json['invoice_balance']),
        brand: _string(json['brand']),
        last4: _string(json['last4']),
        receiptUrl: _string(json['receipt_url']),
        // Absent on a server from before decline answers: not declined.
        declined: json['declined'] == true,
      );

  /// `recorded`, `unapplied`, `processing`, `canceled`, `failed`,
  /// `orphaned`, `rejected`, or a Stripe PaymentIntent status.
  final String status;
  final String paymentId;
  final Decimal applied;
  final Decimal unapplied;
  final Decimal? invoiceBalance;
  final String brand;
  final String last4;
  final String receiptUrl;

  /// The card presented last was declined: the PaymentIntent still waits for
  /// another card ([status] stays Stripe's `requires_payment_method`), and
  /// [brand] / [last4] are that card's. Never why it was declined.
  final bool declined;

  bool get isRecorded => status == 'recorded' || status == 'unapplied';
}
