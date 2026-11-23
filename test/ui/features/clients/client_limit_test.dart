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
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/repositories/_repository_helpers.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/domain/upgrade/client_usage.dart';
import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/domain/upgrade/upgrade_launcher.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/ui/core/edit/generic_edit_view_model.dart';
import 'package:admin/ui/features/clients/widgets/client_limit.dart';

import '../../../_localization_helper.dart';

AuthSession _session({String plan = '', int hostedClientCount = 5}) =>
    AuthSession(
      baseUrl: 'https://invoicing.co',
      isHosted: true,
      accountId: 'acct',
      currentCompanyId: 'co',
      userId: 'u1',
      plan: plan,
      planExpires: plan.isEmpty ? '' : '2099-01-01',
      hostedClientCount: hostedClientCount,
      companies: const [],
    );

/// A [ClientUsage] whose server total is [total] (null: never answers).
ClientUsage _usage({int? total, String plan = ''}) => ClientUsage(
  session: ValueNotifier<AuthSession?>(_session(plan: plan)),
  fetchCount: (_) =>
      total == null ? Completer<int?>().future : Future.value(total),
  watchQueued: (_) => Stream.value((creates: 0, removals: 0)),
);

class _FakeAuth implements AuthRepository {
  _FakeAuth(AuthSession s) : session = ValueNotifier<AuthSession?>(s);
  @override
  final ValueNotifier<AuthSession?> session;
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// The signed-in hosted session, which says whose purchases are withheld.
class _FakeServices implements Services {
  _FakeServices(AuthSession s) : auth = _FakeAuth(s);
  @override
  final AuthRepository auth;
  @override
  Formatter? formatterIfReady(String companyId) => null;
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Future<void> _pump(
  WidgetTester tester, {
  required ClientUsage? usage,
  required Widget Function(BuildContext context) child,
  bool signedIn = false,
  AuthSession? session,
}) async {
  Widget app = MaterialApp(
    theme: buildInTheme(InTheme.light),
    localizationsDelegates: kTestLocalizationsDelegates,
    supportedLocales: kTestSupportedLocales,
    home: Scaffold(body: Builder(builder: child)),
  );
  if (signedIn) {
    app = Provider<Services>.value(
      value: _FakeServices(session ?? _session()),
      child: app,
    );
  }
  await tester.pumpWidget(
    usage == null
        ? app
        : ChangeNotifierProvider<ClientUsage>.value(value: usage, child: app),
  );
  await tester.pump();
}

/// A client form's view model, its save state set by hand.
class _FormVm extends GenericEditViewModel<String> {
  _FormVm({super.original}) : super(initialDraft: '');

  bool saving = false;
  String? sent;
  Map<String, List<String>> errors = const {};

  @override
  bool get isSaving => saving;
  @override
  String? get lastSentDraft => sent;
  @override
  Map<String, List<String>> get fieldErrors => errors;
  @override
  Future<SaveResult<String>> performSave() => throw UnimplementedError();
}

const _atLimit =
    'You have used all 5 clients on the Free plan. Upgrade to add more.';
const _over =
    'You have 11 clients. The Free plan allows 5. All your clients are kept. '
    'Upgrade to add new ones.';

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
      await tester.tap(find.byKey(const ValueKey('client_limit_close')));
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
      expect(find.text('3 of 5 clients on the Free plan'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('client_usage_upgrade')),
        findsOneWidget,
      );
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

    testWidgets('well under the cap the list stays quiet', (tester) async {
      // At 1 or 2 of 5 the signup, checklist and Plan screen have said it; a
      // line on every visit to the list would be clutter.
      for (final total in [0, 1, 2]) {
        final usage = _usage(total: total);
        await _pump(
          tester,
          usage: usage,
          child: (_) => const ClientUsageBanner(),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('client_usage_banner')),
          findsNothing,
          reason: '$total of 5',
        );
      }
    });

