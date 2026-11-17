import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/features/settings/widgets/no_gateway_warning.dart';

import '../../../../_localization_helper.dart';

void main() {
  Future<GoRouter> pump(
    WidgetTester tester,
    Stream<int> count, {
    NoGatewayWarningStyle style = NoGatewayWarningStyle.inset,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: NoGatewayWarning(
              messageKey: 'no_gateway_connected',
              style: style,
              countStream: count,
            ),
          ),
        ),
        GoRoute(
          path: kAddGatewayRoute,
          builder: (_, _) => const Text('new gateway'),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        routerConfig: router,
      ),
    );
    await tester.pump();
    return router;
  }

  const message =
      "No payment gateway is connected, so clients can't pay "
      'online yet.';

  testWidgets('no gateway: the warning and its action show', (tester) async {
    await pump(tester, Stream.value(0));
    expect(find.text(message), findsOneWidget);
    expect(find.text('Add Payment Gateway'), findsOneWidget);
  });

  testWidgets('the action opens the new-gateway screen', (tester) async {
    await pump(tester, Stream.value(0));
    await tester.tap(find.text('Add Payment Gateway'));
    await tester.pumpAndSettle();
    expect(find.text('new gateway'), findsOneWidget);
  });

  testWidgets('the stripe variant shows the same action', (tester) async {
    await pump(tester, Stream.value(0), style: NoGatewayWarningStyle.stripe);
    expect(find.text(message), findsOneWidget);
    expect(find.text('Add Payment Gateway'), findsOneWidget);
  });

  testWidgets('a company with a gateway sees nothing', (tester) async {
    await pump(tester, Stream.value(2));
    expect(find.text(message), findsNothing);
  });

  testWidgets('nothing flashes before the count has answered', (tester) async {
    final pending = StreamController<int>();
    addTearDown(pending.close);
    await pump(tester, pending.stream);
    expect(find.text(message), findsNothing);
  });
}
