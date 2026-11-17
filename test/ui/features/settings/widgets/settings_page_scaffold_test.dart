import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/unsaved_changes/unsaved_changes_guard.dart';
import 'package:admin/ui/core/widgets/toast_controller.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/view_models/settings_draft_view_model.dart';
import 'package:admin/ui/features/settings/widgets/settings_page_scaffold.dart';
import 'package:admin/ui/features/settings/widgets/settings_two_pane_scope.dart';

import '../../../../_localization_helper.dart';

/// A draft of one string, with the snapshot API the toolbar's Discard uses.
class _Host extends SettingsDraftHost {
  _Host({this.canSnapshot = true});

  final bool canSnapshot;
  String initial = 'a';
  String draftText = 'a';
  bool saving = false;

  void edit(String v) {
    draftText = v;
    notifyListeners();
  }

  @override
  Map<String, List<String>> get fieldErrors => const {};
  @override
  bool get isLoaded => true;
  @override
  bool get isDirty => draftText != initial;
  @override
  bool get isSaving => saving;
  @override
  String? get loadError => null;
  @override
  String? get submitError => null;
  @override
  void reset() {
    draftText = initial;
    notifyListeners();
  }

  @override
  Future<Object?> save() async {
    initial = draftText;
    notifyListeners();
    return draftText;
  }

  @override
  Future<void> load() async {}

  @override
  Object? draftSnapshot() => canSnapshot ? draftText : null;

  @override
  void restoreDraftSnapshot(Object snapshot) {
    if (snapshot is! String) return;
    draftText = snapshot;
    notifyListeners();
  }
}

class _FakeServices implements Services {
  @override
  final UnsavedChangesGuard unsavedChangesGuard = UnsavedChangesGuard();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late ToastController toasts;
  late SettingsLevelController level;

  setUp(() {
    toasts = ToastController();
    level = SettingsLevelController();
  });
  tearDown(() {
    toasts.dispose();
    level.dispose();
  });

  Future<void> pump(
    WidgetTester tester,
    _Host host, {
    double width = 1200,
    Widget body = const Text('BODY'),
    ValueListenable<bool>? saveVisible,
  }) {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Services>.value(value: _FakeServices()),
          ChangeNotifierProvider<ToastController>.value(value: toasts),
          ChangeNotifierProvider<SettingsLevelController>.value(value: level),
        ],
        child: MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: SettingsTwoPaneScope(
            isTwoPane: true,
            child: SettingsPageScaffold<_Host>(
              titleKey: 'localization',
              viewModel: host,
              saveVisible: saveVisible,
              body: body,
            ),
          ),
        ),
      ),
    );
  }

  final save = find.byKey(const ValueKey('settings_save'));
  final discard = find.byKey(const ValueKey('settings_discard'));
  final unsaved = find.byKey(const ValueKey('unsaved-label'));

  testWidgets('Save is a filled button, enabled only when dirty', (
    tester,
  ) async {
    final host = _Host();
    await pump(tester, host);

    expect(tester.widget(save), isA<FilledButton>());
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(discard, findsNothing);
    expect(unsaved, findsNothing);
    // 44 px tall: the bar's primary is a full-size target.
    expect(tester.getSize(save).height, greaterThanOrEqualTo(44));

    host.edit('b');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(discard, findsOneWidget);
    expect(unsaved, findsOneWidget);
  });

  testWidgets('the cluster reads [Save][Discard][?] from the start', (
    tester,
  ) async {
    final host = _Host()..edit('b');
    await pump(tester, host);

    final help = find.byKey(const ValueKey('settings_learn_more'));
    expect(help, findsOneWidget);
    final saveX = tester.getTopLeft(save).dx;
    final discardX = tester.getTopLeft(discard).dx;
    expect(saveX, lessThan(discardX));
    expect(discardX, lessThan(tester.getTopLeft(help).dx));
  });

  testWidgets('Discard resets with no dialog, and Undo puts the edit back', (
    tester,
  ) async {
    final host = _Host()..edit('typed');
    await pump(tester, host);

    await tester.tap(discard);
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(host.draftText, 'a');
    expect(host.isDirty, isFalse);

    final toast = toasts.toasts.single;
    expect(toast.message, 'Changes discarded');
    expect(toast.action?.label, 'Undo');
    toast.action!.onPressed();
    await tester.pump();
    expect(host.draftText, 'typed');
    expect(host.isDirty, isTrue);
    toasts.clearAll(); // its auto-dismiss timer
  });

  testWidgets('a host that cannot snapshot discards without Undo', (
    tester,
  ) async {
    final host = _Host(canSnapshot: false)..edit('typed');
    await pump(tester, host);

    await tester.tap(discard);
    await tester.pump();
    expect(host.isDirty, isFalse);
    expect(toasts.toasts.single.action, isNull);
    toasts.clearAll(); // its auto-dismiss timer
  });

  testWidgets('a narrow pane drops the Unsaved label but keeps Discard', (
    tester,
  ) async {
    final host = _Host()..edit('b');
    await pump(tester, host, width: 400);

    expect(unsaved, findsNothing);
    expect(discard, findsOneWidget);
  });

  testWidgets('on a phone Discard is an icon, so the title keeps its room', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final host = _Host()..edit('b');
      await pump(tester, host, width: 390);

      expect(discard, findsOneWidget);
      expect(tester.widget(discard), isA<IconButton>());
      expect(
        find.descendant(of: discard, matching: find.byType(Text)),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  Future<void> pressSave(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl+S saves a dirty draft, as the Save button does (D1)', (
    tester,
  ) async {
    final host = _Host();
    await pump(tester, host, body: const TextField());
    await tester.tap(find.byType(TextField));
    await tester.pump();

    // Clean: nothing to save, nothing happens.
    await pressSave(tester);
    expect(host.initial, 'a');

    host.edit('b');
    await tester.pump();
    await pressSave(tester);
    expect(host.initial, 'b');
    expect(host.isDirty, isFalse);
    // Let the "Saved" toast run out.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('Ctrl+S does nothing on a tab that hides Save', (tester) async {
    final host = _Host()..edit('b');
    final visible = ValueNotifier<bool>(false);
    addTearDown(visible.dispose);
    await pump(tester, host, body: const TextField(), saveVisible: visible);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await pressSave(tester);
    expect(host.initial, 'a');
  });
}
