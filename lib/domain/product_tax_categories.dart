/// Canonical product tax-category catalog — wire id → localization key.
///
/// Single source of truth, mirrored from the server's
/// `Product::PRODUCT_TYPE_*` constants (`app/Models/Product.php`) and React's
/// `useTaxCategories()` (`src/components/tax-rates/TaxCategorySelector.tsx`).
/// The server contract is the string id (`'1'`..`'10'`); the value is a
/// localization key resolved via `context.tr(...)`.
///
/// `'10'` is the server's `PRODUCT_INTRA_COMMUNITY`, which React does not
/// offer: `BaseRule::tax` zero-rates it for a buyer in another region, and the
/// e-invoice standards map it to VAT category K. Its label is the server's own
/// `intracommunity_tax_info` ("Tax-free intra-community delivery"), the text
/// the PDF prints for the same treatment — there is no shorter server string.
///
/// `Map` literal order is insertion order in Dart, so iterating
/// `.entries` yields `1`→`10` for dropdowns / pickers. Every consumer
/// (the set-tax-category dialog, the edit-form dropdown, the list column,
/// the detail card) reads from this map — do not re-declare a local copy.
/// `product_tax_category_catalog_test` guards that all ids resolve to a
/// real `en.json` key.
const Map<String, String> kProductTaxCategories = <String, String>{
  '1': 'physical_goods',
  '2': 'services',
  '3': 'digital_products',
  '4': 'shipping',
  '5': 'tax_exempt',
  '6': 'reduced_tax',
  '7': 'override_tax',
  '8': 'zero_rated',
  '9': 'reverse_tax',
  '10': 'intracommunity_tax_info',
};

/// `Product::PRODUCT_TYPE_OVERRIDE_TAX` — the one category whose line keeps
/// the tax names and rates typed on it while Calculate Taxes is on.
const String kOverrideTaxCategoryId = '7';

/// The category a standard line falls back to — Physical Goods, what the
/// server gives a blank `tax_id` on any line that is not hourly
/// (`CleanLineItems`), and what React's blank line item and product pick use.
const String kDefaultTaxCategoryId = '1';

/// The category an hourly (`type_id` 2) line falls back to — Services, what
/// `CleanLineItems` gives a blank `tax_id` on a task line. US states that
/// exempt services (`US/Rule::taxService`) tax it at zero, so stamping such a
/// line Physical Goods would add sales tax the server never would.
const String kServicesTaxCategoryId = '2';

/// The category the server will save a line under: its own [taxCategoryId],
/// or — when blank — what `CleanLineItems` fills in before any tax is worked
/// out: Services for an [hourly] line, Physical Goods for any other.
///
/// A blank id is therefore never Override on the server. Read through this
/// wherever a line's category is shown or decided on, so a blank line shows
/// the category it will really be taxed by.
String taxCategoryAsSaved(String taxCategoryId, {required bool hourly}) =>
    taxCategoryId.isNotEmpty
    ? taxCategoryId
    : (hourly ? kServicesTaxCategoryId : kDefaultTaxCategoryId);

/// Whether a line in category [taxCategoryId] keeps its own tax rates while
/// the company's Calculate Taxes is on — Override (`7`) only:
/// `BaseRule::override` leaves the line's rates alone, and every other
/// category's are recalculated on save (`InvoiceItemSum::calcTaxesAutomatically`),
/// whatever the line carried. Pass the id through [taxCategoryAsSaved] first:
/// a blank one is saved as a real category, never as Override.
bool taxCategoryKeepsManualRates(String taxCategoryId) =>
    taxCategoryId == kOverrideTaxCategoryId;
