import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/company_label_overrides.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/data/models/domain/billing/line_item_type.dart';
import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/models/value/country.dart';
import 'package:admin/data/models/value/currency.dart';
import 'package:admin/data/models/value/datetime_format.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/repositories/company_repository.dart';
import 'package:admin/domain/billing/totals_calculator.dart';
import 'package:admin/l10n/company_labels_scope.dart';
import 'package:admin/ui/features/billing_shared/billing_doc_overview.dart';
import 'package:admin/ui/core/widgets/cell_copy_hover.dart';
import 'package:admin/ui/features/billing_shared/line_items_readonly_table.dart';
import 'package:admin/ui/features/billing_shared/totals_widget.dart';
import 'package:admin/utils/formatting.dart';

import '../../../_localization_helper.dart';

/// Minimal repos so [BillingDocOverview] can watch the active company — it
/// needs it for surcharge labels and for the header's Custom Labels. Anything
/// else throws so the test fails loudly if the widget reaches further.
class _FakeCompanyRepo implements CompanyRepository {
  _FakeCompanyRepo(this._company);
  final Company? _company;

  @override
  Stream<Company?> watchCompany(String companyId) => Stream.value(_company);

  // Cold seed cache: keeps these tests on the async watch path, exactly as
  // before `BaseEntityRepository.peek` existed. The `company is still loading
  // (null)` case below depends on it staying cold.
  @override
  Company? peek({required String companyId, required String id}) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeAuth implements AuthRepository {
  @override
  String? get currentCompanyId => 'co-A';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeServices implements Services {
  _FakeServices(this.company);
  @override
  final CompanyRepository company;
  @override
  final AuthRepository auth = _FakeAuth();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// A company whose Custom Labels (`settings.translations`) hold [overrides].
Company _companyWithLabels(Map<String, dynamic> overrides) =>
    Company(settings: CompanySettings(translations: overrides));

/// A USD formatter — exercises the real money/date path so these tests catch
/// the original bug (raw `100` / `2022-02-08`) regressing.
Formatter _usdFormatter() => Formatter(
  settings: CompanyFormatSettings.fallback,
  currencies: {
    '1': Currency(
      id: '1',
      name: 'US Dollar',
      code: 'USD',
      symbol: r'$',
      precision: 2,
      thousandSeparator: ',',
      decimalSeparator: '.',
      swapCurrencySymbol: false,
      exchangeRate: Decimal.one,
    ),
  },
  countries: {
    '840': Country(
      id: '840',
      name: 'United States',
      iso2: 'US',
      iso3: 'USA',
      swapCurrencySymbol: false,
      thousandSeparator: '',
      decimalSeparator: '',
      swapPostalCode: false,
    ),
  },
  dateFormats: {'5': const DatetimeFormat(id: '5', format: 'MMM d, yyyy')},
);

LineItem _item({
  String productKey = 'Widget',
  String notes = 'A nice widget',
  String cost = '50',
  String quantity = '2',
}) => emptyLineItem().copyWith(
  productKey: productKey,
  notes: notes,
  cost: Decimal.parse(cost),
  quantity: Decimal.parse(quantity),
);

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {Company? company}) {
    return tester.pumpWidget(
      Provider<Services>.value(
        value: _FakeServices(_FakeCompanyRepo(company)),
        child: MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
  }

  group('LineItemsReadonlyTable', () {
    testWidgets('the item name carries the copy affordance; a line with no '
        'item name offers none', (tester) async {
      // The Item cell was plain text: the only way to copy a product key was
      // to open the line's editor and select it there.
      await pump(
        tester,
        SizedBox(
          width: 900,
          child: LineItemsReadonlyTable(
            items: [
              _item(),
              _item(productKey: '', notes: 'Just a note'),
            ],
            formatter: _usdFormatter(),
            currencyId: '1',
          ),
        ),
      );
      await tester.pump();

      final copies = tester
          .widgetList<CellCopyHover>(find.byType(CellCopyHover))
          .toList();
      // One per item name — the description and the figures have none, and
      // a line with no name leads with its description instead.
      expect(copies.map((c) => c.value), ['Widget']);
      expect(find.text('Just a note'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      // Touch: the row's tap opens the line, so the name copies on long-press.
      expect(copies.every((c) => c.touchLongPressCopies), isTrue);
    });

    testWidgets('renders item, unit cost and gross line total', (tester) async {
      await pump(
        tester,
        LineItemsReadonlyTable(
          items: [_item()],
          formatter: _usdFormatter(),
          currencyId: '1',
        ),
      );
      await tester.pump();

      expect(find.text('Widget'), findsOneWidget);
      expect(find.text(r'$50.00'), findsOneWidget); // unit cost
      expect(find.text(r'$100.00'), findsOneWidget); // gross = 50 × 2
    });

    testWidgets('header uses the shipped labels when the company has none', (
      tester,
    ) async {
      await pump(
        tester,
        LineItemsReadonlyTable(
          items: [_item()],
          formatter: _usdFormatter(),
          currencyId: '1',
        ),
      );
      await tester.pump();

      // Column heads are set in capitals.
      expect(find.text('UNIT COST'), findsOneWidget);
      expect(find.text('ITEM'), findsOneWidget);
    });

    testWidgets('header honors the company Custom Labels override', (
      tester,
    ) async {
      await pump(
        tester,
        // The app's own route: `main.dart` installs the scope over every
        // screen, fed by `CompanyLabelOverrides`.
        CompanyLabelsScope(
          labels: ValueNotifier(
            companyLabelOverrides(
              _companyWithLabels(const {'unit_cost': 'Unit Price'}),
            ),
          ),
          child: LineItemsReadonlyTable(
            items: [_item()],
            formatter: _usdFormatter(),
            currencyId: '1',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('UNIT PRICE'), findsOneWidget);
      expect(find.text('UNIT COST'), findsNothing);
      // Untouched keys keep the bundled string.
      expect(find.text('ITEM'), findsOneWidget);
    });

    testWidgets('a blank override falls back to the shipped label', (
      tester,
    ) async {
      // The Custom Labels editor seeds a newly added row with '', and the
      // server coerces nulls to ''. Neither may blank the column header.
      await pump(
        tester,
        // The app's own route: `main.dart` installs the scope over every
        // screen, fed by `CompanyLabelOverrides`.
        CompanyLabelsScope(
          labels: ValueNotifier(
            companyLabelOverrides(
              _companyWithLabels(const {'unit_cost': '', 'item': '   '}),
            ),
          ),
          child: LineItemsReadonlyTable(
            items: [_item()],
            formatter: _usdFormatter(),
            currencyId: '1',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('UNIT COST'), findsOneWidget);
      expect(find.text('ITEM'), findsOneWidget);
    });

    testWidgets('shows an empty placeholder when there are no items', (
      tester,
    ) async {
      await pump(
        tester,
        LineItemsReadonlyTable(
          items: const [],
          formatter: _usdFormatter(),
          currencyId: '1',
        ),
      );
      await tester.pump();

      expect(find.text('No records found'), findsOneWidget);
    });

    // A line's custom values were shown nowhere in the app. Product and hourly
    // lines share this table but take their labels from different company
    // fields, so each line names its own.
    group('custom values', () {
      const definitions = {
        'product1': 'Color|Red,Blue',
        'product2': 'Warranty|switch',
        'task1': 'Phase|single_line_text',
      };
      final product = _item().copyWith(
        customValue1: 'Red',
        customValue2: 'yes',
      );
      final hourly = _item(
        productKey: 'Design',
      ).copyWith(typeId: LineItemType.task, customValue1: 'Discovery');

      for (final width in [1200.0, 420.0]) {
        final layout = width > 600 ? 'wide' : 'stacked';
        testWidgets('$layout: each line labelled from its own fields', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await pump(
            tester,
            LineItemsReadonlyTable(
              items: [product, hourly],
              formatter: _usdFormatter(),
              currencyId: '1',
              customFields: definitions,
            ),
          );
          await tester.pump();

          expect(find.text('Color: Red   ·   Warranty: Yes'), findsOneWidget);
          expect(find.text('Phase: Discovery'), findsOneWidget);
        });
      }

      testWidgets('nothing extra before the company has loaded', (
        tester,
      ) async {
        await pump(
          tester,
          LineItemsReadonlyTable(
            items: [product],
            formatter: _usdFormatter(),
            currencyId: '1',
          ),
        );
        await tester.pump();

        expect(find.textContaining('Color'), findsNothing);
      });
    });

    // Tap a line to edit it (admin-portal parity). The index handed back is
    // the line's place in `items` — blank lines counted though not drawn —
    // since that is how the edit view model's draft holds them.
    for (final width in [800.0, 320.0]) {
      testWidgets('a tapped line reports its index in items ($width px)', (
        tester,
      ) async {
        final tapped = <int>[];
        await pump(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: LineItemsReadonlyTable(
                items: [
                  _item(),
                  emptyLineItem(),
                  _item(productKey: 'Gadget'),
                ],
                formatter: _usdFormatter(),
                currencyId: '1',
                onTapItem: tapped.add,
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Gadget'));
        await tester.tap(find.text('Widget'));
        expect(tapped, [2, 0]);
      });
    }

    testWidgets('without onTapItem the lines are not tap targets', (
      tester,
    ) async {
      await pump(
        tester,
        LineItemsReadonlyTable(
          items: [_item()],
          formatter: _usdFormatter(),
          currencyId: '1',
        ),
      );
      await tester.pump();
      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('BillingDocOverview', () {
    testWidgets('renders line items + totals, then whatever trails them', (
      tester,
    ) async {
      await pump(
        tester,
        SingleChildScrollView(
          child: BillingDocOverview(
            totalsInput: BillingTotalsInput(
              lineItems: [_item()],
              discount: Decimal.zero,
              isAmountDiscount: false,
              usesInclusiveTaxes: false,
            ),
            precision: 2,
            balance: Decimal.parse('100'),
            formatter: _usdFormatter(),
            currencyId: '1',
            trailing: const [Text('TRAILING_MARKER')],
          ),
        ),
      );
      await tester.pump();

      // Line item + computed total both formatted.
      expect(find.text('Widget'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text(r'$100.00'), findsWidgets);
      // Nothing is dashed; the notes are a card of their own now
      // (`billing_doc_notes_test.dart`).
      expect(find.text('—'), findsNothing);
      // Trailing (the invoice's payments and reminders, then the printed
      // notes) renders.
      expect(find.text('TRAILING_MARKER'), findsOneWidget);
    });

    testWidgets('the totals are the foot of the table: at the end of its row '
        'where there is room, and the whole row where there is not', (
      tester,
    ) async {
      Future<({double left, double width})> totalsAt(double width) async {
        await pump(
          tester,
          SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: BillingDocOverview(
                  totalsInput: BillingTotalsInput(
                    lineItems: [_item()],
                    discount: Decimal.zero,
                    isAmountDiscount: false,
                    usesInclusiveTaxes: false,
                  ),
                  precision: 2,
                  formatter: _usdFormatter(),
                  currencyId: '1',
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final totals = tester.getRect(find.byType(TotalsWidget));
        final table = tester.getRect(find.byType(LineItemsReadonlyTable));
        return (left: totals.left - table.left, width: totals.width);
      }

      // Inside the table's own 1 px border on both sides. A 390 px phone
      // leaves 366, less than the cap: the totals take the whole row.
      final phone = await totalsAt(366);
      expect(phone.left, 1);
      expect(phone.width, 364);
      // The pane has room: capped, and under the Total column at the end.
      final pane = await totalsAt(448);
      expect(pane.width, 360);
      expect(pane.left, 448 - 360 - 1);
    });

    testWidgets('names line custom values from the watched company', (
      tester,
    ) async {
      // Pins the overview's hand-off of `company.customFields` to the table —
      // the table tests build it directly and can't see that wiring.
      await pump(
        tester,
        SingleChildScrollView(
          child: BillingDocOverview(
            totalsInput: BillingTotalsInput(
              lineItems: [_item().copyWith(customValue1: 'Red')],
              discount: Decimal.zero,
              isAmountDiscount: false,
              usesInclusiveTaxes: false,
            ),
            precision: 2,
            balance: Decimal.parse('100'),
            formatter: _usdFormatter(),
            currencyId: '1',
          ),
        ),
        company: const Company(customFields: {'product1': 'Color|Red,Blue'}),
      );
      await tester.pump();

      expect(find.text('Color: Red'), findsOneWidget);
    });
  });
}
