import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/shortcuts/key_binding.dart';
import 'package:admin/app/shortcuts/shortcut_catalog.dart';
import 'package:admin/ui/core/widgets/shortcut_tooltip.dart';
import 'package:admin/ui/features/shell/widgets/company_switcher_button.dart';

import '_shell_test_helpers.dart';

// Switch company ships unbound (⌘K is the palette's, docs/keyboard.md), so the
// switcher's tooltip must read the live binding — it hardcoded `⌘ K`.
void main() {
  late ShellFixture fixture;

  setUp(() async {
    fixture = await buildFixture(
      companies: const [
        FakeCompany(id: 'c1', name: 'Acme'),
        FakeCompany(id: 'c2', name: 'Globex'),
      ],
    );
  });

  tearDown(() async => fixture.dispose());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    wrapWithShell(
      fixture.services,
      Center(
        child: SizedBox(
          width: 240,
          child: CompanySwitcherButton(
            session: fixture.services.auth.session.value!,
          ),
        ),
      ),
    ),
  );

  testWidgets('unbound: a plain label, no keycaps', (tester) async {
    await pump(tester);
    expect(find.byType(ShortcutTooltip), findsNothing);
    expect(find.byTooltip('Switch Company'), findsOneWidget);
  });

  testWidgets('bound by the user: the tooltip shows that chord', (
    tester,
  ) async {
    // `restoreFromJson`, not `setBinding`: the latter persists through the
    // real database, whose stream never settles under the test's fake clock.
    fixture.services.keyboardShortcuts.restoreFromJson(
      jsonEncode({
        ShortcutActionIds.openCompanyPicker: KeyBinding.logical(
          LogicalKeyboardKey.keyJ.keyId,
          usesPrimary: true,
        ).toJson(),
      }),
    );
    await pump(tester);
    final tooltip = tester.widget<ShortcutTooltip>(
      find.byType(ShortcutTooltip),
    );
    expect(tooltip.keys.last, 'J');
  });
}
