import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/features/settings/widgets/cascade_tabbed_settings_shell.dart';
import 'package:admin/ui/features/settings/widgets/settings_form_shell.dart';

import '../../../../_localization_helper.dart';

/// The preview button is a page-level action: it rides each tab's intro row
/// (`SettingsPageActions` → `SettingsFormShell`), beside the tab's intro
/// sentence and its own action — never a bar of its own above the tabs, which
/// spent a whole row on one button and pushed the intro onto the next
/// (`docs/settings-screens.md` § A page's intro and its actions share one
/// row).

const _intro = 'What your documents print.';

class _Host extends StatefulWidget {
  const _Host({required this.initialIndex});

  final int initialIndex;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final TabController controller = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialIndex,
  );
  final ValueNotifier<bool> previewShown = ValueNotifier<bool>(false);

  @override
  void dispose() {
    controller.dispose();
    previewShown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CascadeSidePaneLayout(
      tabBarView: TabBarView(
        controller: controller,
        children: [
          SettingsFormShell(
            subtitle: _intro,
            sections: const [SizedBox(height: 40, child: Text('A'))],
          ),
          SettingsFormShell(
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                onPressed: () {},
                child: const Text('LEAD'),
              ),
            ],
            sections: const [SizedBox(height: 40, child: Text('B'))],
          ),
        ],
      ),
      sidePane: const Text('PANE'),
      previewShown: previewShown,
      fullScreenBuilder: (_) => const SizedBox.shrink(),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required int tab,
  double textScale = 1,
}) async {
  // The layout keys off its own constraints, so the surface is the width.
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: _Host(initialIndex: tab)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _intro$ => find.byKey(const ValueKey('settings-page-subtitle'));

void main() {
  testWidgets('tablet band → Show Preview shares the intro row, and the '
      'first card follows it directly', (tester) async {
    await _pump(tester, width: 800, tab: 0);

    final button = find.widgetWithText(OutlinedButton, 'Show Preview');
    expect(button, findsOneWidget);
    expect(_intro$, findsOneWidget);
    // One row: the button is level with the intro's (only) line, at the end.
    expect(
      tester.getCenter(_intro$).dy,
      moreOrLessEquals(tester.getCenter(button).dy, epsilon: 2),
    );
    expect(
      tester.getTopLeft(button).dx,
      greaterThan(tester.getTopRight(_intro$).dx),
    );
    // Nothing between the row and the card.
    expect(
      tester.getTopLeft(find.text('A')).dy,
      greaterThan(tester.getBottomLeft(button).dy),
    );
    expect(
      tester.getTopLeft(find.text('A')).dy - tester.getBottomLeft(button).dy,
      lessThanOrEqualTo(InSpacing.xl),
    );
    // The pane is behind the toggle here.
    expect(find.text('PANE'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tablet band → a tab\'s own action sits beside Show Preview', (
    tester,
  ) async {
    await _pump(tester, width: 800, tab: 1);

    final preview = find.widgetWithText(OutlinedButton, 'Show Preview');
    expect(find.text('LEAD'), findsOneWidget);
    expect(preview, findsOneWidget);
    expect(
      tester.getCenter(find.text('LEAD')).dy,
      moreOrLessEquals(tester.getCenter(preview).dy),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tablet band → shown, Hide Preview stays above the pane', (
    tester,
  ) async {
    await _pump(tester, width: 800, tab: 0);

    await tester.tap(find.text('Show Preview'));
    await tester.pumpAndSettle();

    expect(find.text('PANE'), findsOneWidget);
    expect(find.text('Hide Preview'), findsOneWidget);
    expect(_intro$, findsNothing);

    await tester.tap(find.text('Hide Preview'));
    await tester.pumpAndSettle();
    expect(find.text('PANE'), findsNothing);
    expect(_intro$, findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('side by side → no preview button, the tab action still shows', (
    tester,
  ) async {
    await _pump(tester, width: 1200, tab: 1);

    expect(find.text('LEAD'), findsOneWidget);
    expect(find.text('PANE'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(
      tester.getTopLeft(find.text('LEAD')).dx,
      lessThan(tester.getTopLeft(find.text('PANE')).dx),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone 390 at 1x → the intro and Preview share the top row', (
    tester,
  ) async {
    await _pump(tester, width: 390, tab: 0);

    expect(tester.takeException(), isNull);
    final button = find.widgetWithText(OutlinedButton, 'Preview');
    expect(button, findsOneWidget);
    // Same row: level with the intro's first line, at the end, and the
    // first card right under the row.
    expect(
      tester.getCenter(button).dy,
      moreOrLessEquals(tester.getTopLeft(_intro$).dy + 10, epsilon: 2),
    );
    expect(
      tester.getTopLeft(button).dx,
      greaterThan(tester.getTopRight(_intro$).dx),
    );
    expect(tester.getTopRight(button).dx, lessThanOrEqualTo(390));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone 320 at 2x → the intro column would be unreadable, so '
      'Preview drops under it; nothing overflows', (tester) async {
    await _pump(tester, width: 320, tab: 0, textScale: 2);

    expect(tester.takeException(), isNull);
    final button = find.widgetWithText(OutlinedButton, 'Preview');
    expect(button, findsOneWidget);
    expect(
      tester.getTopLeft(button).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(_intro$).dy),
    );
    expect(tester.getTopRight(button).dx, lessThanOrEqualTo(320));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone 320 at 1x → nothing overflows', (tester) async {
    await _pump(tester, width: 320, tab: 0);

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopRight(find.widgetWithText(OutlinedButton, 'Preview')).dx,
      lessThanOrEqualTo(320),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
