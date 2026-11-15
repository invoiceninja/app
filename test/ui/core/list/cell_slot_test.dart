import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/domain/columns/column_definition.dart';
import 'package:admin/ui/core/list/cell_slot.dart';
import 'package:admin/ui/core/widgets/cell_copy_hover.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';

/// Behavioural coverage for the wide-table cell now shared by every entity
/// list.
///
/// It replaced seventeen private `_CellSlot` copies that no test referenced —
/// which is how two of them drifted into a different brace style without
/// anyone noticing, and why a wrong entity passed to `valueBuilder` would have
/// been invisible. One test here now stands behind all seventeen tiles.
///
/// The width branch is the load-bearing part: it is what keeps a row's cells
/// lined up with `EntityListColumnHeaders`, whose `_HeaderCell<T>` resolves the
/// same `isFlex ? Expanded : SizedBox(width:)` decision on the header side.
class _Row {
  const _Row(this.name);
  final String name;
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    ColumnDefinition<_Row> column, {
    _Row entity = const _Row('Acme'),
  }) => tester.pumpWidget(
    MaterialApp(
      // CopyIconButton reads `context.inTheme`; it only mounts when the
      // column has a copy value, which is why one test needed this.
      theme: buildInTheme(InTheme.light),
      home: Scaffold(
        // A Row so `Expanded` is legal — the real host is the tile's Row.
        body: Row(
          children: [
            CellSlot<_Row>(
              column: column,
              entity: entity,
              child: const Text('CELL'),
            ),
          ],
        ),
      ),
    ),
  );

  ColumnDefinition<_Row> col({
    double? width,
    ColumnAlign align = ColumnAlign.start,
    String? Function(_Row)? valueBuilder,
    bool copiesCellName = false,
    Widget Function(_Row, BuildContext)? cellBuilder,
  }) => ColumnDefinition<_Row>(
    id: 'name',
    labelKey: 'name',
    width: width,
    align: align,
    valueBuilder: valueBuilder,
    copiesCellName: copiesCellName,
    cellBuilder: cellBuilder ?? (r, _) => Text(r.name),
  );

  testWidgets('a flex column expands; a sized one takes the declared width', (
    tester,
  ) async {
    // `width: null` is what makes a column flex — the identity column. Getting
    // this backwards silently knocks every following cell out of alignment
    // with its header.
    await pump(tester, col());
    expect(find.byType(Expanded), findsOneWidget);
    expect(
      tester.widgetList<SizedBox>(find.byType(SizedBox)).map((s) => s.width),
      isNot(contains(140.0)),
    );

    await pump(tester, col(width: 140));
    expect(find.byType(Expanded), findsNothing);
    expect(
      tester.widgetList<SizedBox>(find.byType(SizedBox)).map((s) => s.width),
      contains(140.0),
    );
  });

  testWidgets('align: end anchors the cell to the trailing edge', (
    tester,
  ) async {
    // The Align that wraps THIS cell's child — `find.byType(Align).first`
    // picks up an unrelated one from the Scaffold and passes even when the
    // branch is deleted.
    AlignmentGeometry alignOf() => tester
        .widget<Align>(
          find
              .ancestor(of: find.text('CELL'), matching: find.byType(Align))
              .first,
        )
        .alignment;

    await pump(tester, col(width: 100));
    expect(alignOf(), AlignmentDirectional.centerStart);

    await pump(tester, col(width: 100, align: ColumnAlign.end));
    expect(alignOf(), AlignmentDirectional.centerEnd);
  });

  testWidgets('the copy value comes from valueBuilder, fed THIS row', (
    tester,
  ) async {
    // The conversion renamed a per-file parameter (`quote:`, `category:`, …)
    // to `entity:` across seventeen call sites. Passing the wrong object here
    // would put another row's text on the clipboard and nothing would throw.
    await pump(
      tester,
      col(width: 100, valueBuilder: (r) => 'copy:${r.name}'),
      entity: const _Row('Globex'),
    );
    expect(
      tester.widget<CellCopyHover>(find.byType(CellCopyHover)).value,
      'copy:Globex',
    );
  });

  testWidgets('a column with no valueBuilder offers nothing to copy', (
    tester,
  ) async {
    // `CellCopyHover` suppresses the affordance on a null value — that is how
    // a dashed cell avoids offering to copy an em dash.
    await pump(tester, col(width: 100));
    expect(
      tester.widget<CellCopyHover>(find.byType(CellCopyHover)).value,
      isNull,
    );
  });

  testWidgets('the column align is forwarded to the copy affordance', (
    tester,
  ) async {
    await pump(tester, col(width: 100, align: ColumnAlign.end));
    expect(
      tester.widget<CellCopyHover>(find.byType(CellCopyHover)).align,
      ColumnAlign.end,
    );
  });

  group('a related record column (copiesCellName)', () {
    String? copied;
    setUp(() {
      copied = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    /// A cell whose label resolves [name] the way a `*NameLabel` does: later,
    /// from its own state, with no rebuild of the row.
    Future<ValueNotifier<String?>> pumpNameCell(
      WidgetTester tester, {
      String? name,
    }) async {
      final resolved = ValueNotifier<String?>(name);
      addTearDown(resolved.dispose);
      final column = col(
        width: 200,
        valueBuilder: (_) => 'Wpmbk5ezJn',
        copiesCellName: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          home: Scaffold(
            body: Row(
              children: [
                CellSlot<_Row>(
                  column: column,
                  entity: const _Row('Acme'),
                  child: ValueListenableBuilder<String?>(
                    valueListenable: resolved,
                    builder: (context, value, _) {
                      CellCopyNameScope.report(context, value);
                      return Text(value ?? '—');
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return resolved;
    }

    Future<void> hover(WidgetTester tester, String text) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text(text)));
      await tester.pumpAndSettle();
    }

    testWidgets('copies the name the label resolved, never the id', (
      tester,
    ) async {
      // The Client column's `valueBuilder` is the hashed `clientId`; the copy
      // icon beside "Acme Corp" used to put `Wpmbk5ezJn` on the clipboard.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final resolved = await pumpNameCell(tester);
        // The name lands on the label's own stream, after the row was built.
        resolved.value = 'Acme Corp';
        await tester.pump();

        await hover(tester, 'Acme Corp');
        await tester.tap(find.byType(CopyIconButton));
        await tester.pumpAndSettle();
        expect(copied, 'Acme Corp');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('offers nothing while the label shows a dash', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpNameCell(tester);
        await hover(tester, '—');
        // The slot stays mounted (the tree must not change shape when the
        // name lands) but is invisible and takes no pointer.
        final opacity = tester.widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byType(CopyIconButton),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(opacity.opacity, 0);
        await tester.tap(find.byType(CopyIconButton), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(copied, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    double iconOpacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byType(CopyIconButton),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    testWidgets('a parent rebuild under a resting pointer keeps the icon', (
      tester,
    ) async {
      // `CellSlot` builds a fresh child on every parent rebuild (a stream
      // emission, a selection change). Clearing the name on a new child hid
      // the icon and let the click through to the row.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final resolved = await pumpNameCell(tester, name: 'Acme Corp');
        await hover(tester, 'Acme Corp');
        expect(iconOpacity(tester), 1);

        // The same row, rebuilt from above with a new child instance.
        await tester.pumpWidget(
          MaterialApp(
            theme: buildInTheme(InTheme.light),
            home: Scaffold(
              body: Row(
                children: [
                  CellSlot<_Row>(
                    column: col(
                      width: 200,
                      valueBuilder: (_) => 'Wpmbk5ezJn',
                      copiesCellName: true,
                    ),
                    entity: const _Row('Acme'),
                    child: ValueListenableBuilder<String?>(
                      valueListenable: resolved,
                      builder: (context, value, _) {
                        CellCopyNameScope.report(context, value);
                        return Text(value ?? '—');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(iconOpacity(tester), 1);
        await tester.tap(find.byType(CopyIconButton));
        await tester.pumpAndSettle();
        expect(copied, 'Acme Corp');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a name that lands under a resting pointer shows the icon', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final resolved = await pumpNameCell(tester);
        await hover(tester, '—');
        expect(iconOpacity(tester), 0);

        // No pointer event, no rebuild from above: only the label's stream.
        resolved.value = 'Acme Corp';
        await tester.pumpAndSettle();
        expect(iconOpacity(tester), 1);
        await tester.tap(find.byType(CopyIconButton));
        await tester.pumpAndSettle();
        expect(copied, 'Acme Corp');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a row swapped into the slot does not inherit the last name', (
      tester,
    ) async {
      // A recycled row whose client id is empty draws a plain dash — no label,
      // so nothing reports — and must not offer the previous row's client.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpNameCell(tester, name: 'Acme Corp');
        await pump(
          tester,
          col(width: 200, valueBuilder: (_) => null, copiesCellName: true),
        );
        await hover(tester, 'CELL');
        await tester.tap(find.byType(CopyIconButton), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(copied, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('CellCopyHover.touchLongPressCopies', () {
    String? copied;
    setUp(() {
      copied = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<int> pumpCell(WidgetTester tester, {required bool optIn}) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          home: Scaffold(
            body: Center(
              child: InkWell(
                onTap: () => taps++,
                child: CellCopyHover(
                  value: 'Widget',
                  touchLongPressCopies: optIn,
                  child: const Text('Widget'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Widget'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Widget'));
      await tester.pumpAndSettle();
      return taps;
    }

    testWidgets('touch: a long-press copies and the row keeps its tap', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        expect(await pumpCell(tester, optIn: true), 1);
        expect(copied, 'Widget');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('touch: off by default — an entity list row owns the '
        'long-press', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pumpCell(tester, optIn: false);
        expect(copied, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
