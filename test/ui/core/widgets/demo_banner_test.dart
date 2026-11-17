import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/widgets/offline_banner.dart';

import '../../../_localization_helper.dart';

/// The demo build's strip: slim, in the info (accent) tokens, and dismissible
/// for the session only — the dismissal is a static in-memory notifier, never
/// a stored preference, so the next launch (the next visitor to a shared demo)
/// sees it again.
void main() {
  tearDown(() => OfflineBanner.demoBannerDismissed.value = false);

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: const Scaffold(
        body: Column(children: [OfflineBanner(isDemoBuild: true)]),
      ),
    ),
  );

  testWidgets('the ✕ hides it, and only in memory', (tester) async {
    await pump(tester);
    expect(find.text('Demo mode'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Demo mode'), findsNothing);
    expect(OfflineBanner.demoBannerDismissed.value, isTrue);

    // A remount in the same session stays dismissed.
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    expect(find.text('Demo mode'), findsNothing);
  });

  testWidgets('is drawn in the info tokens', (tester) async {
    await pump(tester);
    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text('Demo mode'), matching: find.byType(Material))
          .first,
    );
    expect(material.color, InTheme.light.accentSoft);
  });

  testWidgets('is slim with a pointer: one line around a 28 px ✕', (
    tester,
  ) async {
    await pump(tester);
    final height = tester
        .getSize(
          find
              .ancestor(
                of: find.text('Demo mode'),
                matching: find.byType(Material),
              )
              .first,
        )
        .height;
    expect(height, lessThanOrEqualTo(30));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('keeps a 44 px ✕ on touch', (tester) async {
    await pump(tester);
    expect(
      tester.getSize(find.byTooltip('Dismiss')).height,
      greaterThanOrEqualTo(InSizes.touchTarget),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
