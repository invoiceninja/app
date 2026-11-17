import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/features/settings/widgets/settings_nav_row.dart';

/// A settings navigation row: a 56 px floor, one merged button for a screen
/// reader (title, status, count), and a chevron that answers hover.

Future<void> _pump(
  WidgetTester tester,
  Widget row, {
  InTheme theme = InTheme.light,
  double width = 600,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(theme),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 400),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(body: Center(child: row)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a 56 px floor, and a tap runs the action', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      SettingsNavRow(
        icon: Icons.credit_card_outlined,
        title: 'Payment Types',
        status: '12 of 14 shown',
        onTap: () => taps++,
      ),
    );

    expect(
      tester.getSize(find.byType(SettingsNavRow)).height,
      greaterThanOrEqualTo(SettingsNavRow.minHeight),
    );
    await tester.tap(find.text('Payment Types'));
    expect(taps, 1);
  });

  testWidgets('one button for a screen reader: title, status, count', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      SettingsNavRow(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Payment Gateways',
        status: 'Stripe · PayPal',
        count: 2,
        onTap: () {},
      ),
    );

    final node = tester.getSemantics(find.text('Payment Gateways'));
    expect(node.label, contains('Payment Gateways'));
    expect(node.label, contains('Stripe · PayPal'));
    expect(node.label, contains('2'));
    expect(
      node.label.indexOf('Payment Gateways'),
      lessThan(node.label.indexOf('Stripe')),
    );
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('the chevron darkens on hover', (tester) async {
    await _pump(
      tester,
      SettingsNavRow(
        icon: Icons.credit_card_outlined,
        title: 'Payment Types',
        onTap: () {},
      ),
    );
    final tokens = InTheme.light;
    Color chevron() =>
        tester.widget<Icon>(find.byIcon(Icons.chevron_right)).color!;
    expect(chevron(), tokens.ink3);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Payment Types')));
    await tester.pump();
    expect(chevron(), tokens.ink2);
  });

  testWidgets('a pending status keeps the row the height it will have', (
    tester,
  ) async {
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsNavRow(
            key: const Key('pending'),
            icon: Icons.account_balance_wallet_outlined,
            title: 'Payment Gateways',
            statusPending: true,
            onTap: () {},
          ),
          SettingsNavRow(
            key: const Key('answered'),
            icon: Icons.account_balance_wallet_outlined,
            title: 'Payment Gateways',
            status: 'Stripe',
            onTap: () {},
          ),
        ],
      ),
      textScale: 2,
    );

    expect(
      tester.getSize(find.byKey(const Key('pending'))).height,
      tester.getSize(find.byKey(const Key('answered'))).height,
    );
  });

  testWidgets('320 px, 2x text, dark: a long status ellipsizes, nothing '
      'overflows', (tester) async {
    await _pump(
      tester,
      SettingsNavRow(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Payment Gateways',
        status: List.filled(8, 'Authorize.Net').join(' · '),
        count: 8,
        warning: true,
        onTap: () {},
      ),
      theme: InTheme.dark,
      width: 320,
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
  });
}
