import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/models/domain/enabled_modules.dart';
import 'package:admin/ui/features/settings/settings_search_catalog.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/view_models/settings_draft_view_model.dart';
import 'package:admin/ui/features/settings/views/basic/online_payments/payment_setup_card.dart';
import 'package:admin/ui/features/settings/widgets/no_gateway_warning.dart'
    show kAddGatewayRoute;
import 'package:admin/ui/features/settings/widgets/settings_form_shell.dart';
import 'package:admin/ui/features/settings/widgets/settings_nav_row.dart';

import '../../../../../_localization_helper.dart';

/// Payment Settings' first card (`docs/settings-screens.md` § Payment
/// Settings opens with a setup card of two navigation rows): the gateways row
/// in its three states — pending, none (the page's warning), some — the
/// group-scope display-order variant, and a types count that follows the
/// live draft.

class _Host extends SettingsDraftHost {
  _Host(this._settings);
  CompanySettings _settings;

  @override
  CompanySettings get settings => _settings;
  @override
  CompanySettings get draftSettings => _settings;
  @override
  Company? get draft => const Company();
  @override
  Map<String, List<String>> get fieldErrors => const {};
  @override
  void updateSettings(CompanySettings Function(CompanySettings) edit) {
    _settings = edit(_settings);
    notifyListeners();
  }

  @override
  bool get isLoaded => true;
  @override
  bool get isDirty => false;
  @override
  bool get isSaving => false;
  @override
  String? get loadError => null;
  @override
  String? get submitError => null;
  @override
  void reset() {}
  @override
  Future<Object?> save() async => null;
  @override
  Future<void> load() async {}
}

const _typeIds = ['1', '2', '3', '4', '5'];

