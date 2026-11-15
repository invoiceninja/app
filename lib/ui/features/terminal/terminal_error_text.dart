import 'package:store_services/store_services.dart';

import 'package:admin/data/services/terminal_server_error.dart';
import 'package:admin/domain/terminal/terminal_eligibility.dart';
import 'package:admin/ui/features/terminal/view_models/collect_card_payment_view_model.dart';

/// The words the counter sees for every way taking a card can go wrong
/// (docs/in-person-payments.md). One exhaustive switch per source, so a new
/// SDK code fails to compile until it has words; `terminal_error_text_test`
/// walks both.
///
/// Many of them name the feature through a `:name` placeholder — Apple's long
/// name on iOS, in the language the sentence renders in (`tapToPayNameFor`) —
/// so every lookup passes it. [iOS]: an iPhone or iPad gets its own words
/// wherever the shared ones talk about Android or "this phone".

/// The translation key for an SDK [code].
String terminalErrorKey(TerminalErrorCode code, {bool? iOS}) {
  final apple = iOS ?? isIPhonePlatform();
  return switch (code) {
    TerminalErrorCode.canceled => 'terminal_error_canceled',
    TerminalErrorCode.declined => 'terminal_error_declined',
    TerminalErrorCode.outcomeUnknown => 'terminal_checking_help',
    TerminalErrorCode.invalidState => 'terminal_error_invalid_state',
    TerminalErrorCode.timeout => 'terminal_error_timeout',
    TerminalErrorCode.cardNotRead => 'terminal_error_card_not_read',
    TerminalErrorCode.termsNotAccepted => 'terminal_error_terms_not_accepted',
    TerminalErrorCode.termsCanceled => 'terminal_error_terms_canceled',
    TerminalErrorCode.termsNeedsAppleAccount =>
      'terminal_error_terms_apple_account',
    TerminalErrorCode.termsFailed => 'terminal_error_terms_failed',
    TerminalErrorCode.unsupportedDevice ||
    TerminalErrorCode.entitlementMissing =>
      apple
          ? 'terminal_error_unsupported_device_ios'
          : 'terminal_error_unsupported_device',
    // App Review 1.4: an out-of-date iOS says to update it.
    TerminalErrorCode.unsupportedOs =>
      apple ? 'terminal_update_ios' : 'terminal_error_unsupported_os',
    TerminalErrorCode.debugNotSupported ||
    TerminalErrorCode.insecureEnvironment =>
      apple ? 'terminal_error_insecure_ios' : 'terminal_error_insecure',
    // Only Tap to Pay on iPhone meets these on iOS: an iPhone.
    TerminalErrorCode.deviceTampered =>
      apple
          ? 'terminal_error_device_tampered_ios'
          : 'terminal_error_device_tampered',
    TerminalErrorCode.pinUnavailable => 'terminal_error_pin_unavailable',
    TerminalErrorCode.passcodeNotEnabled =>
      apple ? 'terminal_error_passcode_ios' : 'terminal_error_passcode',
    TerminalErrorCode.phoneCallInProgress => 'terminal_error_phone_call',
    TerminalErrorCode.accountNotEnabled => 'terminal_error_account_not_enabled',
    TerminalErrorCode.permissionDenied =>
      apple ? 'terminal_error_permission_ios' : 'terminal_error_permission',
    TerminalErrorCode.locationServicesDisabled =>
      apple ? 'terminal_error_location_off_ios' : 'terminal_error_location_off',
    TerminalErrorCode.nfcDisabled => 'terminal_error_nfc_off',
    TerminalErrorCode.bluetoothOff => 'terminal_error_bluetooth_off',
    TerminalErrorCode.alreadyConnected ||
    TerminalErrorCode.readerBusy => 'terminal_error_reader_busy',
    TerminalErrorCode.readerDisconnected =>
      'terminal_error_reader_disconnected',
    TerminalErrorCode.updateRequired => 'terminal_error_update_required',
    TerminalErrorCode.batteryLow => 'terminal_error_battery_low',
    TerminalErrorCode.network => 'terminal_error_network',
    TerminalErrorCode.sessionExpired => 'terminal_error_session_expired',
    TerminalErrorCode.cancelFailed => 'terminal_error_cancel_failed',
    TerminalErrorCode.unknown => 'terminal_error_unknown',
  };
}

