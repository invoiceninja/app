import 'package:admin/data/models/api/terminal_models.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/invoice_status.dart';
import 'package:admin/domain/terminal/terminal_eligibility.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sent = emptyInvoice().copyWith(
    id: 'inv_1',
    statusId: InvoiceStatus.sent,
  );

  TerminalAvailability availability({
    bool platformReady = true,
    bool canCreatePayment = true,
    Invoice? invoice,
    bool configEnabled = true,
    bool planOk = true,
    String? accountCountry = 'US',
    TerminalReaderChoice readers = TerminalReaderChoice.tapToPay,
  }) => terminalAvailability(
    platformReady: platformReady,
    canCreatePayment: canCreatePayment,
    invoice: invoice ?? sent,
    configEnabled: configEnabled,
    planOk: planOk,
    accountCountry: accountCountry,
    readers: (_) => readers,
  );

  test('offered on a payable invoice when everything lines up', () {
    expect(availability(), TerminalAvailability.available);
    expect(
      availability(invoice: sent.copyWith(statusId: InvoiceStatus.draft)),
      TerminalAvailability.available,
      reason: 'drafts are collected on site and marked sent by the server',
    );
    expect(
      availability(invoice: sent.copyWith(statusId: InvoiceStatus.partial)),
      TerminalAvailability.available,
    );
  });

  test('a hosted plan below Pro opens the upgrade instead', () {
    expect(availability(planOk: false), TerminalAvailability.upgrade);
  });

  test('every gate hides it', () {
    expect(availability(platformReady: false), TerminalAvailability.hidden);
    expect(availability(canCreatePayment: false), TerminalAvailability.hidden);
    expect(availability(configEnabled: false), TerminalAvailability.hidden);
    expect(availability(accountCountry: null), TerminalAvailability.hidden);
    expect(
      availability(readers: TerminalReaderChoice.none),
      TerminalAvailability.hidden,
    );
    for (final status in [
      InvoiceStatus.paid,
      InvoiceStatus.cancelled,
      InvoiceStatus.reversed,
    ]) {
      expect(
        availability(invoice: sent.copyWith(statusId: status)),
        TerminalAvailability.hidden,
        reason: '$status',
      );
    }
    expect(
      availability(invoice: sent.copyWith(isDeleted: true)),
      TerminalAvailability.hidden,
    );
    expect(
      availability(invoice: sent.copyWith(id: 'tmp_123')),
      TerminalAvailability.hidden,
      reason: 'the server has never seen it',
    );
  });

  group('Tap to Pay on iPhone before anything is set up', () {
    TerminalAvailability iPhone({
      bool tapToPayIPhone = true,
      List<String> setupCountries = const [],
      bool isAdmin = true,
      bool noStripeGateway = false,
      String companyCountry = '',
      bool configEnabled = true,
      bool planOk = true,
    }) => terminalAvailability(
      platformReady: true,
      canCreatePayment: true,
      invoice: sent,
      configEnabled: configEnabled,
      planOk: planOk,
      accountCountry: null,
      readers: (_) => TerminalReaderChoice.none,
      tapToPayIPhone: tapToPayIPhone,
      setupCountries: setupCountries,
      isAdmin: isAdmin,
      noStripeGateway: noStripeGateway,
      companyCountry: companyCountry,
    );

    test('an existing user: a Stripe gateway in an iPhone country with Card '
        'present still off shows the button before the terms', () {
      expect(iPhone(setupCountries: ['US']), TerminalAvailability.available);
      expect(
        iPhone(setupCountries: ['US'], isAdmin: false),
        TerminalAvailability.available,
        reason: 'a non-admin is told to ask an admin when pressing',
      );
      expect(
        iPhone(setupCountries: ['GI']),
        TerminalAvailability.hidden,
        reason: 'no Tap to Pay on iPhone in Gibraltar',
      );
      expect(
        iPhone(setupCountries: ['US'], planOk: false),
        TerminalAvailability.upgrade,
      );
    });

    test('a new admin: no Stripe gateway, a company in an iPhone country', () {
      expect(
        iPhone(noStripeGateway: true, companyCountry: 'GB'),
        TerminalAvailability.available,
      );
      expect(
        iPhone(noStripeGateway: true, companyCountry: 'GB', isAdmin: false),
        TerminalAvailability.hidden,
      );
      expect(
        iPhone(noStripeGateway: true, companyCountry: 'BR'),
        TerminalAvailability.hidden,
      );
      expect(
        iPhone(companyCountry: 'GB'),
        TerminalAvailability.hidden,
        reason: 'a Stripe gateway that can take no card is not a new user',
      );
      expect(
        iPhone(noStripeGateway: true),
        TerminalAvailability.hidden,
        reason: 'an older server that sends no company country',
      );
    });

    test('never on another platform, nor with the release flag off', () {
      expect(
        iPhone(tapToPayIPhone: false, setupCountries: ['US']),
        TerminalAvailability.hidden,
      );
      expect(
        iPhone(
          tapToPayIPhone: false,
          noStripeGateway: true,
          companyCountry: 'US',
        ),
        TerminalAvailability.hidden,
      );
      expect(
        iPhone(setupCountries: ['US'], configEnabled: false),
        TerminalAvailability.hidden,
      );
    });
  });

  group('terminal/config', () {
    test('setup gateways and the company country are read when sent', () {
      final config = TerminalConfig.fromJson(const {
        'enabled': true,
        'plan_ok': true,
        'gateways': <Object>[],
        'setup_gateways': [
          {
            'company_gateway_id': 'cg_9',
            'label': 'Stripe',
            'account_country': 'us',
          },
          'junk',
        ],
        'company_country': 'gb',
      });
      expect(config.setupGateways, hasLength(1));
      expect(config.setupGateways.single.companyGatewayId, 'cg_9');
      expect(config.setupGateways.single.accountCountry, 'US');
      expect(config.companyCountry, 'GB');
      expect(config.declineReceipts, isTrue);
    });

    test('an older server that leaves them out still parses', () {
      final config = TerminalConfig.fromJson(const {
        'enabled': true,
        'plan_ok': true,
        'gateways': <Object>[],
      });
      expect(config.setupGateways, isEmpty);
      expect(config.companyCountry, '');
      // It can't send a decline receipt either: the button stays hidden.
      expect(config.declineReceipts, isFalse);
    });
  });

  group('reader choice', () {
    TerminalReaderChoice choice({
      bool tapToPayDevice = true,
      bool iPhone = false,
      String country = 'US',
      bool bluetoothDevice = true,
      bool readerUsed = false,
    }) => terminalReaderChoice(
      tapToPayDevice: tapToPayDevice,
      iPhone: iPhone,
      accountCountry: country,
      bluetoothDevice: bluetoothDevice,
      readerUsed: readerUsed,
    );

    test('Tap to Pay on a capable phone in a supported country', () {
      expect(choice(), TerminalReaderChoice.tapToPay);
      expect(choice(country: 'GB'), TerminalReaderChoice.tapToPay);
    });

    test("an iPhone uses Stripe's iPhone countries, not Android's", () {
      expect(choice(iPhone: true), TerminalReaderChoice.tapToPay);
      expect(
        choice(iPhone: true, country: 'CZ'),
        TerminalReaderChoice.tapToPay,
      );
      expect(
        choice(country: 'GI'),
        TerminalReaderChoice.tapToPay,
        reason: 'Gibraltar has Tap to Pay on Android',
      );
      expect(
        choice(iPhone: true, country: 'GI'),
        TerminalReaderChoice.none,
        reason: 'but not on iPhone',
      );
    });

    test('an iOS Apple wants updated keeps a Bluetooth reader it has used; '
        'without one, Tap to Pay on iPhone stays and says to update', () {
      expect(
        terminalReaderChoice(
          tapToPayDevice: true,
          iPhone: true,
          accountCountry: 'US',
          bluetoothDevice: true,
          readerUsed: true,
          osUpdateRequired: true,
        ),
        TerminalReaderChoice.bluetooth,
      );
      expect(
        terminalReaderChoice(
          tapToPayDevice: true,
          iPhone: true,
          accountCountry: 'US',
          bluetoothDevice: true,
          readerUsed: false,
          osUpdateRequired: true,
        ),
        TerminalReaderChoice.tapToPay,
      );
      expect(
        choice(iPhone: true, readerUsed: true),
        TerminalReaderChoice.tapToPay,
        reason: 'a current iOS prefers Tap to Pay on iPhone',
      );
    });

    test('Bluetooth only once a reader has been used here — not on every '
        'phone that has Bluetooth', () {
      expect(choice(tapToPayDevice: false), TerminalReaderChoice.none);
      expect(
        choice(tapToPayDevice: false, readerUsed: true),
        TerminalReaderChoice.bluetooth,
      );
      expect(
        choice(country: 'BR', readerUsed: true),
        TerminalReaderChoice.bluetooth,
        reason: 'Tap to Pay is not offered in Brazil',
      );
      expect(
        choice(tapToPayDevice: false, bluetoothDevice: false, readerUsed: true),
        TerminalReaderChoice.none,
      );
    });
  });
}
