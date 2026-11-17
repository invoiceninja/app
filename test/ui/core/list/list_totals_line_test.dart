import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/models/value/currency.dart';
import 'package:admin/data/models/value/datetime_format.dart';
import 'package:admin/data/repositories/list_totals_repository.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/list_status_tabs.dart';
import 'package:admin/domain/list_totals.dart';
import 'package:admin/domain/sidebar_badge_modes.dart';
import 'package:admin/ui/core/list/entity_list_status_tabs.dart';
import 'package:admin/ui/core/list/list_totals_line.dart';
import 'package:admin/ui/core/widgets/trailing_if_room.dart';
import 'package:admin/utils/formatting.dart';

import '../../../_localization_helper.dart';

/// A money list's totals line (docs/entity-lists.md § A money list's totals
/// line): what it prints, when it hides, when it asks the server again — and,
/// on a wide list, its place at the end of the status strip's row, where it
/// shows only while it fits after the tabs.

Currency _currency(String id, String code, String symbol) => Currency(
  id: id,
  name: code,
  code: code,
  symbol: symbol,
  precision: 2,
  thousandSeparator: ',',
  decimalSeparator: '.',
  swapCurrencySymbol: false,
  exchangeRate: Decimal.one,
);

final _formatter = Formatter(
  settings: const CompanyFormatSettings(
    currencyId: '1',
    countryId: '840',
    dateFormatId: 'X',
    useCommaAsDecimalPlace: false,
    showCurrencyCode: false,
    enableMilitaryTime: false,
    locale: '',
  ),
  currencies: {
    '1': _currency('1', 'USD', r'$'),
    '2': _currency('2', 'GBP', '£'),
    '3': _currency('3', 'EUR', '€'),
  },
  countries: const {},
  dateFormats: const {'X': DatetimeFormat(id: 'X', format: 'd/MMM/yyyy')},
);

class _FakeSource implements ListTotalsSource {
  final totals = StreamController<CurrencyTotals?>.broadcast();
  final outbox = StreamController<int>.broadcast();
  final List<Duration?> refreshes = [];

  @override
  Stream<CurrencyTotals?> watch(EntityType type, String companyId) =>
      totals.stream;

  @override
  Future<void> refresh(
    EntityType type,
    String companyId, {
    Duration? maxAge,
  }) async => refreshes.add(maxAge);

  @override
  Stream<int> watchOutboxActive(String companyId) => outbox.stream;
}