/// The translation key for a server `error_code`, or null for one the app
/// has no words for (the server's own message is shown then). [tapToPay]:
/// the screen is Tap to Pay on iPhone, so "Collect card payment" is named
/// as the action really is.
String? terminalServerErrorKey(String code, {bool tapToPay = false}) =>
    switch (code) {
      TerminalServerError.disabled => 'terminal_server_disabled',
      TerminalServerError.planRequired => 'terminal_server_plan_required',
      TerminalServerError.notEnabled => 'terminal_server_not_enabled',
      TerminalServerError.unsupportedCurrency =>
        'terminal_server_unsupported_currency',
      TerminalServerError.collectionOpen => 'terminal_server_collection_open',
      TerminalServerError.collectionClosed => 'terminal_error_unknown',
      TerminalServerError.alreadyPaid => 'terminal_server_already_paid',
      TerminalServerError.balanceChanged => 'terminal_server_balance_changed',
      TerminalServerError.amountMismatch => 'terminal_server_amount_mismatch',
      TerminalServerError.feeNotAllowed => 'terminal_server_fee_not_allowed',
      TerminalServerError.sendInvoiceFirst =>
        'terminal_server_send_invoice_first',
      TerminalServerError.notCollected => 'terminal_error_card_not_read',
      TerminalServerError.locationAddressRequired =>
        'terminal_server_location_address',
      'collection_starting' => 'terminal_collection_starting',
      'no_gateway_for_currency' => 'terminal_no_gateway_for_currency',
      'location_needs_admin' =>
        tapToPay
            ? 'terminal_ask_admin_location_ios'
            : 'terminal_ask_admin_location',
      // App Review 3.8.1: the same words as a connect the terms stopped.
      'tap_to_pay_ask_admin' => 'terminal_error_terms_not_accepted',
      'connect_stripe_first' => 'terminal_connect_stripe_first',
      _ => null,
    };

/// [tr] is `context.tr`; the result is a translated sentence, never a raw
/// SDK message. [name] fills `:name` for the key being rendered —
/// `(key) => tapToPayNameFor(context, key)`.
String terminalProblemText(
  CollectProblem problem,
  String Function(String key, [Map<String, String>? params]) tr, {
  required String Function(String key) name,
  bool? iOS,
  bool tapToPay = false,
}) {
  final server = problem.serverCode;
  if (server != null) {
    if (server == TerminalServerError.fieldErrors &&
        problem.message.isNotEmpty) {
      return problem.message;
    }
    final key = terminalServerErrorKey(server, tapToPay: tapToPay);
    if (key != null) {
      return switch (server) {
        TerminalServerError.collectionOpen when problem.data['age'] is! num =>
          tr('terminal_server_collection_open_no_age', {
            'user': '${problem.data['user'] ?? ''}'.trim().isEmpty
                ? tr('terminal_someone')
                : '${problem.data['user']}',
          }),
        TerminalServerError.collectionOpen => tr(key, {
          'user': '${problem.data['user'] ?? ''}'.trim().isEmpty
              ? tr('terminal_someone')
              : '${problem.data['user']}',
          'minutes': '${((problem.data['age'] as num? ?? 0) / 60).ceil()}',
        }),
        'no_gateway_for_currency' => tr(key, {
          'currency': '${problem.data['currency'] ?? ''}',
        }),
        // The server names the currency in its own message.
        TerminalServerError.unsupportedCurrency =>
          problem.message.isNotEmpty ? problem.message : tr(key),
        _ => tr(key, {'name': name(key)}),
      };
    }
    return problem.message.isNotEmpty
        ? problem.message
        : tr('terminal_error_unknown');
  }
  final code = problem.code;
  if (code != null) {
    final key = terminalErrorKey(code, iOS: iOS);
    return tr(key, {'name': name(key)});
  }
  return problem.message.isNotEmpty
      ? problem.message
      : tr('terminal_error_unknown');
}