Future<GoRouter> _pump(
  WidgetTester tester, {
  required List<String>? gateways,
  _Host? host,
  SettingsLevelController? level,
  InTheme theme = InTheme.light,
  double width = 800,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SettingsFormShell(
            sections: [
              PaymentSetupSection(
                gatewayNames: gateways,
                paymentTypeIds: _typeIds,
              ),
            ],
          ),
        ),
      ),
      GoRoute(path: kAddGatewayRoute, builder: (_, _) => const Text('ADD')),
      GoRoute(
        path: kCompanyGatewaysRoute,
        builder: (_, _) => const Text('GATEWAYS'),
      ),
      GoRoute(path: kPaymentTypesRoute, builder: (_, _) => const Text('TYPES')),
    ],
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsLevelController>.value(
          value: level ?? SettingsLevelController(),
        ),
        ChangeNotifierProvider<SettingsDraftHost>.value(
          value: host ?? _Host(const CompanySettings()),
        ),
      ],
      child: MaterialApp.router(
        theme: buildInTheme(theme),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

const _noGateway =
    "No payment gateway is connected, so clients can't pay online yet.";

void main() {
  testWidgets('pending: the title over a blank line — never the warning', (
    tester,
  ) async {
    await _pump(tester, gateways: null);

    expect(find.text('Payment Gateways'), findsOneWidget);
    expect(find.text('Add Payment Gateway'), findsNothing);
    expect(find.text(_noGateway), findsNothing);
    final row = tester.widget<SettingsNavRow>(
      find.widgetWithText(SettingsNavRow, 'Payment Gateways'),
    );
    expect(row.warning, isFalse);
    expect(row.statusPending, isTrue);
  });

  testWidgets('none: the row is the warning and goes to the add screen', (
    tester,
  ) async {
    await _pump(tester, gateways: const []);

    expect(find.text('Add Payment Gateway'), findsOneWidget);
    expect(find.text(_noGateway), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    // One way to add a gateway on the page, not two.
    expect(find.byType(OutlinedButton), findsNothing);

    await tester.tap(find.text('Add Payment Gateway'));
    await tester.pumpAndSettle();
    expect(find.text('ADD'), findsOneWidget);
  });

  testWidgets('some: names joined, a count, and the gateways list', (
    tester,
  ) async {
    await _pump(tester, gateways: const ['Stripe', 'PayPal']);

    expect(find.text('Payment Gateways'), findsOneWidget);
    expect(find.text('Stripe · PayPal'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

    await tester.tap(find.text('Payment Gateways'));
    await tester.pumpAndSettle();
    expect(find.text('GATEWAYS'), findsOneWidget);
  });

  testWidgets('the types count follows the live draft', (tester) async {
    final host = _Host(const CompanySettings());
    await _pump(tester, gateways: const ['Stripe'], host: host);

    expect(find.text('5 of 5 shown'), findsOneWidget);
    host.updateSettings((s) => s.copyWith(hiddenPaymentTypes: '2,4'));
    await tester.pump();
    expect(find.text('3 of 5 shown'), findsOneWidget);

    await tester.tap(find.text('Payment Types'));
    await tester.pumpAndSettle();
    expect(find.text('TYPES'), findsOneWidget);
  });

  testWidgets('group scope: only the display-order row, and no warning', (
    tester,
  ) async {
    final level = SettingsLevelController()
      ..setLevel(SettingsLevel.group, targetId: 'g1', targetName: 'VIP');
    await _pump(tester, gateways: const [], level: level);

    expect(find.text('Gateway display order'), findsOneWidget);
    expect(
      find.text(
        'No gateways configured. Add one at company scope to set a portal '
        'order.',
      ),
      findsOneWidget,
    );
    expect(find.text('Payment Types'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('focus order: gateways, then types', (tester) async {
    await _pump(tester, gateways: const ['Stripe']);

    final rows = find.byType(InkWell);
    expect(
      tester.getTopLeft(rows.at(0)).dy,
      lessThan(tester.getTopLeft(rows.at(1)).dy),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      Focus.of(tester.element(find.text('Payment Gateways'))).hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      Focus.of(tester.element(find.text('Payment Types'))).hasFocus,
      isTrue,
    );
  });

  group('search offers exactly the setup labels that render', () {
    // A hit reveals its field by the label on screen, so a key offered in a
    // state that draws a different label opens the page and flashes nothing.
    const setupKeys = [
      'company_gateways',
      'add_gateway',
      'gateway_display_order',
      'payment_types',
    ];
    final l10n = bundledLocalization();
    final allModules = kEnabledModulesOrder.fold<int>(
      0,
      (mask, m) => mask | m.bitmask,
    );
    Set<String> offered({required bool cascade, required int? gateways}) => {
      for (final key in setupKeys)
        for (final h in searchSettings(
          l10n.lookup(key),
          l10n,
          scope: SettingsSearchScope(
            enabledModules: allModules,
            isAdminOrOwner: true,
            isCascade: cascade,
            isHosted: true,
            activeGatewayCount: gateways,
          ),
        ))
          if (h.route == '/settings/online_payments' && h.fieldKey == key) key,
    };

    // A count not known (the command palette) offers both gateway labels —
    // fail open; the settings search watches it, so this is every state it
    // can be in.
    for (final (cascade, gateways) in [
      (false, const <String>[]),
      (false, const ['Stripe']),
      (true, const <String>[]),
      (true, const ['Stripe']),
    ]) {
      testWidgets('${cascade ? 'group' : 'company'} scope, '
          '${gateways.length} gateways', (tester) async {
        final level = SettingsLevelController();
        if (cascade) {
          level.setLevel(SettingsLevel.group, targetId: 'g1', targetName: 'G');
        }
        await _pump(tester, gateways: gateways, level: level);
        final keys = offered(cascade: cascade, gateways: gateways.length);
        expect(keys, isNotEmpty);
        for (final key in setupKeys) {
          expect(
            find.text(l10n.lookup(key)),
            keys.contains(key) ? findsOneWidget : findsNothing,
            reason: '$key ${keys.contains(key) ? 'offered' : 'not offered'}',
          );
        }
      });
    }
  });

  for (final theme in [InTheme.light, InTheme.dark]) {
    testWidgets(
      '320 px at 2x text (${theme == InTheme.dark ? 'dark' : 'light'})'
      ': nothing overflows',
      (tester) async {
        await _pump(
          tester,
          gateways: const ['Stripe', 'PayPal', 'Authorize.Net', 'Square'],
          theme: theme,
          width: 320,
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Payment Types'), findsOneWidget);
      },
    );
  }
}
