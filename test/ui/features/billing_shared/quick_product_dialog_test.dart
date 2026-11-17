import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/product.dart';
import 'package:admin/ui/features/billing_shared/line_item_picker/quick_product_dialog.dart';

import '../../../_localization_helper.dart';

/// The quick "new product" dialog the line-item cell and the Add-items picker
/// open. Beta feedback: on a purchase order it asks for the sale price beside
/// the cost, and (with `enable_product_cost`, which needs a company lookup and
/// is exercised through the callers) a sales document asks for the cost
/// beside the price — so the product needn't be opened again afterwards.
void main() {
  Future<Product?> open(
    WidgetTester tester, {
    required bool vendorDoc,
    required Future<void> Function() fill,
  }) async {
    Product? result;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showQuickProductDialog(
                  context,
                  initialKey: 'Widget',
                  vendorDoc: vendorDoc,
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await fill();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    return result;
  }

  testWidgets('a purchase order asks for the cost and the sale price', (
    tester,
  ) async {
    final product = await open(
      tester,
      vendorDoc: true,
      fill: () async {
        await tester.enterText(find.widgetWithText(TextField, 'Cost'), '40');
        await tester.enterText(find.widgetWithText(TextField, 'Price'), '65');
      },
    );
    expect(product!.productKey, 'Widget');
    expect(product.cost, Decimal.fromInt(40));
    expect(product.price, Decimal.fromInt(65));
  });

  testWidgets('with no company to ask, a sales document asks only the price', (
    tester,
  ) async {
    final product = await open(
      tester,
      vendorDoc: false,
      fill: () async {
        expect(find.widgetWithText(TextField, 'Cost'), findsNothing);
        await tester.enterText(find.widgetWithText(TextField, 'Price'), '65');
      },
    );
    expect(product!.price, Decimal.fromInt(65));
    expect(product.cost, Decimal.zero);
  });
}
