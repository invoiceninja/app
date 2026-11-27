import 'dart:convert';

import 'package:admin/app/services.dart';
import 'package:admin/app/terminal_controller.dart';
import 'package:admin/data/models/domain/invoice_status.dart';
import 'package:admin/domain/terminal/terminal_eligibility.dart';
import 'package:admin/ui/core/detail/entity_quick_actions.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';
import 'package:admin/ui/features/invoices/widgets/invoice_actions.dart';
import 'package:admin/ui/features/settings/widgets/card_reader_section.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_icon.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../shell/_shell_test_helpers.dart';

/// Where the card action shows outside the collect screen — the invoice's
/// menu, its first quick tile, Device Settings' card reader row — named and
/// drawn as Apple requires on iOS (App Review 5.4, 5.5), and as before on
/// Android (docs/in-person-payments.md).
void main() {
  final invoice = emptyInvoice().copyWith(
    id: 'inv_1',
    number: '0042',
    statusId: InvoiceStatus.sent,
    amount: Decimal.fromInt(100),
    balance: Decimal.fromInt(100),
  );

  const bridge = MethodChannel('invoice_ninja/stripe_terminal');
  var blocker = '';

  setUp(() {
    blocker = '';
    TerminalController.lastKnownDevice = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
          if (call.method != 'deviceSupport') return null;
          return <String, Object?>{
            'tapToPay': blocker.isEmpty,
            'bluetooth': true,
            'nfcEnabled': true,
            'locationServicesEnabled': true,
            'tapToPayBlocker': blocker.isEmpty ? null : blocker,
          };
        });
  });
  tearDown(() {
    TerminalController.lastKnownDevice = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, null);
  });

  final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  Future<Services> fixture(
    WidgetTester tester, {
    http.Client? httpClient,
  }) async {
    final f = await buildFixture(
      companies: [
        FakeCompany(id: 'co1', name: 'Acme', isAdmin: true, isOwner: true),
      ],
      httpClient: httpClient,
    );
    addTearDown(f.dispose);
    await f.services.terminal.refreshDevice();
    return f.services;
  }

  Future<(List<_CardItem>, List<EntityQuickAction<InvoiceAction>>)> actions(
    WidgetTester tester,
  ) async {
    final services = await fixture(tester);
    late List<_CardItem> items;
    late List<EntityQuickAction<InvoiceAction>> quick;
    await tester.pumpWidget(
      wrapWithShell(
        services,
        Builder(
          builder: (context) {
            items = [
              for (final i in InvoiceActions.itemsFor(
                context,
                invoice,
                (_) {},
                cardPayment: TerminalAvailability.available,
              ))
                if (i.kind == InvoiceAction.collectCardPayment)
                  _CardItem(
                    label: i.label,
                    icon: i.icon,
                    drawn: i.iconWidget(20),
                  ),
            ];
            quick = InvoiceActions.quickItemsFor(
              context,
              invoice,
              (_) {},
              hasPdfPane: false,
              cardPayment: TerminalAvailability.available,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    return (items, quick);
  }

  testWidgets('iOS: the menu item and the first quick tile are Apple\'s name '
      'and symbol, never "Card" or the contactless icon', (tester) async {
    final (items, quick) = await actions(tester);
    expect(items.single.label, 'Tap to Pay on iPhone');
    expect(items.single.drawn, isA<TapToPayIcon>());
    expect(items.single.icon, isNot(Icons.contactless_outlined));
    expect(quick.first.item.kind, InvoiceAction.collectCardPayment);
    expect(quick.first.shortLabel, 'Tap to Pay on iPhone');
    expect(quick.first.item.iconWidget(20), isA<TapToPayIcon>());
  }, variant: iOS);

  testWidgets('Android is unchanged: "Collect card payment", "Card" and the '
      'contactless icon', (tester) async {
    final (items, quick) = await actions(tester);
    expect(items.single.label, 'Collect card payment');
    expect(items.single.icon, Icons.contactless_outlined);
    expect(items.single.drawn, isA<Icon>());
    expect(quick.first.shortLabel, 'Card');
  }, variant: android);

  /// The server's `terminal/config`: one card-present Stripe gateway, or
  /// [status] with the server's own body for a server without the route.
  http.Client server({int status = 200}) => MockClient((request) async {
    if (request.url.path != '/api/v1/terminal/config') {
      throw http.ClientException('offline (test fixture)');
    }
    if (status != 200) {
      return http.Response(
        jsonEncode({'message': 'Route does not exist'}),
        status,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({
        'enabled': true,
        'plan_ok': true,
        'gateways': [
          {
            'company_gateway_id': 'cg_1',
            'label': 'Stripe',
            'account_country': 'us',
            'default_currency': 'USD',
            'card_payments_active': true,
            'locations': [
              {'id': 'tml_1', 'display_name': 'Main'},
            ],
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  Future<void> section(WidgetTester tester, {int status = 200}) async {
    final services = await fixture(tester, httpClient: server(status: status));
    await tester.pumpWidget(
      wrapWithShell(
        services,
        const SingleChildScrollView(child: CardReaderSection()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a server without card payments (404) gets no card at all, '
      'not one saying it couldn\'t check', (tester) async {
    await section(tester, status: 404);
    expect(find.text('Card readers'), findsNothing);
    expect(find.textContaining('Tap to Pay'), findsNothing);
    expect(find.textContaining('Couldn'), findsNothing);
  }, variant: android);

  testWidgets('iOS: the card reader row has Apple\'s name and symbol, the '
      'words settings search reveals', (tester) async {
    await section(tester);
    expect(find.text('Tap to Pay on iPhone'), findsOneWidget);
    expect(find.byType(TapToPayIcon), findsOneWidget);
    expect(find.byIcon(Icons.contactless_outlined), findsNothing);
    expect(find.textContaining('Android'), findsNothing);
  }, variant: iOS);

  testWidgets('iOS before general availability (no entitlement): no row and '
      'no word of Tap to Pay on iPhone', (tester) async {
    blocker = 'entitlementMissing';
    await section(tester);
    expect(find.byType(TapToPayIcon), findsNothing);
    expect(find.textContaining('Tap to Pay'), findsNothing);
    expect(find.text('Card readers'), findsOneWidget);
  }, variant: iOS);

  testWidgets('Android: "Tap to Pay" with the contactless icon, as before', (
    tester,
  ) async {
    await section(tester);
    expect(find.text('Tap to Pay'), findsOneWidget);
    expect(find.byIcon(Icons.contactless_outlined), findsOneWidget);
    expect(find.byType(TapToPayIcon), findsNothing);
  }, variant: android);
}

/// What the menu draws for the card action.
class _CardItem {
  _CardItem({required this.label, required this.icon, required this.drawn});

  final String label;
  final IconData icon;
  final Widget drawn;
}
