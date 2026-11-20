// About carries Invoice Ninja's privacy policy and terms (App Review
// 5.1.1(i)), except on a white-labeled self-hosted install, which shows
// nothing of Invoice Ninja's own.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/ui/features/shell/widgets/about_dialog.dart';

import '_shell_test_helpers.dart';

void main() {
  Future<void> openAbout(WidgetTester tester, ShellFixture fixture) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppAboutDialog(context),
            child: const Text('trigger'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
  }

  final privacy = find.byKey(const ValueKey('legal_privacy_policy'));

  testWidgets('hosted: the legal links are there', (tester) async {
    final fixture = await buildFixture(
      companies: const [FakeCompany(id: 'c1', name: 'Acme')],
    );
    addTearDown(fixture.dispose);
    await openAbout(tester, fixture);

    expect(privacy, findsOneWidget);
  });

  testWidgets('an unlicensed self-host keeps them', (tester) async {
    final fixture = await buildFixture(
      companies: const [FakeCompany(id: 'c1', name: 'Acme')],
      isHosted: false,
      plan: '',
    );
    addTearDown(fixture.dispose);
    await openAbout(tester, fixture);

    expect(privacy, findsOneWidget);
  });

  testWidgets('a white-labeled self-host has none', (tester) async {
    final fixture = await buildFixture(
      companies: const [FakeCompany(id: 'c1', name: 'Acme')],
      isHosted: false,
      plan: 'white_label',
    );
    addTearDown(fixture.dispose);
    await openAbout(tester, fixture);

    expect(privacy, findsNothing);
    expect(find.byKey(const ValueKey('legal_terms_of_service')), findsNothing);
  });
}
