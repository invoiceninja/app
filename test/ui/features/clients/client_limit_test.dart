// The Free plan's client cap in the UI (docs/free-plan-limits.md): New client
// at the cap opens the Upgrade dialog instead of a form the server would
// refuse, an account over the cap is told its clients are kept (never "11 of
// 5"), an unknown count lets the create through, and the clients list shows a
// quiet usage line only to a hosted Free plan.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/upgrade/client_usage.dart';
import 'package:admin/ui/features/clients/widgets/client_limit.dart';

import '../../../_localization_helper.dart';

AuthSession _session({String plan = ''}) => AuthSession(
  baseUrl: 'https://invoicing.co',
  isHosted: true,
  accountId: 'acct',
  currentCompanyId: 'co',
  userId: 'u1',
  plan: plan,
  planExpires: plan.isEmpty ? '' : '2099-01-01',
  hostedClientCount: 5,
  companies: const [],
);

/// A [ClientUsage] whose server total is [total] (null: never answers).
ClientUsage _usage({int? total, String plan = ''}) => ClientUsage(
  session: ValueNotifier<AuthSession?>(_session(plan: plan)),
  fetchCount: () =>
      total == null ? Completer<int?>().future : Future.value(total),
  watchQueuedCreates: (_) => Stream.value(0),
);

Future<void> _pump(
  WidgetTester tester, {
  required ClientUsage? usage,
  required Widget Function(BuildContext context) child,
}) async {
  final app = MaterialApp(
    theme: buildInTheme(InTheme.light),
    localizationsDelegates: kTestLocalizationsDelegates,
    supportedLocales: kTestSupportedLocales,
    home: Scaffold(body: Builder(builder: child)),
  );
  await tester.pumpWidget(
    usage == null
        ? app
        : ChangeNotifierProvider<ClientUsage>.value(value: usage, child: app),
  );
  await tester.pump();
}

const _atLimit = 'The Free plan includes 5 clients. Upgrade to add more.';
const _over =
    'You have 11 clients. The Free plan allows 5, so your existing clients are '
    'kept, and adding more needs an upgrade.';

void main() {
  group('interceptNewClientAtLimit', () {
    Future<bool?> tapNew(WidgetTester tester, ClientUsage? usage) async {
      bool? intercepted;
      await _pump(
        tester,
        usage: usage,
        child: (context) => TextButton(
          onPressed: () => intercepted = interceptNewClientAtLimit(context),
          child: const Text('new'),
        ),
      );
      await tester.tap(find.text('new'));
      await tester.pumpAndSettle();
      return intercepted;
    }

    testWidgets('at the cap: the dialog, not the form', (tester) async {
      final usage = _usage(total: 5);
      expect(await tapNew(tester, usage), isTrue);
      expect(find.text('Client Limit'), findsOneWidget);
      expect(find.text(_atLimit), findsOneWidget);
      expect(
        find.text('Archived and deleted clients count toward the limit.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('client_limit_upgrade')),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text(_atLimit), findsNothing);
    });

    testWidgets('over the cap: the clients are kept, never "11 of 5"', (
      tester,
    ) async {
      final usage = _usage(total: 11);
      expect(await tapNew(tester, usage), isTrue);
      expect(find.text(_over), findsOneWidget);
      expect(find.textContaining('11 of 5'), findsNothing);
    });

    testWidgets('under the cap: through', (tester) async {
      final usage = _usage(total: 3);
      expect(await tapNew(tester, usage), isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('an unknown count lets the create through', (tester) async {
      final usage = _usage();
      expect(await tapNew(tester, usage), isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('no ClientUsage (self-hosted tests, fakes): through', (
      tester,
    ) async {
      expect(await tapNew(tester, null), isFalse);
    });
  });

  testWidgets('the dialog answers true for Upgrade', (tester) async {
    bool? result;
    await _pump(
      tester,
      usage: null,
      child: (context) => TextButton(
        onPressed: () async => result = await showDialog<bool>(
          context: context,
          builder: (_) => const ClientLimitDialog(limit: 5, used: 5),
        ),
        child: const Text('open'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('client_limit_upgrade')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  group('ClientUsageBanner', () {
    testWidgets('a Free plan sees its usage and Upgrade', (tester) async {
      final usage = _usage(total: 3);
      await _pump(
        tester,
        usage: usage,
        child: (_) => const ClientUsageBanner(),
      );
      await tester.pump();
      expect(find.text('3 of 5 free clients used'), findsOneWidget);
      expect(find.text('Upgrade'), findsOneWidget);
    });

    testWidgets('over the cap it says so plainly', (tester) async {
      final usage = _usage(total: 11);
      await _pump(
        tester,
        usage: usage,
        child: (_) => const ClientUsageBanner(),
      );
      await tester.pump();
      expect(
        find.text('You have 11 clients. The Free plan allows 5.'),
        findsOneWidget,
      );
    });

    testWidgets('a paid plan sees nothing', (tester) async {
      final usage = _usage(total: 3, plan: 'pro');
      await _pump(
        tester,
        usage: usage,
        child: (_) => const ClientUsageBanner(),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('client_usage_banner')), findsNothing);
    });
  });
}
