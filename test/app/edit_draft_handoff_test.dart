// "Add to invoice" hands an EXISTING invoice, with the new lines appended, to
// its edit screen for review (invoiceninja/app#207).
//
// The draft used to ride as route `extra`, and the edit route was keyed on the
// record id alone. So when the Invoices branch already held an editor for that
// invoice — the reporter had opened it to delete the line the quote brought
// over — go_router reused it, `buildVm` never ran again, and the app "switched
// to the invoice" showing only the old lines. The draft now rides on
// `Services` and bumps the edit route's key, which recreates the editor.
//
// Uses the production `buildEntityRouteBlock` and `goEntityEditWithDraft`.

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/router.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/unsaved_changes/unsaved_changes_guard.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../_localization_helper.dart';

/// Only the hand-off surface is real; anything else the code under test
/// reaches for fails loudly.
class _HandoffServices implements Services {
  final Map<String, int> _gen = {};
  Object? _draft;
  String? _key;

  @override
  final ValueNotifier<int> seedGenTick = ValueNotifier(0);

  @override
  final UnsavedChangesGuard unsavedChangesGuard = UnsavedChangesGuard();

  @override
  void stageEditDraft(String basePath, String id, Object draft) {
    final key = '$basePath/$id';
    _draft = draft;
    _key = key;
    _gen[key] = (_gen[key] ?? 0) + 1;
    seedGenTick.value++;
  }

  @override
  int editSeedGenFor(String basePath, String id) => _gen['$basePath/$id'] ?? 0;

  @override
  T? takeEditDraft<T>(String basePath, String id) {
    final draft = _draft;
    if (_key != '$basePath/$id' || draft is! T) return null;
    _draft = null;
    _key = null;
    return draft;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Stands in for the invoice edit screen: what it shows is fixed by what it
/// took when its State was built — exactly like `buildVm`.
class _Editor extends StatefulWidget {
  const _Editor({required this.id});

  final String id;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final String shown;

  @override
  void initState() {
    super.initState();
    shown =
        context.read<Services>().takeEditDraft<String>(
          '/invoices',
          widget.id,
        ) ??
        'saved:${widget.id}';
  }

  @override
  Widget build(BuildContext context) => Text('EDIT $shown');
}

void main() {
  late _HandoffServices services;
  late GoRouter router;

  Future<void> pumpApp(WidgetTester tester, {required String at}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    services = _HandoffServices();
    router = GoRouter(
      initialLocation: at,
      routes: [
        buildEntityRouteBlock(
          basePath: '/invoices',
          list: (_, _) => const Scaffold(body: Text('LIST')),
          create: null,
          detail: (_, _) => const Text('DETAIL'),
          edit: (_, state) => _Editor(id: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      Provider<Services>.value(
        value: services,
        child: MaterialApp.router(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A context inside the router, as an action's would be. (Not the list's
  /// own: a full-width editor takes it offstage.)
  BuildContext appContext(WidgetTester tester) =>
      router.routerDelegate.navigatorKey.currentContext!;

  testWidgets('a hand-off reaches an editor already open on that invoice', (
    tester,
  ) async {
    await pumpApp(tester, at: '/invoices/i1/edit?view=full');
    expect(find.text('EDIT saved:i1'), findsOneWidget);

    var announced = false;
    final went = await goEntityEditWithDraft(
      appContext(tester),
      '/invoices',
      'i1',
      'with-task-line',
      announce: () => announced = true,
    );
    await tester.pumpAndSettle();

    expect(went, isTrue);
    expect(announced, isTrue);
    expect(find.text('EDIT with-task-line'), findsOneWidget);
    expect(find.text('EDIT saved:i1'), findsNothing);
  });

  testWidgets('a second hand-off to the same invoice replaces the first', (
    tester,
  ) async {
    await pumpApp(tester, at: '/invoices');

    await goEntityEditWithDraft(appContext(tester), '/invoices', 'i1', 'one');
    await tester.pumpAndSettle();
    expect(find.text('EDIT one'), findsOneWidget);

    await goEntityEditWithDraft(appContext(tester), '/invoices', 'i1', 'two');
    await tester.pumpAndSettle();
    expect(find.text('EDIT two'), findsOneWidget);
  });

  testWidgets('a rebuild of the open editor neither recreates it nor takes a '
      'draft staged for another invoice', (tester) async {
    await pumpApp(tester, at: '/invoices/i1/edit?view=full');

    // Bumps `seedGenTick`, so the i1 route rebuilds — with its key unchanged.
    services.stageEditDraft('/invoices', 'i2', 'for-i2');
    await tester.pumpAndSettle();

    expect(find.text('EDIT saved:i1'), findsOneWidget);
    expect(services.takeEditDraft<String>('/invoices', 'i2'), 'for-i2');
  });

  testWidgets('unsaved edits elsewhere are asked about, and keeping them '
      'cancels the hand-off', (tester) async {
    await pumpApp(tester, at: '/invoices/i1/edit?view=full');
    final dirty = ValueNotifier(true);
    addTearDown(dirty.dispose);
    final unregister = services.unsavedChangesGuard.register(
      isDirty: () => dirty.value,
      source: dirty,
    );
    addTearDown(unregister);

    var announced = false;
    final pending = goEntityEditWithDraft(
      appContext(tester),
      '/invoices',
      'i1',
      'with-task-line',
      announce: () => announced = true,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(await pending, isFalse);
    expect(announced, isFalse);
    expect(find.text('EDIT saved:i1'), findsOneWidget);
    // Nothing left staged to ambush the next ordinary edit.
    expect(services.takeEditDraft<String>('/invoices', 'i1'), isNull);
  });
}
