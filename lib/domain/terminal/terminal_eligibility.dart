import 'package:flutter/foundation.dart';

import 'package:admin/data/models/domain/invoice.dart';

/// Whether an invoice offers "Collect card payment", decided from plain
/// facts so every gate is testable (docs/in-person-payments.md). A leaf: no
/// services, no SDK.

/// Build-time switches, all on: `--dart-define=IN_CARD_PRESENT=false` removes
/// the feature, the other two remove one part of it.
const bool kCardPresentEnabled = bool.fromEnvironment(
  'IN_CARD_PRESENT',
  defaultValue: true,
);
const bool kCardPresentBluetooth = bool.fromEnvironment(
  'IN_CARD_PRESENT_BLUETOOTH',
  defaultValue: true,
);
const bool kCardPresentSurcharge = bool.fromEnvironment(
  'IN_CARD_PRESENT_SURCHARGE',
  defaultValue: true,
);

/// Account countries where Stripe offers Tap to Pay on Android, generally
/// available or in public preview (docs.stripe.com/terminal/payments/
/// setup-reader/tap-to-pay?platform=android, read 2026-11-10).
const Set<String> kTapToPayAndroidCountries = {
  'AT', 'AU', 'BE', 'CA', 'CH', 'DE', 'DK', 'FI', 'FR', 'GB', 'IE', //
  'IT', 'MY', 'NL', 'NO', 'NZ', 'PL', 'PT', 'SE', 'SG', 'US', //
  'BG', 'CY', 'CZ', 'EE', 'ES', 'GI', 'HK', 'HR', 'HU', 'JP', //
  'LI', 'LT', 'LU', 'LV', 'MT', 'MX', 'RO', 'SI', 'SK', //
};

/// Account countries where Stripe offers Tap to Pay on iPhone, generally
/// available or in public preview (docs.stripe.com/terminal/payments/
/// setup-reader/tap-to-pay?platform=ios, read 2026-11-15). Not the same as
/// Android's: no Gibraltar, and Liechtenstein and Malaysia only in preview.
const Set<String> kTapToPayIPhoneCountries = {
  'AT', 'AU', 'BE', 'CA', 'CH', 'CZ', 'DE', 'DK', 'ES', 'FI', 'FR', //
  'GB', 'IE', 'IT', 'LU', 'NL', 'NZ', 'PL', 'PT', 'SE', 'SG', 'US', //
  'BG', 'CY', 'EE', 'HK', 'HR', 'HU', 'JP', 'LI', 'LT', 'LV', 'MT', //
  'MX', 'MY', 'NO', 'RO', 'SI', 'SK', //
};

/// This is an iPhone (or an iPad, which Apple never lets take Tap to Pay):
/// where everything Apple's App Review asks of Tap to Pay on iPhone applies.
/// Android, desktop and web are unchanged by it.
bool isIPhonePlatform() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

enum TerminalAvailability {
  hidden,

  /// Shown, and opens the upgrade flow: a hosted plan below Pro.
  upgrade,
  available,
}

/// How the app may read a card here.
enum TerminalReaderChoice { tapToPay, bluetooth, none }

/// [tapToPayDevice]: this phone can do Tap to Pay. [iPhone]: it's an iPhone,
/// whose Tap to Pay countries differ from Android's. [readerUsed]: a
/// Bluetooth reader has been connected in this app before — the action isn't
/// offered to every phone that merely has Bluetooth.
///
/// [osUpdateRequired]: an iPhone on an iOS Apple wants updated before Tap to
/// Pay on iPhone. Its Bluetooth reader, once used, still takes the card; with
/// none, Tap to Pay on iPhone stays, and says to update (App Review 1.4).
TerminalReaderChoice terminalReaderChoice({
  required bool tapToPayDevice,
  required bool iPhone,
  required String accountCountry,
  required bool bluetoothDevice,
  required bool readerUsed,
  bool osUpdateRequired = false,
}) {
  final countries = iPhone
      ? kTapToPayIPhoneCountries
      : kTapToPayAndroidCountries;
  final bluetooth = kCardPresentBluetooth && bluetoothDevice && readerUsed;
  if (tapToPayDevice &&
      countries.contains(accountCountry) &&
      !(osUpdateRequired && bluetooth)) {
    return TerminalReaderChoice.tapToPay;
  }
  if (bluetooth) return TerminalReaderChoice.bluetooth;
  return TerminalReaderChoice.none;
}

/// [platformReady]: the build has the feature, this is the mobile app with
/// Stripe's SDK, and not the demo. [configEnabled] (the server's switch, and
/// the release flag) / [planOk] / [accountCountry] come from the server's
/// `terminal/config`; a null [accountCountry] means no usable gateway (or no
/// answer).
///
/// On an iPhone that can take Tap to Pay on iPhone ([tapToPayIPhone]) the
/// action is also offered before anything is set up, so the button is there
/// before Apple's terms (App Review 5.3): for a Stripe gateway in an iPhone
/// country whose Card present is still off ([setupCountries]), and — for an
/// admin of a company with no Stripe gateway at all ([noStripeGateway]) — a
/// company in an iPhone country ([companyCountry]).
TerminalAvailability terminalAvailability({
  required bool platformReady,
  required bool canCreatePayment,
  required Invoice invoice,
  required bool configEnabled,
  required bool planOk,
  required String? accountCountry,
  required TerminalReaderChoice Function(String accountCountry) readers,
  bool tapToPayIPhone = false,
  Iterable<String> setupCountries = const [],
  bool isAdmin = false,
  bool noStripeGateway = false,
  String companyCountry = '',
}) {
  if (!platformReady || !canCreatePayment) return TerminalAvailability.hidden;
  if (invoice.isDeleted ||
      invoice.isPaid ||
      invoice.isCancelled ||
      invoice.isReversed ||
      invoice.id.isEmpty ||
      invoice.id.startsWith('tmp_')) {
    return TerminalAvailability.hidden;
  }
  if (!configEnabled) return TerminalAvailability.hidden;
  final shown =
      (accountCountry != null &&
          readers(accountCountry) != TerminalReaderChoice.none) ||
      (tapToPayIPhone &&
          (setupCountries.any(kTapToPayIPhoneCountries.contains) ||
              (isAdmin &&
                  noStripeGateway &&
                  kTapToPayIPhoneCountries.contains(companyCountry))));
  if (!shown) return TerminalAvailability.hidden;
  return planOk ? TerminalAvailability.available : TerminalAvailability.upgrade;
}
