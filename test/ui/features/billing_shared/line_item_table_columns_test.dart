import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/static/pdf_catalogs.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_column_config.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_table_columns.dart';
import 'package:flutter_test/flutter_test.dart';

/// The desktop line-item table shows the company's Invoice Design columns,
/// with what React's `useProductColumns` / `useTaskColumns` force in
/// (invoiceninja/app#216). Before, it drew every field a line can hold, and a
/// company with several custom fields and taxes got columns too narrow to use.
void main() {
  List<String> resolve(
    List<String>? saved, {
    String section = PdfVariableSection.productColumns,
    int taxes = 0,
    bool discount = false,
    bool quantity = true,
    Set<int> custom = const {},
  }) => resolveLineItemColumnVariables(
    section: section,
    saved: saved,
    enabledItemTaxRates: taxes,
    enableProductDiscount: discount,
    enableProductQuantity: quantity,
    definedCustomSlots: custom,
  );

  group('resolveLineItemColumnVariables (React useProductColumns)', () {
    test('an empty list: Item, Description, Unit Cost, Quantity — and no '
        'Line Total, as React', () {
      expect(resolve(const []), [
        r'$product.item',
        r'$product.description',
        r'$product.unit_cost',
        r'$product.quantity',
      ]);
    });

    test('an empty list still gets the taxes, discount and custom fields', () {
      expect(resolve(const [], taxes: 2, discount: true, custom: {1, 3}), [
        r'$product.item',
        r'$product.description',
        r'$product.unit_cost',
        r'$product.quantity',
        r'$product.tax_rate1',
        r'$product.tax_rate2',
        r'$product.discount',
        r'$product.product1',
        r'$product.product3',
      ]);
    });

    test('no saved list reads as the catalog default, as the settings '
        'screen and the server PDF do', () {
      expect(resolve(null, taxes: 1, discount: true), [
        r'$product.item',
        r'$product.description',
        r'$product.unit_cost',
        r'$product.quantity',
        r'$product.discount',
        r'$product.tax_rate1',
        r'$product.line_total',
      ]);
    });

    test('the saved order is kept; Item, Unit Cost and Quantity are forced '
        'in', () {
      expect(resolve(const [r'$product.line_total', r'$product.description']), [
        r'$product.item',
        r'$product.description',
        r'$product.unit_cost',
        r'$product.quantity',
        r'$product.line_total',
      ]);
      expect(
        resolve(const [
          r'$product.description',
          r'$product.quantity',
          r'$product.item',
          r'$product.unit_cost',
        ]),
        [
          r'$product.description',
          r'$product.quantity',
          r'$product.item',
          r'$product.unit_cost',
        ],
      );
    });

    test('a column the list leaves out stays out', () {
      // The whole point: Description off the PDF is off the table too.
      expect(
        resolve(const [
          r'$product.item',
          r'$product.unit_cost',
          r'$product.quantity',
          r'$product.line_total',
        ]),
        isNot(contains(r'$product.description')),
      );
    });

    test('tax becomes one column per enabled rate, at its place', () {
      expect(
        resolve(const [
          r'$product.item',
          r'$product.tax',
          r'$product.unit_cost',
          r'$product.quantity',
        ], taxes: 3),
        [
          r'$product.item',
          r'$product.tax_rate1',
          r'$product.tax_rate2',
          r'$product.tax_rate3',
          r'$product.unit_cost',
          r'$product.quantity',
        ],
      );
    });

    test('taxes off: the listed tax column goes, none is added', () {
      expect(
        resolve(const [r'$product.item', r'$product.tax'], taxes: 0),
        isNot(contains(startsWith(r'$product.tax'))),
      );
    });

    test('discount follows the company switch, whatever the list says', () {
      const listed = [r'$product.item', r'$product.discount'];
      expect(resolve(listed), isNot(contains(r'$product.discount')));
      expect(
        resolve(const [r'$product.item'], discount: true),
        contains(r'$product.discount'),
      );
    });

    test('every defined custom field shows; an undefined one never does', () {
      final columns = resolve(
        const [
          r'$product.item',
          r'$product.product2',
          r'$product.product4',
          r'$product.unit_cost',
          r'$product.quantity',
        ],
        custom: {1, 2},
      );
      expect(columns, [
        r'$product.item',
        r'$product.product2', // listed and defined: at its place
        r'$product.unit_cost',
        r'$product.quantity',
        r'$product.product1', // defined, unlisted: appended
      ]);
    });

    test('Show Product Quantity off drops Quantity from a product table', () {
      expect(
        resolve(null, quantity: false),
        isNot(contains(r'$product.quantity')),
      );
    });

    test('Tax Amount, Gross Line Total and Line Total move to the end', () {
      expect(
        resolve(
          const [
            r'$product.line_total',
            r'$product.gross_line_total',
            r'$product.item',
            r'$product.tax_amount',
            r'$product.description',
          ],
          custom: {1},
        ),
        [
          r'$product.item',
          r'$product.description',
          r'$product.unit_cost',
          r'$product.quantity',
          r'$product.product1',
          r'$product.tax_amount',
          r'$product.gross_line_total',
          r'$product.line_total',
        ],
      );
    });

    test('Net Cost is PDF-only, and a doubled variable is kept once', () {
      expect(
        resolve(const [
          r'$product.item',
          r'$product.net_cost',
          r'$product.description',
          r'$product.description',
        ]),
        [
          r'$product.item',
          r'$product.description',
          r'$product.unit_cost',
          r'$product.quantity',
        ],
      );
    });
  });

  group('task table (React useTaskColumns)', () {
    List<String> task(
      List<String>? saved, {
      bool quantity = true,
      Set<int> custom = const {},
    }) => resolve(
      saved,
      section: PdfVariableSection.taskColumns,
      quantity: quantity,
      custom: custom,
    );

    test('an empty list: Service, Description, Rate, Hours', () {
      expect(task(const []), [
        r'$task.service',
        r'$task.description',
        r'$task.rate',
        r'$task.hours',
      ]);
    });

    test('Hours stays with Show Product Quantity off', () {
      expect(task(null, quantity: false), contains(r'$task.hours'));
    });

    test('custom fields are task1..4', () {
      expect(task(const [], custom: {2}), contains(r'$task.task2'));
      expect(task(const [], custom: {2}), isNot(contains(r'$task.product2')));
    });
  });

  test('variables map onto the table cells; tags has none', () {
    expect(
      lineItemTableColumnsFromVariables(const [
        r'$task.service',
        r'$task.rate',
        r'$task.hours',
        r'$product.tax_rate2',
        r'$product.product3',
        r'$product.tags',
        r'$product.gross_line_total',
      ]),
      [
        LineItemTableColumn.item,
        LineItemTableColumn.unitCost,
        LineItemTableColumn.quantity,
        const LineItemTableColumn.tax(2),
        const LineItemTableColumn.custom(3),
        LineItemTableColumn.grossLineTotal,
      ],
    );
  });

  group('LineItemColumnConfig.forCompany', () {
    Company company({
      Map<String, List<String>>? pdfVariables,
      bool? syncQuoteColumns,
      bool quantity = true,
      int taxes = 0,
      Map<String, String> customFields = const {},
    }) => Company(
      id: 'co',
      enabledItemTaxRates: taxes,
      enableProductDiscount: true,
      enableProductQuantity: quantity,
      customFields: customFields,
      settings: CompanySettings(
        pdfVariables: pdfVariables,
        syncInvoiceQuoteColumns: syncQuoteColumns,
      ),
    );

    const host = LineItemColumnConfig(showDiscount: true, taxColumnCount: 1);

    test('no company: the full legacy set, no columns tab', () {
      final config = host.forCompany(null);
      expect(config.columnsSection, isNull);
      expect(config.desktopColumns, [
        LineItemTableColumn.item,
        LineItemTableColumn.description,
        LineItemTableColumn.unitCost,
        LineItemTableColumn.quantity,
        LineItemTableColumn.discount,
        const LineItemTableColumn.tax(1),
        LineItemTableColumn.lineTotal,
      ]);
    });

    test('the company list drives the table; the flags still describe the '
        'whole line for the dialog and the phone', () {
      final config = host.forCompany(
        company(
          taxes: 2,
          customFields: const {'product1': 'Color'},
          pdfVariables: const {
            PdfVariableSection.productColumns: [
              r'$product.item',
              r'$product.unit_cost',
              r'$product.quantity',
              r'$product.line_total',
            ],
          },
        ),
      );
      expect(config.columnsSection, PdfVariableSection.productColumns);
      expect(config.desktopColumns, [
        LineItemTableColumn.item,
        LineItemTableColumn.unitCost,
        LineItemTableColumn.quantity,
        const LineItemTableColumn.tax(1),
        const LineItemTableColumn.tax(2),
        LineItemTableColumn.discount,
        const LineItemTableColumn.custom(1),
        LineItemTableColumn.lineTotal,
      ]);
      // Description is off the table, not off the line.
      expect(config.taxColumnCount, 2);
      expect(config.customFields.single.slot, 1);
    });

    test('a quote reads Quote Product Columns only when unsynced', () {
      const quote = LineItemColumnConfig(isQuote: true);
      const quoteColumns = {
        PdfVariableSection.productColumns: [r'$product.description'],
        PdfVariableSection.productQuoteColumns: [r'$product.line_total'],
      };
      final unsynced = quote.forCompany(
        company(pdfVariables: quoteColumns, syncQuoteColumns: false),
      );
      expect(unsynced.columnsSection, PdfVariableSection.productQuoteColumns);
      expect(unsynced.desktopColumns, contains(LineItemTableColumn.lineTotal));
      expect(
        unsynced.desktopColumns,
        isNot(contains(LineItemTableColumn.description)),
      );

      // Unset is synced — the server's default, and the settings screen's.
      for (final sync in [true, null]) {
        final synced = quote.forCompany(
          company(pdfVariables: quoteColumns, syncQuoteColumns: sync),
        );
        expect(synced.columnsSection, PdfVariableSection.productColumns);
      }

      // An invoice never reads the quote list.
      expect(
        const LineItemColumnConfig()
            .forCompany(
              company(pdfVariables: quoteColumns, syncQuoteColumns: false),
            )
            .columnsSection,
        PdfVariableSection.productColumns,
      );
    });

    test('a task table reads Task Columns', () {
      const tasks = LineItemColumnConfig(isTaskTable: true, isQuote: true);
      final config = tasks.forCompany(
        company(
          syncQuoteColumns: false,
          pdfVariables: const {
            PdfVariableSection.taskColumns: [
              r'$task.service',
              r'$task.hours',
              r'$task.rate',
            ],
          },
        ),
      );
      expect(config.columnsSection, PdfVariableSection.taskColumns);
      expect(config.desktopColumns, [
        LineItemTableColumn.item,
        LineItemTableColumn.quantity,
        LineItemTableColumn.unitCost,
      ]);
    });
  });
}
