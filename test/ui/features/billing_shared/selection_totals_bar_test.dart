import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/api/vendor_api_model.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/vendor.dart';
import 'package:admin/data/repositories/client_repository.dart';
import 'package:admin/data/repositories/vendor_repository.dart';
import 'package:admin/data/repositories/group_setting_repository.dart';
import 'package:admin/domain/billing/selection_totals.dart';
import 'package:admin/ui/features/billing_shared/selection_totals_bar.dart';

import '../../../_localization_helper.dart';

Decimal _d(String v) => Decimal.parse(v);

SelectionTotalsRow _row(
  String clientId,
  String amount, {
  String taxes = '0',
  String? balance,
}) => SelectionTotalsRow(
  clientId: clientId,
  amount: _d(amount),
  taxes: _d(taxes),
  balance: balance == null ? null : _d(balance),
);

class _FakeClients implements ClientRepository {
  _FakeClients(this.byId);
  final Map<String, Client> byId;
  @override
  Stream<Client?> watch({required String companyId, required String id}) =>
      Stream<Client?>.value(byId[id]);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeVendors implements VendorRepository {
  _FakeVendors(this.byId);
  final Map<String, Vendor> byId;
  @override
  Stream<Vendor?> watch({required String companyId, required String id}) =>
      Stream<Vendor?>.value(byId[id]);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeGroups implements GroupSettingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeServices implements Services {
  _FakeServices(this.clients, [VendorRepository? vendors])
    : vendors = vendors ?? _FakeVendors(const {});
  @override
  final ClientRepository clients;
  @override
  final VendorRepository vendors;
  @override
  final GroupSettingRepository groupSettings = _FakeGroups();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('selectionTotals', () {
    String? usd(String _) => '1';

    test('adds amount, net (amount less taxes) and balance', () {
      final totals = selectionTotals([
        _row('a', '110', taxes: '10', balance: '110'),
        _row('b', '55', taxes: '5', balance: '20'),
      ], usd)!;
      final t = totals.single;
      expect(t.count, 2);
      expect(t.amount, _d('165'));
      expect(t.net, _d('150'));
      expect(t.balance, _d('130'));
    });

    test('never adds two currencies together', () {
      final totals = selectionTotals([
        _row('us', '100'),
        _row('eu', '40'),
        _row('us', '1'),
      ], (c) => c == 'eu' ? '3' : '1')!;
      expect(totals.map((t) => t.currencyId), ['1', '3']);
      expect(totals.first.amount, _d('101'));
      expect(totals.last.amount, _d('40'));
    });

    test('no total while a client\'s currency is unknown', () {
      expect(
        selectionTotals([
          _row('a', '1'),
          _row('b', '2'),
        ], (c) => c == 'a' ? '1' : null),
        isNull,
      );
    });

    test('a vendor id never collides with a client id', () {
      // A purchase order totals in its vendor's currency; the same hashed id
      // naming a client must not answer for it.
      final keys = <String>[];
      selectionTotals(
        [
          _row('x', '1'),
          SelectionTotalsRow(vendorId: 'x', amount: _d('2'), taxes: _d('0')),
        ],
        (k) {
          keys.add(k);
          return '1';
        },
      );
      expect(keys, ['x', '${kVendorPartyPrefix}x']);
    });

    test('no balance when no row has one', () {
      expect(selectionTotals([_row('a', '9')], usd)!.single.balance, isNull);
    });
  });

  testWidgets('the bar prints one line of figures per currency', (
    tester,
  ) async {
    final services = _FakeServices(
      _FakeClients({
        'us': Client.fromApi(const ClientApi(id: 'us', currencyId: '1')),
        'eu': Client.fromApi(const ClientApi(id: 'eu', currencyId: '3')),
      }),
    );
    await tester.pumpWidget(
      Provider<Services>.value(
        value: services,
        child: MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: SelectionTotalsBar(
              companyId: 'co',
              rows: [
                _row('us', '110', taxes: '10', balance: '110'),
                _row('eu', '40', balance: '0'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // No formatter: raw decimals, one Wrap per currency.
    expect(find.text('Amount  110', findRichText: true), findsOneWidget);
    expect(find.text('Net Amount  100', findRichText: true), findsOneWidget);
    expect(find.text('Balance  110', findRichText: true), findsOneWidget);
    expect(find.text('Amount  40', findRichText: true), findsOneWidget);
    expect(find.byType(Wrap), findsNWidgets(2));
  });

  testWidgets('purchase orders total in their vendor\'s currency, and a vendor '
      'naming none is in the company\'s', (tester) async {
    final services = _FakeServices(
      _FakeClients(const {}),
      _FakeVendors({
        'eu': Vendor.fromApi(const VendorApi(id: 'eu', currencyId: '3')),
        'home': Vendor.fromApi(const VendorApi(id: 'home')),
      }),
    );
    await tester.pumpWidget(
      Provider<Services>.value(
        value: services,
        child: MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: SelectionTotalsBar(
              companyId: 'co',
              rows: [
                SelectionTotalsRow(
                  vendorId: 'eu',
                  amount: _d('40'),
                  taxes: _d('0'),
                ),
                SelectionTotalsRow(
                  vendorId: 'home',
                  amount: _d('7'),
                  taxes: _d('0'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Amount  40', findRichText: true), findsOneWidget);
    expect(find.text('Amount  7', findRichText: true), findsOneWidget);
    expect(find.byType(Wrap), findsNWidgets(2));
  });
}