    testWidgets('Upgrade on the usage line is a full touch target', (
      tester,
    ) async {
      final usage = _usage(total: 4);
      await _pump(
        tester,
        usage: usage,
        child: (_) => const ClientUsageBanner(),
      );
      await tester.pump();
      final size = tester.getSize(
        find.byKey(const ValueKey('client_usage_upgrade')),
      );
      expect(size.height, greaterThanOrEqualTo(44));
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

  group('confirmNewClientSave', () {
    Future<bool?> save(
      WidgetTester tester,
      ClientUsage usage,
      _FormVm vm,
    ) async {
      bool? allowed;
      await _pump(
        tester,
        usage: usage,
        child: (context) => TextButton(
          onPressed: () async =>
              allowed = await confirmNewClientSave(context, vm),
          child: const Text('save'),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      return allowed;
    }

    testWidgets('a create at the cap is not sent; the dialog says why', (
      tester,
    ) async {
      // A deep link or the command palette reaches the blank form without
      // the gate; Save must not queue a create the server will refuse.
      expect(await save(tester, _usage(total: 5), _FormVm()), isFalse);
      expect(find.byType(ClientLimitDialog), findsOneWidget);
    });

    testWidgets('an edit at the cap saves', (tester) async {
      expect(
        await save(tester, _usage(total: 5), _FormVm(original: 'c1')),
        isTrue,
      );
      expect(find.byType(ClientLimitDialog), findsNothing);
    });

    testWidgets('a create under the cap saves', (tester) async {
      expect(await save(tester, _usage(total: 4), _FormVm()), isTrue);
    });
  });

  group('ClientLimitFormBanner', () {
    Future<void> pumpBanner(
      WidgetTester tester,
      ClientUsage usage,
      _FormVm vm,
    ) async {
      await _pump(
        tester,
        usage: usage,
        child: (_) => ClientLimitFormBanner(vm: vm),
      );
      await tester.pump();
    }

    final banner = find.byKey(const ValueKey('client_limit_form_banner'));

    testWidgets('a blank form at the cap says so', (tester) async {
      await pumpBanner(tester, _usage(total: 5), _FormVm());
      expect(banner, findsOneWidget);
    });

    testWidgets('not on the form whose own save reached the cap', (
      tester,
    ) async {
      // The fifth client's create is queued, and counted, before the form
      // leaves: the form that added it must not read "limit reached".
      final saving = _FormVm()..saving = true;
      await pumpBanner(tester, _usage(total: 5), saving);
      expect(banner, findsNothing);
      final saved = _FormVm()..sent = 'Acme';
      await pumpBanner(tester, _usage(total: 5), saved);
      expect(banner, findsNothing);
    });

    testWidgets('a save the server refused for the cap says so', (
      tester,
    ) async {
      final vm = _FormVm()
        ..sent = 'Acme'
        ..errors = const {
          'id': ['limit'],
        };
      await pumpBanner(tester, _usage(total: 3), vm);
      expect(banner, findsOneWidget);
    });
  });

  testWidgets('the dialog says the server\'s words when the cap is unknown', (
    tester,
  ) async {
    await _pump(
      tester,
      usage: null,
      child: (context) => TextButton(
        onPressed: () => showClientLimitDialog(
          context,
          detail: 'You have hit the client limit.',
        ),
        child: const Text('open'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('You have hit the client limit.'), findsOneWidget);
    expect(find.byKey(const ValueKey('client_limit_upgrade')), findsOneWidget);
  });

  group('showImportClientLimit', () {
    Future<bool?> fail(
      WidgetTester tester,
      ClientUsage usage,
      Object error,
    ) async {
      bool? shown;
      await _pump(
        tester,
        usage: usage,
        child: (context) => TextButton(
          onPressed: () => shown = showImportClientLimit(context, error),
          child: const Text('import'),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('import'));
      await tester.pumpAndSettle();
      return shown;
    }

    const limitError = ValidationException('invalid', {
      'files.client': ["You've hit the 5 client limit on Free accounts."],
    });

    testWidgets('an import refused for the cap gets Upgrade, not a toast', (
      tester,
    ) async {
      expect(await fail(tester, _usage(total: 3), limitError), isTrue);
      expect(find.byType(ClientLimitDialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('client_limit_upgrade')),
        findsOneWidget,
      );
    });

    testWidgets('the import preview\'s hashed copy is the same refusal', (
      tester,
    ) async {
      const hashed = ValidationException('invalid', {
        'column_map.client': ['limit'],
      });
      expect(await fail(tester, _usage(total: 3), hashed), isTrue);
    });

    testWidgets('a paid plan keeps the plain error', (tester) async {
      expect(
        await fail(tester, _usage(total: 3, plan: 'pro'), limitError),
        isFalse,
      );
      expect(find.byType(ClientLimitDialog), findsNothing);
    });

    testWidgets('another failure keeps the plain error', (tester) async {
      expect(
        await fail(tester, _usage(total: 3), Exception('offline')),
        isFalse,
      );
      const other = ValidationException('invalid', {
        'skip_header': ['bad'],
      });
      expect(await fail(tester, _usage(total: 3), other), isFalse);
    });
  });
  // A store build whose hosted service does not sell in-app to the account
  // (docs/free-plan-limits.md): every limit is still said in full, only the
  // "Upgrade …" sentence and the button go.
  group('a store build that sells nothing', () {
    const atLimitInfo = 'You have used all 5 clients on the Free plan.';
    const overInfo =
        'You have 11 clients. The Free plan allows 5. All your clients are '
        'kept.';
    final upgradeKeys = [
      const ValueKey('client_limit_upgrade'),
      const ValueKey('client_usage_upgrade'),
      const ValueKey('client_limit_form_upgrade'),
    ];
    void expectNoUpgrade() {
      for (final key in upgradeKeys) {
        expect(find.byKey(key), findsNothing, reason: '$key');
      }
      expect(find.textContaining('Upgrade'), findsNothing);
    }

    setUp(() {
      debugStoreBillingOverride = true;
      debugInAppPurchasesOfferedOverride = false;
    });
    tearDown(() {
      debugStoreBillingOverride = null;
      debugInAppPurchasesOfferedOverride = null;
    });

    Future<void> openDialog(WidgetTester tester, {int used = 5}) async {
      await _pump(
        tester,
        usage: null,
        signedIn: true,
        child: (context) => TextButton(
          onPressed: () => showClientLimitDialog(context, limit: 5, used: used),
          child: const Text('open'),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('the dialog states the limit, with Close only', (tester) async {
      await openDialog(tester);
      expect(find.text(atLimitInfo), findsOneWidget);
      expect(
        find.text('Archived and deleted clients count toward the limit.'),
        findsOneWidget,
      );
      expectNoUpgrade();
      await tester.tap(find.byKey(const ValueKey('client_limit_close')));
      await tester.pumpAndSettle();
      expect(find.text(atLimitInfo), findsNothing);
    });

    testWidgets('over the cap the clients are still said to be kept', (
      tester,
    ) async {
      await openDialog(tester, used: 11);
      expect(find.text(overInfo), findsOneWidget);
      expectNoUpgrade();
    });

    testWidgets('the list line keeps its count, without Upgrade', (
      tester,
    ) async {
      await _pump(
        tester,
        usage: _usage(total: 4),
        signedIn: true,
        child: (_) => const ClientUsageBanner(),
      );
      await tester.pump();
      expect(find.text('4 of 5 clients on the Free plan'), findsOneWidget);
      expectNoUpgrade();
    });

    testWidgets('the form notice states the limit, without Upgrade', (
      tester,
    ) async {
      await _pump(
        tester,
        usage: _usage(total: 5),
        signedIn: true,
        child: (_) => ClientLimitFormBanner(vm: _FormVm()),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('client_limit_form_banner')),
        findsOneWidget,
      );
      expect(find.text(atLimitInfo), findsOneWidget);
      expectNoUpgrade();
    });

    testWidgets('an import over the cap says nothing was imported', (
      tester,
    ) async {
      const limitError = ValidationException('invalid', {
        'files.client': ["You've hit the 5 client limit on Free accounts."],
      });
      await _pump(
        tester,
        usage: _usage(total: 3),
        signedIn: true,
        child: (context) => TextButton(
          onPressed: () => showImportClientLimit(context, limitError),
          child: const Text('import'),
        ),
      );
      await tester.tap(find.text('import'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This import would take you past the 5 clients the Free plan '
          'allows, so nothing was imported.',
        ),
        findsOneWidget,
      );
      expectNoUpgrade();
    });

    // A cap the app does not know: the server's `limit_clients` words are
    // never shown here (they may ask the user to upgrade), ours are.
    const serverWords = "You've hit the 5 client limit on Free accounts.";
    const unknownCapInfo = "You have reached the Free plan's client limit.";

    testWidgets('a refused save with no known cap says ours, not the '
        "server's", (tester) async {
      final vm = _FormVm()
        ..sent = 'Acme'
        ..errors = const {
          'id': [serverWords],
        };
      await _pump(
        tester,
        usage: null,
        signedIn: true,
        session: _session(hostedClientCount: 0),
        child: (_) => ClientLimitFormBanner(vm: vm),
      );
      await tester.pump();
      expect(find.text(unknownCapInfo), findsOneWidget);
      expect(find.text(serverWords), findsNothing);
      expectNoUpgrade();
    });

    testWidgets('the dialog with no known cap says ours', (tester) async {
      await _pump(
        tester,
        usage: null,
        signedIn: true,
        session: _session(hostedClientCount: 0),
        child: (context) => TextButton(
          onPressed: () => showClientLimitDialog(context),
          child: const Text('open'),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(unknownCapInfo), findsOneWidget);
      expectNoUpgrade();
    });

    testWidgets("a client's field errors carry ours, the cap when known", (
      tester,
    ) async {
      late Map<String, List<String>> known;
      late Map<String, List<String>> unknown;
      late Map<String, List<String>> other;
      await _pump(
        tester,
        usage: _usage(total: 5),
        signedIn: true,
        child: (context) {
          known = presentClientFieldErrors(context, const {
            'id': [serverWords],
            'name': ['required'],
          });
          other = presentClientFieldErrors(context, const {
            'name': ['required'],
          });
          return const SizedBox();
        },
      );
      expect(known, {
        'id': [atLimitInfo],
        'name': ['required'],
      });
      expect(other, {
        'name': ['required'],
      });
      await _pump(
        tester,
        usage: null,
        signedIn: true,
        session: _session(hostedClientCount: 0),
        child: (context) {
          unknown = presentClientFieldErrors(context, const {
            'id': [serverWords],
          });
          return const SizedBox();
        },
      );
      expect(unknown, {
        'id': [unknownCapInfo],
      });
    });

    testWidgets("off the store the server's words stand", (tester) async {
      debugStoreBillingOverride = false;
      late Map<String, List<String>> errors;
      await _pump(
        tester,
        usage: null,
        signedIn: true,
        session: _session(hostedClientCount: 0),
        child: (context) {
          errors = presentClientFieldErrors(context, const {
            'id': [serverWords],
          });
          return const SizedBox();
        },
      );
      expect(errors, {
        'id': [serverWords],
      });
    });

    testWidgets('once the config sells here, Upgrade is back', (tester) async {
      debugInAppPurchasesOfferedOverride = true;
      await openDialog(tester);
      expect(find.text(_atLimit), findsOneWidget);
      expect(
        find.byKey(const ValueKey('client_limit_upgrade')),
        findsOneWidget,
      );
    });

    testWidgets('desktop keeps Upgrade, whatever the offer', (tester) async {
      debugStoreBillingOverride = false;
      await openDialog(tester);
      expect(find.text(_atLimit), findsOneWidget);
      expect(
        find.byKey(const ValueKey('client_limit_upgrade')),
        findsOneWidget,
      );
    });
  });
}
