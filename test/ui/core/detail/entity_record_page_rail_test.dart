// The wide rail layout of `EntityRecordPage`: tabs and lists under the lead,
// the reference cards in a column at the end edge.
//
// Three things this layout has to keep, each of which an earlier look at a
// rail gave as a reason not to build one (`EntityRecordColumn`'s doc):
// the strip still pins, the tab body keeps its State when the window crosses
// the threshold, and nothing changes below it.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/detail/entity_record_page.dart';

/// Counts its own builds' State: a remount would reset it.
class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  int taps = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: () => setState(() => taps++),
          child: Text('taps $taps'),
        ),
        const SizedBox(height: 3000),
      ],
    );
  }
}

Widget _page({bool withRail = true}) => MaterialApp(
  theme: buildInTheme(InTheme.light),
  home: Scaffold(
    body: EntityRecordPage(
      top: const SizedBox(height: 600, child: Text('top')),
      lead: withRail ? const SizedBox(height: 120, child: Text('lead')) : null,
      rail: withRail ? const SizedBox(height: 900, child: Text('rail')) : null,
      tabStrip: const SizedBox(height: 44, child: Text('strip')),
      tabBody: const _Body(),
    ),
  ),
);

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('wide: the lists lead and the cards sit in a rail at the end', (
    tester,
  ) async {
    _size(tester, 1400);
    await tester.pumpWidget(_page());

    expect(find.text('top'), findsNothing);
    expect(find.text('lead'), findsOneWidget);
    // The strip starts right under the lead, not under 600 px of cards.
    expect(tester.getTopLeft(find.text('strip')).dy, lessThan(200));
    // The rail is the end column, kRecordRailWidth wide.
    final rail = tester.getRect(find.text('rail'));
    final strip = tester.getRect(find.text('strip'));
    expect(rail.left, greaterThan(strip.left + 800));
    expect(1400 - rail.left, lessThanOrEqualTo(kRecordRailWidth + 32));
  });

  testWidgets('wide: the strip still pins once the lead has scrolled away', (
    tester,
  ) async {
    _size(tester, 1400);
    await tester.pumpWidget(_page());
    final before = tester.getTopLeft(find.text('strip')).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pump();

    expect(before, greaterThan(100));
    expect(tester.getTopLeft(find.text('strip')).dy, closeTo(0, 1));
    // The rail scrolls with the page: one scroll view.
    expect(find.text('lead'), findsNothing);
  });

  testWidgets('below the threshold nothing moves', (tester) async {
    _size(tester, kRecordRailMinWidth - 1);
    await tester.pumpWidget(_page());

    expect(find.text('top'), findsOneWidget);
    expect(find.text('lead'), findsNothing);
    expect(find.text('rail'), findsNothing);
    expect(tester.getTopLeft(find.text('strip')).dy, greaterThan(600));
  });

  testWidgets('a host with no rail keeps the one layout at any width', (
    tester,
  ) async {
    _size(tester, 1900);
    await tester.pumpWidget(_page(withRail: false));

    expect(find.text('top'), findsOneWidget);
    expect(tester.getTopLeft(find.text('strip')).dy, greaterThan(600));
  });

  testWidgets('the tab body keeps its State across the threshold', (
    tester,
  ) async {
    _size(tester, 1400);
    await tester.pumpWidget(_page());
    await tester.tap(find.text('taps 0'));
    await tester.pump();
    expect(find.text('taps 1'), findsOneWidget);

    // Narrower: out of the rail layout.
    tester.view.physicalSize = const Size(1000, 900);
    await tester.pump();
    expect(find.text('top'), findsOneWidget);
    expect(find.text('taps 1'), findsOneWidget);

    // And back.
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pump();
    expect(find.text('lead'), findsOneWidget);
    expect(find.text('taps 1'), findsOneWidget);
  });
}
