import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/quick_create.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_create_fab.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_create_strip.dart';

import '../../../../_localization_helper.dart';

/// The wide dashboard's create buttons. The strip takes plain options, so it
/// is pumped here without `Services`; `dashboard_screen_test.dart` covers which
/// options the screen passes and where a pick navigates.
void main() {
  // Real glyph widths — how many buttons fit is the thing under test.
  setUpAll(_loadInterTight);

  final allOptions = [
    for (final type in kQuickCreateEntities)
      QuickCreateOption(type: type, icon: Icons.circle_outlined),
  ];

  Future<void> pumpStrip(
    WidgetTester tester, {
    List<QuickCreateOption>? options,
    ValueChanged<QuickCreateOption>? onCreate,
    double width = 600,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        theme: buildInTheme(InTheme.light),
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            // Loose, as the top bar hands it: the strip may be narrower than
            // its slot, never wider.
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: DashboardCreateStrip(
                options: options ?? allOptions,
                onCreate: onCreate ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The split button's ▾ — the strip's one menu.
  Finder splitToggle() => find.byIcon(Icons.keyboard_arrow_down);

  /// The create buttons drawn inline, in order — the primary's main part,
  /// then the outlined secondaries. The ▾ has no label and is not counted.
  List<String> inlineLabels(WidgetTester tester) => [
    for (final e in find.byType(FilledButton).evaluate())
      if (_hasText(e)) _labelOf(tester, e),
    for (final e in find.byType(OutlinedButton).evaluate()) _labelOf(tester, e),
  ];

  Future<List<String>> openSplitMenu(WidgetTester tester) async {
    await tester.tap(splitToggle());
    await tester.pumpAndSettle();
    return [
      for (final e in find.byType(MenuItemButton).evaluate())
        tester
                .widget<Text>(
                  find
                      .descendant(
                        of: find.byWidget(e.widget),
                        matching: find.byType(Text),
                      )
                      .first,
                )
                .data ??
            '',
    ];
  }

  testWidgets('the first option is the primary, a split button at the '
      'trailing end', (tester) async {
    await pumpStrip(tester);
    final labels = inlineLabels(tester);
    // `kQuickCreateEntities` order: the primary as its full phrase, the
    // secondaries as bare nouns beside the `+`.
    expect(labels.take(3), ['New Invoice', 'Quote', 'Payment']);
    // Two filled halves of one control: the create and its ▾.
    expect(find.byType(FilledButton), findsNWidgets(2));
    expect(splitToggle(), findsOneWidget);
    final primary = tester.getRect(
      find.widgetWithText(FilledButton, 'New Invoice'),
    );
    for (final e in find.byType(OutlinedButton).evaluate()) {
      expect(
        tester.getRect(find.byWidget(e.widget)).right,
        lessThan(primary.left),
      );
    }
    // The ▾ is attached to the primary's end.
    final toggle = tester.getRect(splitToggle());
    expect(toggle.left, greaterThan(primary.right));
    expect(toggle.left - primary.right, lessThan(20));
  });

  testWidgets('there is no More button and no horizontal ⋯', (tester) async {
    for (final width in [280.0, 420.0, 600.0, 1400.0]) {
      await pumpStrip(tester, width: width);
      expect(find.text('More'), findsNothing, reason: '@ $width');
      expect(find.byIcon(Icons.more_vert), findsNothing, reason: '@ $width');
      expect(find.byIcon(Icons.more_horiz), findsNothing, reason: '@ $width');
    }
  });

  testWidgets('a squeeze folds the secondaries, never the primary', (
    tester,
  ) async {
    await pumpStrip(tester, width: 280);
    expect(tester.takeException(), isNull);
    expect(find.text('New Invoice'), findsOneWidget);
    expect(splitToggle(), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('the floor it reports holds the split primary', (tester) async {
    late double floor;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        theme: buildInTheme(InTheme.light),
        home: Builder(
          builder: (context) {
            floor = dashboardCreateStripMinWidth(context, allOptions);
            return const SizedBox();
          },
        ),
      ),
    );
    await pumpStrip(tester, width: floor);
    expect(tester.takeException(), isNull);
    expect(find.text('New Invoice'), findsOneWidget);
    expect(splitToggle(), findsOneWidget);
    expect(
      tester.getSize(find.byType(DashboardCreateStrip)).width,
      lessThanOrEqualTo(floor),
    );
  });

  testWidgets('the ▾ lists every other create, in order, whatever fits', (
    tester,
  ) async {
    for (final width in [280.0, 1400.0]) {
      await pumpStrip(tester, width: width);
      final menu = await openSplitMenu(tester);
      // Full phrases, every option but the primary, in the sheet's order —
      // the secondaries drawn inline included, so the menu never changes
      // with the window.
      expect(menu, hasLength(allOptions.length - 1), reason: '@ $width');
      expect(menu.first, 'New Quote', reason: '@ $width');
      expect(menu, contains('Enter Expense'), reason: '@ $width');
      expect(menu, isNot(contains('New Invoice')), reason: '@ $width');
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a narrower slot shows fewer buttons, never an overflow', (
    tester,
  ) async {
    await pumpStrip(tester, width: 600);
    final wide = inlineLabels(tester).length;
    await pumpStrip(tester, width: 300);
    final narrow = inlineLabels(tester).length;
    expect(narrow, lessThan(wide));
    expect(tester.takeException(), isNull);
  });

  testWidgets('larger text moves the cut instead of clipping a label', (
    tester,
  ) async {
    // 380 px: room for the three capped buttons at normal size, so only the
    // text size can move the cut.
    await pumpStrip(tester, width: 380);
    final normal = inlineLabels(tester).length;
    // The app's largest in-app setting: never more buttons, never an overflow.
    await pumpStrip(tester, width: 380, textScale: 1.4);
    expect(inlineLabels(tester).length, lessThanOrEqualTo(normal));
    expect(tester.takeException(), isNull);
    // An OS scale on top of it: the cut has to move.
    await pumpStrip(tester, width: 380, textScale: 2);
    expect(inlineLabels(tester).length, lessThan(normal));
    expect(tester.takeException(), isNull);
  });

  testWidgets('never grows past its cap, however wide the bar', (tester) async {
    await pumpStrip(tester, width: 1400);
    expect(
      tester.getSize(find.byType(DashboardCreateStrip)).width,
      lessThanOrEqualTo(kDashboardCreateStripMaxWidth),
    );
    expect(inlineLabels(tester).length, lessThan(allOptions.length));
  });

  testWidgets('three buttons at most, the rest in the ▾ menu', (tester) async {
    await pumpStrip(tester, width: 1400);
    expect(inlineLabels(tester).length, kDashboardCreateStripMaxButtons);
    expect(splitToggle(), findsOneWidget);
  });

  testWidgets('every button is one height', (tester) async {
    await pumpStrip(tester, width: 600);
    final heights = {
      for (final e in find.byType(FilledButton).evaluate())
        tester.getSize(find.byWidget(e.widget)).height,
      for (final e in find.byType(OutlinedButton).evaluate())
        tester.getSize(find.byWidget(e.widget)).height,
    };
    expect(heights, hasLength(1), reason: 'heights: $heights');
  });

  testWidgets('a tap on a button creates that entity', (tester) async {
    final created = <QuickCreateOption>[];
    await pumpStrip(tester, onCreate: created.add);
    await tester.tap(find.text('Quote'));
    await tester.tap(find.text('New Invoice'));
    expect(created.map((o) => o.type), [EntityType.quote, EntityType.invoice]);
  });

  // An action is not `+ <noun>`: it wears its own icon and its phrase.
  testWidgets('Scan Receipt reads as itself, not as "+ Expense"', (
    tester,
  ) async {
    final created = <QuickCreateOption>[];
    await pumpStrip(
      tester,
      options: const [
        QuickCreateOption(type: EntityType.invoice, icon: Icons.circle),
        QuickCreateOption.scanReceipt(),
      ],
      onCreate: created.add,
    );
    final button = find.ancestor(
      of: find.text('Scan Receipt'),
      matching: find.byType(OutlinedButton),
    );
    expect(button, findsOneWidget);
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.receipt_long_outlined),
      ),
      findsOneWidget,
    );
    await tester.tap(button);
    expect(created.single.action, QuickCreateAction.scanReceipt);
  });

  testWidgets('a pick from the ▾ creates that entity', (tester) async {
    final created = <QuickCreateOption>[];
    await pumpStrip(tester, width: 420, onCreate: created.add);
    await openSplitMenu(tester);
    await tester.tap(find.byType(MenuItemButton).last);
    await tester.pumpAndSettle();
    expect(created.map((o) => o.type), [kQuickCreateEntities.last]);
  });

  testWidgets('with one option the primary is a plain button, no ▾', (
    tester,
  ) async {
    await pumpStrip(tester, options: allOptions.take(1).toList(), width: 600);
    expect(inlineLabels(tester), ['New Invoice']);
    expect(splitToggle(), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('a user who may create nothing gets no strip', (tester) async {
    await pumpStrip(tester, options: const []);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(tester.getSize(find.byType(DashboardCreateStrip)), Size.zero);
  });

  testWidgets('a screen reader hears the full phrase, and can activate it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final created = <QuickCreateOption>[];
    await pumpStrip(tester, onCreate: created.add);
    // "Enter Payment", not the bare noun on the button.
    final payment = find.bySemanticsLabel('Enter Payment');
    expect(payment, findsOneWidget);
    expect(
      tester.getSemantics(payment),
      matchesSemantics(
        label: 'Enter Payment',
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}

bool _hasText(Element button) => find
    .descendant(of: find.byWidget(button.widget), matching: find.byType(Text))
    .evaluate()
    .isNotEmpty;

String _labelOf(WidgetTester tester, Element button) {
  final text = find.descendant(
    of: find.byWidget(button.widget),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(text.first).data ?? '';
}

Future<void> _loadInterTight() async {
  final loader = FontLoader(kSansFontFamily)
    ..addFont(
      Future.value(
        File(
          'assets/fonts/InterTight.ttf',
        ).readAsBytesSync().buffer.asByteData(),
      ),
    );
  await loader.load();
}
