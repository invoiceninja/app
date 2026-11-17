import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/list/entity_list_constants.dart';
import 'package:admin/ui/core/widgets/content_panel.dart';

/// `ContentPanel` — the white card the Tasks time views and the Activity feed
/// draw their rows in. The part no screen test measures: it owns the bottom
/// safe inset, so what it holds is told there is none.

const _window = Size(390, 844);
const _inset = 34.0;

class _Probe extends StatelessWidget {
  const _Probe();

  static MediaQueryData? seen;

  @override
  Widget build(BuildContext context) {
    seen = MediaQuery.of(context);
    return const SizedBox.expand();
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required bool wide,
  double? bottom,
}) async {
  tester.view.physicalSize = _window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[InTheme.light],
      ),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(padding: const EdgeInsets.only(bottom: _inset)),
          child: ContentPanel(
            wide: wide,
            bottom: bottom,
            child: const _Probe(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('narrow: 16 each side, and the panel pays the safe inset', (
    tester,
  ) async {
    await _pump(tester, wide: false);
    final card = tester.getRect(find.byType(ContentPanelCard));
    expect(card.left, 16);
    expect(card.right, _window.width - 16);
    // `InSpacing.md` is 8 under 600 px, plus the inset beneath it.
    expect(card.top, 8);
    expect(card.bottom, _window.height - 8 - _inset);
    expect(_Probe.seen!.padding.bottom, 0);
  });

  testWidgets('wide: the list table inset, plus the safe inset below', (
    tester,
  ) async {
    await _pump(tester, wide: true);
    final card = tester.getRect(find.byType(ContentPanelCard));
    final inset = entityListTableInset(compact: false);
    expect(card.left, inset.start);
    expect(card.right, _window.width - inset.end);
    expect(card.top, inset.top);
    expect(card.bottom, _window.height - inset.bottom - _inset);
  });

  testWidgets('an explicit bottom is the whole gap, inset included', (
    tester,
  ) async {
    await _pump(tester, wide: false, bottom: 120);
    final card = tester.getRect(find.byType(ContentPanelCard));
    expect(card.bottom, _window.height - 120);
    expect(_Probe.seen!.padding.bottom, 0);
  });

  testWidgets('the card is the list chrome: surface, border, r3, shadow1', (
    tester,
  ) async {
    await _pump(tester, wide: false);
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(ContentPanelCard),
        matching: find.byType(Container),
      ),
    );
    final d = box.decoration! as BoxDecoration;
    const t = InTheme.light;
    expect(d.color, t.surface);
    expect(d.border, Border.all(color: t.border));
    expect(d.borderRadius, BorderRadius.circular(InRadii.r3));
    expect(d.boxShadow, t.shadow1);
  });
}