Widget _app(Widget child, {double width = 800}) => MaterialApp(
  theme: buildInTheme(InTheme.light),
  localizationsDelegates: kTestLocalizationsDelegates,
  supportedLocales: kTestSupportedLocales,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

Map<String, Decimal> _dec(Map<String, String> m) => {
  for (final e in m.entries) e.key: Decimal.parse(e.value),
};

void main() {
  group('ListTotalsLine', () {
    late _FakeSource source;

    setUp(() => source = _FakeSource());

    Future<void> pump(WidgetTester tester, EntityType type) async {
      await tester.pumpWidget(
        _app(
          ListTotalsLine(
            source: source,
            entityType: type,
            companyId: 'co',
            formatter: _formatter,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('label, then each currency — the company\'s first, its '
        'local "" share folded in — and never a zero', (tester) async {
      await pump(tester, EntityType.quote);
      source.totals.add(
        _dec({'3': '17588', '': '33', '1': '5900', '2': '0', '999': '1'}),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text(r'Open  $5,933.00 · €17,588.00', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('each list reads its own label', (tester) async {
      for (final (type, label) in [
        (EntityType.credit, 'Credit Balance'),
        (EntityType.payment, 'Unapplied'),
        (EntityType.expense, 'Uninvoiced'),
        (EntityType.recurringExpense, 'Active'),
      ]) {
        source = _FakeSource();
        await pump(tester, type);
        source.totals.add(_dec({'2': '1'}));
        await tester.pump();
        await tester.pump();
        expect(
          find.text('$label  £1.00', findRichText: true),
          findsOneWidget,
          reason: '$type',
        );
      }
    });

    testWidgets('unknown, empty and all-zero draw nothing at all', (
      tester,
    ) async {
      await pump(tester, EntityType.quote);
      Finder line() => find.byType(TotalsLineText);
      expect(line(), findsNothing);
      source.totals.add(null);
      await tester.pump();
      await tester.pump();
      expect(line(), findsNothing);
      source.totals.add(const {});
      await tester.pump();
      await tester.pump();
      expect(line(), findsNothing);
      source.totals.add(_dec({'1': '0', '': '0'}));
      await tester.pump();
      await tester.pump();
      expect(line(), findsNothing);
    });

    testWidgets('opening asks with the five-minute max age; a change leaving '
        'the outbox asks again, once, after the quiet delay', (tester) async {
      await pump(tester, EntityType.payment);
      expect(source.refreshes, [kListTotalsMaxAge]);

      source.outbox.add(2);
      await tester.pump();
      source.outbox.add(3);
      await tester.pump(kListTotalsRefetchDelay * 2);
      expect(source.refreshes, hasLength(1), reason: 'a rise is not a drop');

      source.outbox.add(2);
      await tester.pump();
      source.outbox.add(1);
      await tester.pump(kListTotalsRefetchDelay ~/ 2);
      expect(source.refreshes, hasLength(1));
      await tester.pump(kListTotalsRefetchDelay);
      expect(source.refreshes, [kListTotalsMaxAge, null]);
    });

    testWidgets('a list with no line, or a disabled one, asks nothing', (
      tester,
    ) async {
      await pump(tester, EntityType.vendor);
      await tester.pumpWidget(
        _app(
          ListTotalsLine(
            source: source,
            entityType: EntityType.invoice,
            companyId: 'co',
            formatter: _formatter,
            enabled: false,
          ),
        ),
      );
      expect(source.refreshes, isEmpty);
    });
  });

  group('on a wide list: the end of the status strip\'s row', () {
    final tabs = listStatusTabsFor(
      EntityType.invoice,
      modes: kInvoiceBadgeModes,
      trackInventory: false,
    );
    const lineKey = Key('totals');
    const label = 'Outstanding';
    const amounts = [r'$5,933.00', '£19,399.00', '€17,588.00'];

    Future<void> pump(
      WidgetTester tester,
      double width, {
      bool withLine = true,
      TextDirection direction = TextDirection.ltr,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          Directionality(
            textDirection: direction,
            child: EntityListStatusTabs(
              tabs: tabs,
              selectedIndex: 0,
              showCounts: true,
              streamKey: 'invoice:co',
              countStream: (_) => Stream<int>.value(1234),
              onTap: (_) {},
              contentPadding: const EdgeInsetsDirectional.only(start: 24),
              trailing: withLine
                  ? const Padding(
                      padding: EdgeInsetsDirectional.only(end: 24),
                      child: TotalsLineText(
                        key: lineKey,
                        label: label,
                        amounts: amounts,
                      ),
                    )
                  : null,
            ),
          ),
          width: width,
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    RenderTrailingIfRoom row(WidgetTester tester) =>
        tester.renderObject(find.byType(TrailingIfRoom));

    testWidgets('with room, it sits at the end edge, after the last tab', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, 1800);
      expect(row(tester).showsTrailing, isTrue);
      final line = tester.getRect(find.byKey(lineKey));
      expect(line.right, 1800 - 24);
      expect(line.left, greaterThan(tester.getRect(find.text('Paid')).right));
      expect(find.bySemanticsLabel(RegExp('^$label ')), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('in a right-to-left layout the end edge is the left', (
      tester,
    ) async {
      await pump(tester, 1800, direction: TextDirection.rtl);
      expect(row(tester).showsTrailing, isTrue);
      expect(tester.getRect(find.byKey(lineKey)).left, 24);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without room it is dropped — not painted, hit or read — and '
        'the tabs keep exactly the place they had without it', (tester) async {
      await pump(tester, 600, withLine: false);
      final allAlone = tester.getRect(find.text('All'));
      final paidAlone = tester.getRect(find.text('Paid'));

      final semantics = tester.ensureSemantics();
      await pump(tester, 600);
      expect(row(tester).showsTrailing, isFalse);
      expect(tester.getRect(find.text('All')), allAlone);
      expect(tester.getRect(find.text('Paid')), paidAlone);
      expect(find.byKey(lineKey).hitTestable(), findsNothing);
      expect(find.bySemanticsLabel(RegExp('^$label ')), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('a pane narrower than the tabs scrolls them, with no overflow '
        'and no line', (tester) async {
      await pump(tester, 320);
      expect(row(tester).showsTrailing, isFalse);
      expect(tester.takeException(), isNull);
      // Still a scroller as wide as the pane.
      expect(tester.getSize(find.byType(SingleChildScrollView)).width, 320);
    });
  });
}
