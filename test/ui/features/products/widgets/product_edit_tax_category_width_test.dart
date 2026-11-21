// Category 10's label, "Tax-free intra-community delivery", is wider than a
// phone's field: the product form's Tax Category dropdown sized its button to
// the widest item and overflowed. It now fills the field and ellipsizes.

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/product.dart';
import 'package:admin/ui/features/products/view_models/product_edit_view_model.dart';
import 'package:admin/ui/features/products/widgets/edit/product_edit_taxes_section.dart';

import '../../shell/_shell_test_helpers.dart';

void main() {
  testWidgets('the longest tax category fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
    );
    addTearDown(fixture.dispose);
    final vm = ProductEditViewModel(
      repo: fixture.services.products,
      companyId: 'co1',
      existing: Product(
        id: 'p1',
        productKey: 'Widget',
        notes: '',
        cost: Decimal.zero,
        price: Decimal.one,
        quantity: Decimal.one,
        maxQuantity: Decimal.zero,
        productImage: '',
        inStockQuantity: Decimal.zero,
        stockNotification: false,
        stockNotificationThreshold: Decimal.zero,
        taxName1: '',
        taxRate1: Decimal.zero,
        taxName2: '',
        taxRate2: Decimal.zero,
        taxName3: '',
        taxRate3: Decimal.zero,
        taxId: '10',
        customValue1: '',
        customValue2: '',
        customValue3: '',
        customValue4: '',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        archivedAt: null,
        isDeleted: false,
      ),
    );
    addTearDown(vm.dispose);

    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        SingleChildScrollView(child: ProductEditTaxesSection(vm: vm)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Tax-free intra-community delivery'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
