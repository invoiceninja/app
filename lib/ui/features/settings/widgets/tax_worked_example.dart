import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/l10n/localization.dart';
import 'package:admin/utils/formatting.dart';

/// The amount the worked example taxes.
final Decimal kTaxExampleAmount = Decimal.fromInt(100);

/// The rate the worked example applies, in percent.
final Decimal kTaxExampleRate = Decimal.fromInt(10);

/// The net and tax parts of [amount] taxed at [ratePercent], the way the
/// server splits them: exclusive adds `amount × rate` on top; inclusive takes
/// the tax out of the amount as `amount − amount / (1 + rate)`
/// (`Taxer::calcInclusiveLineTax`). Rounded to cents, so
/// the two parts always add back up to the shown total.
({Decimal net, Decimal tax}) taxExampleParts({
  required Decimal amount,
  required Decimal ratePercent,
  required bool inclusive,
}) {
  final rate = (ratePercent / Decimal.fromInt(100)).toDecimal(
    scaleOnInfinitePrecision: 10,
  );
  if (!inclusive) {
    return (net: amount, tax: (amount * rate).round(scale: 2));
  }
  final net = (amount / (Decimal.one + rate)).toDecimal(
    scaleOnInfinitePrecision: 10,
  );
  final tax = (amount - net).round(scale: 2);
  return (net: amount - tax, tax: tax);
}

/// "Example: $100.00 at 10% tax → $90.91 + $9.09 tax" — what the inclusive /
/// exclusive choice does to a price, worked for the choice currently made, in
/// the company's money format. Null until the company [formatter] has
/// loaded, so a caller can fall back to its static help.
String? taxWorkedExample(
  BuildContext context,
  Formatter? formatter, {
  required bool inclusive,
}) {
  if (formatter == null) return null;
  final parts = taxExampleParts(
    amount: kTaxExampleAmount,
    ratePercent: kTaxExampleRate,
    inclusive: inclusive,
  );
  return context.tr('tax_worked_example', {
    'amount': formatter.money(kTaxExampleAmount),
    'rate': formatter.percent(kTaxExampleRate.toDouble()),
    'net': formatter.money(parts.net),
    'tax': formatter.money(parts.tax),
  });
}
