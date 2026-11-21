import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:admin/domain/product_tax_categories.dart';

void main() {
  test('kProductTaxCategories covers the server PRODUCT_TYPE ids 1..10 and '
      'every label resolves to an en.json key', () {
    // Server source of truth: Product::PRODUCT_TYPE_* = 1..9 plus
    // PRODUCT_INTRA_COMMUNITY = 10 (app/Models/Product.php); React's
    // useTaxCategories() offers 1..9.
    expect(kProductTaxCategories.keys.toList(), [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
    ]);

    final en =
        jsonDecode(File('assets/i18n/en.json').readAsStringSync())
            as Map<String, dynamic>;
    for (final entry in kProductTaxCategories.entries) {
      expect(
        en.containsKey(entry.value),
        isTrue,
        reason:
            'en.json is missing the tax-category label key "${entry.value}" '
            '(id ${entry.key})',
      );
    }
  });

  test('only Override keeps a line\'s manual rates', () {
    expect(taxCategoryKeepsManualRates(kOverrideTaxCategoryId), isTrue);
    for (final id in kProductTaxCategories.keys) {
      if (id == kOverrideTaxCategoryId) continue;
      expect(taxCategoryKeepsManualRates(id), isFalse, reason: id);
    }
  });

  test('a blank category saves as the server fills it (CleanLineItems)', () {
    expect(taxCategoryAsSaved('', hourly: true), '2');
    expect(taxCategoryAsSaved('', hourly: false), '1');
    expect(taxCategoryAsSaved('7', hourly: true), '7');
    expect(taxCategoryAsSaved('5', hourly: false), '5');
  });
}
