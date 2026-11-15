import 'dart:io';
import 'dart:math' as math;

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/widgets/qr_code_image.dart';
import 'package:admin/ui/core/widgets/toast_controller.dart';
import 'package:admin/ui/features/settings/widgets/tap_to_pay_tile.dart';
import 'package:admin/ui/features/terminal/view_models/tap_to_pay_enable_view_model.dart';
import 'package:admin/ui/features/terminal/views/tap_to_pay_enable_screen.dart';
import 'package:admin/ui/features/terminal/widgets/collect_stage_layout.dart';
import 'package:admin/ui/features/terminal/widgets/location_pre_alert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../_localization_helper.dart';
import '_collect_stage_harness.dart';
import '_terminal_fakes.dart';

/// The in-person payment screens in every theme the app can show
/// ([kAllAppThemes]: the six presets, and the user's own accent over a light
/// and a dark one): each state builds without an error, takes its colours
/// from the theme's tokens only, stays readable, and keeps the payment code
/// black on white (docs/in-person-payments.md § Themes).
void main() {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  double ratio(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  test('the screens name no colour of their own: tokens only', () {
    const files = [
      'lib/ui/features/terminal/views/collect_card_payment_screen.dart',
      'lib/ui/features/terminal/views/tap_to_pay_enable_screen.dart',
      'lib/ui/features/terminal/widgets/collect_stage_layout.dart',
      'lib/ui/features/terminal/widgets/pay_another_way.dart',
      'lib/ui/features/terminal/widgets/location_pre_alert.dart',
      'lib/ui/features/settings/widgets/tap_to_pay_tile.dart',
    ];
    final literal = RegExp(r'Color(\.from\w+)?\(|Colors\.(?!transparent\b)');
    for (final path in files) {
      final lines = File(path).readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        expect(
          literal.hasMatch(line),
          isFalse,
          reason: '$path:${i + 1} names a colour; read it from InTheme',
        );
      }
    }
  });

  group('readable in every theme', () {
    for (final (name, build) in kAllAppThemes) {
      test(name, () {
        final t = build().extension<InTheme>()!;
        final ownAccent = name.contains('_accent_');
        void check(String what, Color fg, Color bg, double atLeast) => expect(
          ratio(fg, bg),
          greaterThanOrEqualTo(atLeast),
          reason: '$name: $what',
        );
        for (final (ground, bg) in [
          ('surface', t.surface),
          ('surfaceAlt', t.surfaceAlt),
        ]) {
          // Titles, amounts and body text; then captions.
          check('ink on $ground', t.ink, bg, 7);
          check('ink2 on $ground', t.ink2, bg, 4.5);
          check('ink3 on $ground', t.ink3, bg, 3.5);
          // An error under a field.
          check('overdue on $ground', t.overdue, bg, 4.4);
        }
        // A tag's or a note's words on its tint.
        for (final tone in StageTone.values) {
          final (ink, soft) = tone.colors(t);
          check('ink on ${tone.name}', t.ink, soft, 7);
          // Its mark (an icon, a dot) beside those words. The user's own
          // accent is theirs: a near-black one on a dark theme reads low
          // everywhere the app draws accent on accentSoft.
          if (tone == StageTone.accent && ownAccent) continue;
          check('${tone.name} mark on its tint', ink, soft, 2.8);
        }
        // The primary action — the Tap to Pay on iPhone button — whatever
        // accent the user chose.
        check('label on the primary button', t.onAccent, t.accent, 4.3);
      });
    }
  });

  /// The code is drawn black on a white card whatever the theme, or a phone
  /// camera can't read it.
  void expectQrBlackOnWhite(WidgetTester tester) {
    final qr = tester.widget<QrImageView>(
      find.descendant(
        of: find.byType(QrCodeImage),
        matching: find.byType(QrImageView),
      ),
    );
    expect(qr.backgroundColor, const Color(0xFFFFFFFF));
    expect(qr.eyeStyle.color, const Color(0xFF000000));
    expect(qr.dataModuleStyle.color, const Color(0xFF000000));
  }

  group('collect: every stage under every theme', () {
    Future<void> everyTheme(
      WidgetTester tester,
      CollectHarness h, {
      bool qr = false,
    }) async {
      for (final (name, build) in kAllAppThemes) {
        await h.show(tester, build());
        expect(tester.takeException(), isNull, reason: name);
        if (qr) expectQrBlackOnWhite(tester);
      }
      await h.close(tester);
    }

    for (final iPhone in [true, false]) {
      final variant = TargetPlatformVariant.only(
        iPhone ? TargetPlatform.iOS : TargetPlatform.android,
      );
      final on = iPhone ? 'iPhone' : 'Android';
      for (final scene in CollectScene.values) {
        // Tap to Pay on iPhone takes no surcharge yet.
        if (iPhone && scene == CollectScene.surcharge) continue;
        testWidgets('$on: ${scene.name}', (tester) async {
          final h = await CollectHarness.start(tester, iPhone: iPhone);
          await h.drive(tester, scene);
          if (scene == CollectScene.surcharge) {
            expect(find.text('Surcharge'), findsOneWidget);
          }
          if (scene == CollectScene.declined || scene == CollectScene.unread) {
            h.repo.cancels.add(fakeCompletion('canceled'));
          }
          await everyTheme(tester, h);
        }, variant: variant);
      }

      testWidgets('$on: the decline receipt, open', (tester) async {
        final h = await CollectHarness.start(tester, iPhone: iPhone);
        await h.drive(tester, CollectScene.declined);
        await tester.ensureVisible(find.text('Send decline receipt'));
        await tester.tap(find.text('Send decline receipt'));
        await tester.pump();
        expect(find.byType(TextField), findsOneWidget);
        h.repo.cancels.add(fakeCompletion('canceled'));
        await everyTheme(tester, h);
      }, variant: variant);

      testWidgets('$on: Pay another way, with the code', (tester) async {
        final h = await CollectHarness.start(tester, iPhone: iPhone);
        await h.drive(tester, CollectScene.declined);
        h.repo.cancels.add(fakeCompletion('canceled'));
        await h.openFallback(tester);
        await everyTheme(tester, h, qr: true);
      }, variant: variant);

      testWidgets('$on: Pay another way, not payable online', (tester) async {
        final h = await CollectHarness.start(
          tester,
          iPhone: iPhone,
          link: false,
        );
        await h.drive(tester, CollectScene.declined);
        h.repo.cancels.add(fakeCompletion('canceled'));
        await h.openFallback(tester);
        expect(find.text('Enter Payment'), findsOneWidget);
        await everyTheme(tester, h);
      }, variant: variant);

      testWidgets('$on: a toast above the pinned button', (tester) async {
        final h = await CollectHarness.start(tester, iPhone: iPhone);
        h.services.toasts.info(
          "Card declined on invoice 0042. The customer wasn't charged.",
          action: NotifyAction('Open', () {}),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await everyTheme(tester, h);
      }, variant: variant);
    }
  });

  group('Tap to Pay on iPhone setup under every theme', () {
    final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);
    const all = {
      TapToPayEnableStep.cardPresent,
      TapToPayEnableStep.location,
      TapToPayEnableStep.terms,
      TapToPayEnableStep.learn,
    };

    Future<void> everyTheme(
      WidgetTester tester,
      Widget Function(BuildContext context) build, {
      Future<void> Function(WidgetTester tester)? then,
    }) async {
      tester.view.physicalSize = const Size(390, 844) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      for (final (name, theme) in kAllAppThemes) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(name),
            theme: theme(),
            localizationsDelegates: kTestLocalizationsDelegates,
            home: Builder(builder: build),
          ),
        );
        await tester.pump();
        if (then != null) await then(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: name);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    Widget view(
      TapToPayEnableStage stage, {
      Set<TapToPayEnableStep> done = const {},
      double? progress,
      String? problem,
      bool settings = false,
    }) => TapToPayEnableView(
      stage: stage,
      companyName: 'Acme Plumbing',
      steps: all,
      doneSteps: done,
      progress: progress,
      problem: problem,
      onStart: () {},
      onRetry: () {},
      onDone: () {},
      onOpenInvoices: () {},
      // Ready with nothing to pay online through: its note too.
      onOpenPaymentSettings: stage == TapToPayEnableStage.ready ? () {} : null,
      onOpenSettings: settings ? () {} : null,
    );

    testWidgets('Ready says so when no invoice can be paid online, and only '
        'then', (tester) async {
      var opened = 0;
      Widget ready(VoidCallback? open) => MaterialApp(
        theme: kAllAppThemes.first.$2(),
        localizationsDelegates: kTestLocalizationsDelegates,
        home: TapToPayEnableView(
          stage: TapToPayEnableStage.ready,
          companyName: 'Acme',
          steps: all,
          doneSteps: all,
          onStart: () {},
          onRetry: () {},
          onDone: () {},
          onOpenInvoices: () {},
          onOpenPaymentSettings: open,
        ),
      );
      await tester.pumpWidget(ready(null));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining("can't be paid online"), findsNothing);

      await tester.pumpWidget(ready(() => opened++));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining("can't be paid online"), findsOneWidget);
      await tester.tap(find.text('Payment settings'));
      expect(opened, 1);
    }, variant: iOS);

    for (final stage in TapToPayEnableStage.values) {
      testWidgets('the enable screen: ${stage.name}', (tester) async {
        await everyTheme(
          tester,
          (_) => view(
            stage,
            done: stage == TapToPayEnableStage.intro
                ? const {}
                : const {
                    TapToPayEnableStep.cardPresent,
                    TapToPayEnableStep.location,
                  },
            progress: stage == TapToPayEnableStage.preparing ? 0.42 : null,
            problem: stage == TapToPayEnableStage.failed
                ? 'Location access is off for this app.'
                : null,
            settings: stage == TapToPayEnableStage.failed,
          ),
        );
      }, variant: iOS);
    }

    testWidgets('the app\'s word before iOS asks for location', (tester) async {
      await everyTheme(
        tester,
        (_) => view(TapToPayEnableStage.intro),
        then: (t) async {
          final context = t.element(find.byType(TapToPayEnableView));
          // ignore: unawaited_futures
          showDialog<bool>(
            context: context,
            builder: (_) => const LocationPreAlertDialog(),
          );
          await t.pump();
        },
      );
    }, variant: iOS);

    for (final state in TapToPayTileState.values) {
      testWidgets('the Card readers tile: ${state.name}', (tester) async {
        await everyTheme(
          tester,
          (context) => Scaffold(
            backgroundColor: context.inTheme.bg,
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: CollectCard(
                  child: TapToPayTile(
                    state: state,
                    progress: state == TapToPayTileState.preparing
                        ? 0.42
                        : null,
                    onTurnOn: () {},
                    onHowToUse: () {},
                  ),
                ),
              ),
            ),
          ),
        );
      }, variant: iOS);
    }
  });
}
