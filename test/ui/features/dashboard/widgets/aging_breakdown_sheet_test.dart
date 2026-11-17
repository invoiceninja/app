import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/features/dashboard/widgets/aging_bar.dart';

import '../../../../_localization_helper.dart';

/// The breakdown's shares are the bar's: a bucket that is a credit (below
/// zero) is not drawn in the bar, and summed into the total it pushed the
/// other buckets' shares past 100%.
void main() {
  AgingSegment seg(String label, String amount) => AgingSegment(
    label: label,
    amount: Decimal.parse(amount),
    formatted: '\$$amount',
    color: InTheme.light.partial,
  );

  testWidgets('shares are of the positive total, as the bar draws them', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: Scaffold(
          body: AgingBreakdownSheet(
            segments: [
              seg('Current', '-500'),
              seg('0 - 30 Days', '750'),
              seg('31 - 60 Days', '250'),
              seg('60+ Days', '0'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('75%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    // The credit has no share of the bar.
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('150%'), findsNothing);
    expect(find.textContaining('-100%'), findsNothing);
  });
}
