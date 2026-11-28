// ⌘F / Ctrl+F falls back to the screen's search field. A record or an editor
// with line items binds the chord to its own find lower in the tree, and that
// wins; where its find is disabled, or nothing below binds it, the shell's
// fallback (`FindFocusSearchAction`) focuses the on-stage search field, as `/`
// does. Beta feedback (Nov 2026): Ctrl+F on the invoice list did nothing.
//
// The real shell cannot be pumped, so this builds the same two layers: the
// shell's map and action above, a record's below.

import 'package:admin/app/search_focus_registry.dart';
import 'package:admin/ui/core/utils/find_chord.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Harness extends StatefulWidget {
  const _Harness({
    required this.registry,
    required this.canFind,
    required this.onFind,
  });

  final SearchFocusRegistry registry;
  final bool Function() canFind;
  final VoidCallback onFind;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final search = FocusNode(debugLabel: 'list search');
  final record = FocusNode(debugLabel: 'record');
  late final shellMap = findChordShortcuts(
    intent: const FindFocusSearchIntent(),
  );
  late final recordMap = findChordShortcuts();

  @override
  void dispose() {
    search.dispose();
    record.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Shortcuts(
      shortcuts: shellMap,
      child: Actions(
        actions: <Type, Action<Intent>>{
          FindFocusSearchIntent: FindFocusSearchAction(widget.registry),
        },
        child: Scaffold(
          body: Column(
            children: [
              TextField(key: const ValueKey('search'), focusNode: search),
              Expanded(
                child: Shortcuts(
                  shortcuts: recordMap,
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      FindChordIntent: FindChordAction(
                        onFind: widget.onFind,
                        canFind: widget.canFind,
                      ),
                    },
                    child: Focus(
                      focusNode: record,
                      autofocus: true,
                      child: const TextField(key: ValueKey('record_field')),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<bool> _pressFind(WidgetTester tester) async {
  final apple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final modifier = apple
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
  return handled;
}

void main() {
  late SearchFocusRegistry registry;
  late int finds;
  late bool canFind;

  setUp(() {
    registry = SearchFocusRegistry();
    finds = 0;
    canFind = false;
  });

  Future<_HarnessState> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      _Harness(
        registry: registry,
        canFind: () => canFind,
        onFind: () => finds++,
      ),
    );
    await tester.pump();
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    registry.claim(state.search);
    return state;
  }

  testWidgets('a find below wins while it is enabled', (tester) async {
    canFind = true;
    final state = await pump(tester);
    expect(state.record.hasPrimaryFocus, isTrue);

    expect(await _pressFind(tester), isTrue);
    expect(finds, 1);
    expect(state.search.hasFocus, isFalse);
  });

  testWidgets('a disabled find below falls through to the search field', (
    tester,
  ) async {
    final state = await pump(tester);

    expect(await _pressFind(tester), isTrue);
    expect(finds, 0);
    expect(state.search.hasPrimaryFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('is ⌘F on macOS, never Ctrl+F', (tester) async {
    final state = await pump(tester);

    expect(await _pressFind(tester), isTrue);
    expect(state.search.hasPrimaryFocus, isTrue);

    // ⌃F is Cocoa's forward-a-character: it must not move the focus.
    state.record.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(state.record.hasPrimaryFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('fires from inside a text field', (tester) async {
    final state = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('record_field')));
    await tester.pump();
    expect(state.search.hasFocus, isFalse);

    expect(await _pressFind(tester), isTrue);
    expect(state.search.hasPrimaryFocus, isTrue);
  });

  testWidgets('with no search field on stage, the key is not consumed', (
    tester,
  ) async {
    final state = await pump(tester);
    registry.release(state.search);

    expect(await _pressFind(tester), isFalse);
    expect(state.record.hasPrimaryFocus, isTrue);
  });
}
