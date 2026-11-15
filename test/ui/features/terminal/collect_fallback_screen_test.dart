import 'dart:async';

import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/invoice_status.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/terminal_server_error.dart';
import 'package:admin/ui/core/widgets/qr_code_image.dart';
import 'package:admin/ui/core/widgets/toast_host.dart';
import 'package:admin/ui/features/terminal/view_models/collect_card_payment_view_model.dart';
import 'package:admin/ui/features/terminal/views/collect_card_payment_screen.dart';
import 'package:admin/ui/features/terminal/widgets/pay_another_way.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:store_services/store_services.dart';

import '_collect_stage_harness.dart';
import '_terminal_fakes.dart';

/// The collect screen's ways on after a card that wasn't charged (App Review
/// 4.8, 5.10; docs/in-person-payments.md): "Pay another way", the decline
/// receipt, the receipt's Share — and a toast that never covers the pinned
/// actions (5.3).
void main() {
  /// What the app handed on: to the share sheet on touch, else to the
  /// clipboard (`shareOrCopyLink`).
  final copied = <String>[];
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  setUp(() {
    copied.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(share, (call) async {
      final uri = (call.arguments as Map)['uri'];
      if (uri is String) copied.add(uri);
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(share, null);
  });

  const fallback = 'Pay another way';
  const declineReceipt = 'Send decline receipt';

  group('Pay another way', () {
    for (final scene in [
      CollectScene.unrecorded,
      CollectScene.checking,
      CollectScene.recording,
      CollectScene.approved,
      CollectScene.waiting,
      CollectScene.configure,
    ]) {
      testWidgets('never offered on ${scene.name}, nor a decline receipt', (
        tester,
      ) async {
        final h = await CollectHarness.start(tester);
        await h.drive(tester, scene);

        expect(find.text(fallback), findsNothing);
        expect(find.text(declineReceipt), findsNothing);
        expect(find.byType(PayAnotherWayView), findsNothing);
        await h.close(tester);
      });
    }

    testWidgets('a declined card: the code of the invoice\'s own link, at '
        'once, while the PaymentIntent is cancelled behind it', (tester) async {
      final h = await CollectHarness.start(tester);
      await h.drive(tester, CollectScene.declined);
      expect(find.text(fallback), findsOneWidget);
      expect(find.text(declineReceipt), findsOneWidget);
      h.repo.cancels.add(fakeCompletion('canceled'));

      await h.openFallback(tester);

      expect(h.repo.calls, contains('cancel:pi_1'));
      expect(
        tester.widget<QrCodeImage>(find.byType(QrCodeImage)).data,
        kPaymentLink,
      );
      expect(
        find.text(
          'The customer can scan this code to pay online with another card '
          'or payment method.',
        ),
        findsOneWidget,
      );
      // Android's reader is named plainly, never as Apple's.
      expect(find.text('Back to Tap to Pay'), findsOneWidget);
      expect(
        find.text(
          'If the customer started paying online, wait for it to finish '
          'first.',
        ),
        findsOneWidget,
      );
      // The decline receipt is offered here too.
      expect(find.text(declineReceipt), findsOneWidget);

      await tester.tap(find.text('Share link'));
      await h.settle(tester);
      expect(copied, [kPaymentLink]);
      await h.close(tester);
    });

    testWidgets('a cancelled payment offers it too', (tester) async {
      final h = await CollectHarness.start(tester);
      await h.drive(tester, CollectScene.cancelled);
      expect(h.vm.stage, CollectStage.cancelled);
      expect(find.text(fallback), findsOneWidget);
      final cancels = h.repo.calls.where((c) => c.startsWith('cancel')).length;

      await h.openFallback(tester);

      expect(find.byType(QrCodeImage), findsOneWidget);
      // Already cancelled: nothing more to cancel.
      expect(h.repo.calls.where((c) => c.startsWith('cancel')).length, cancels);
      await h.close(tester);
    });

    testWidgets('on an iPhone the way back names Tap to Pay on iPhone', (
      tester,
    ) async {
      final h = await CollectHarness.start(tester, iPhone: true);
      await h.drive(tester, CollectScene.declined);
      h.repo.cancels.add(fakeCompletion('canceled'));

      await h.openFallback(tester);

      expect(find.text('Back to Tap to Pay on iPhone'), findsOneWidget);
      await h.close(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Done closes the screen', (tester) async {
      final h = await CollectHarness.start(tester);
      await h.drive(tester, CollectScene.declined);
      h.repo.cancels.add(fakeCompletion('canceled'));
      await h.openFallback(tester);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(CollectCardPaymentScreen), findsNothing);
      expect(find.text('invoice below'), findsOneWidget);
      await h.close(tester);
    });

    testWidgets('back: the invoice again, the figures again, then a new '
        'collection', (tester) async {
      final h = await CollectHarness.start(tester);
      await h.drive(tester, CollectScene.declined);
      h.repo.cancels.add(fakeCompletion('canceled'));
      await h.openFallback(tester);
      h.repo.calls.clear();
      h.refetched = kHarnessInvoice;
      h.repo.creates.add(fakeIntent('pi_2'));
      h.platform.session.reads.add(
        const TerminalError(TerminalErrorCode.cardNotRead),
      );

      await tester.tap(find.text('Back to Tap to Pay'));
      await h.settle(tester);

      expect(h.refetches, 1);
      expect(h.repo.calls.where((c) => c.startsWith('quote')), isNotEmpty);
      expect(h.repo.calls.where((c) => c.startsWith('create')), hasLength(1));
      expect(h.repo.createdCollectionIds, hasLength(2));
      expect(h.repo.createdCollectionIds.toSet(), hasLength(2));
      expect(find.byType(QrCodeImage), findsNothing);
      // The new collection's own decline: an unread card, so no receipt.
      expect(h.vm.stage, CollectStage.declined);
      expect(find.text(declineReceipt), findsNothing);
      h.repo.cancels.add(fakeCompletion('canceled'));
      await h.close(tester);
    });

    testWidgets('back to an invoice paid online meanwhile says so, and '
        'offers no fallback', (tester) async {
      final h = await CollectHarness.start(tester);
      await h.drive(tester, CollectScene.declined);
      h.repo.cancels.add(fakeCompletion('canceled'));
      await h.openFallback(tester);
      h.refetched = kHarnessInvoice.copyWith(
        statusId: InvoiceStatus.paid,
        balance: Decimal.zero,
      );

      await tester.tap(find.text('Back to Tap to Pay'));
      await h.settle(tester);

      expect(h.vm.stage, CollectStage.cancelled);
      expect(
        find.text('A previous card payment for this invoice was recorded.'),
        findsOneWidget,
      );
      expect(find.text(fallback), findsNothing);
      expect(h.repo.createdCollectionIds, hasLength(1));
      await h.close(tester);
    });

    for (final (name, link, gateway) in [
      ('no payment link', false, true),
      ('no active gateway', true, false),
    ]) {
      testWidgets('$name: it can\'t be paid online, and Enter Payment hands '
          'over to the invoice\'s own', (tester) async {
        final entered = <Invoice>[];
        final h = await CollectHarness.start(
          tester,
          link: link,
          gateway: gateway,
          enterPayment: (context, invoice) async => entered.add(invoice),
        );
        await h.drive(tester, CollectScene.declined);
        h.repo.cancels.add(fakeCompletion('canceled'));

        await h.openFallback(tester);

        expect(find.byType(QrCodeImage), findsNothing);
        expect(find.text('Share link'), findsNothing);
        expect(
          find.text(
            "This invoice can't be paid online. Record a cash or other "
            'payment instead.',
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Enter Payment'));
        await tester.pumpAndSettle();

        expect(entered.single.id, 'inv_1');
        expect(find.byType(CollectCardPaymentScreen), findsNothing);
        await h.close(tester);
      });
    }

    testWidgets('a gateway count that can\'t be read counts as having one', (
      tester,
    ) async {
      final h = await CollectHarness.start(tester, gateway: false);
      await h.drive(tester, CollectScene.declined);
      h.repo.cancels.add(fakeCompletion('canceled'));

      // No real time for the Drift read: only its timeout answers.
      await tester.tap(find.text(fallback));
      await tester.pump(const Duration(seconds: 3));
      await h.settle(tester);

      expect(find.byType(QrCodeImage), findsOneWidget);
      await h.close(tester);
    });
  });

  group('Send decline receipt', () {
    testWidgets('not for a card that couldn\'t be read', (tester) async {
      final h = await CollectHarness.start(tester);
      await h.drive(tester, CollectScene.unread);

      expect(h.vm.stage, CollectStage.declined);
      expect(find.text(fallback), findsOneWidget);
      expect(find.text(declineReceipt), findsNothing);
      h.repo.cancels.add(fakeCompletion('canceled'));
      await h.close(tester);
    });

    testWidgets('the email shows after the press; sending, then sent', (
      tester,
    ) async {
      final h = await CollectHarness.start(tester);
      await h.drive(tester, CollectScene.declined);
      expect(find.byType(TextField), findsNothing);

      await tester.ensureVisible(find.text(declineReceipt));
      await tester.tap(find.text(declineReceipt));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'sam@example.com',
      );
      h.repo.receiptGate = Completer<void>();
      await tester.tap(find.text('Send'));
      await tester.pump();

      expect(find.text('Sending'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Sending'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );

      h.repo.receiptGate!.complete();
      await h.settle(tester);

      expect(find.text('Decline receipt sent'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(h.repo.calls, contains('receipt:pi_1:sam@example.com'));
      h.repo.cancels.add(fakeCompletion('canceled'));
      await h.close(tester);
    });

    testWidgets('a failure says why and keeps the field; the limit ends it', (
      tester,
    ) async {
      final h = await CollectHarness.start(tester);
      await h.drive(tester, CollectScene.declined);
      await tester.ensureVisible(find.text(declineReceipt));
      await tester.tap(find.text(declineReceipt));
      await tester.pump();
      h.repo.receiptError = const NetworkException('offline');

      await tester.tap(find.text('Send'));
      await h.settle(tester);

      expect(find.textContaining('connection'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      h.repo.receiptError = const TerminalServerError('receipt_limit', '');
      await tester.tap(find.text('Send'));
      await h.settle(tester);

      expect(
        find.text('This receipt has been sent as many times as allowed.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      h.repo.cancels.add(fakeCompletion('canceled'));
      await h.close(tester);
    });
  });

  group('approved', () {
    testWidgets('Share receipt hands on Stripe\'s receipt link; the card '
        'reads as a receipt names it', (tester) async {
      final h = await CollectHarness.start(tester);
      await h.drive(tester, CollectScene.approved);

      expect(find.text('Visa •••• 4242'), findsOneWidget);
      await tester.tap(find.text('Share receipt'));
      await h.settle(tester);

      expect(copied, [kReceiptUrl]);
      await h.close(tester);
    });

    testWidgets('no receipt link, no Share', (tester) async {
      final h = await CollectHarness.start(tester);
      h.repo.creates.add(fakeIntent());
      h.platform.session.reads.add(fakeRead(12000));
      h.repo.finalizes.add(fakeFinalize(12000));
      h.platform.session.confirms.add(
        const TerminalPaymentOutcome(
          paymentIntentId: 'pi_1',
          status: 'succeeded',
        ),
      );
      h.repo.completes.add(fakeCompletion('recorded'));
      unawaited(h.vm.collect());
      await h.settle(tester);

      expect(h.vm.stage, CollectStage.approved);
      expect(find.text('Share receipt'), findsNothing);
      expect(find.text('Done'), findsOneWidget);
      await h.close(tester);
    });
  });

  group('a toast never covers the pinned actions', () {
    for (final iPhone in [true, false]) {
      testWidgets(
        iPhone ? 'the Tap to Pay on iPhone button' : 'Collect',
        (tester) async {
          final h = await CollectHarness.start(tester, iPhone: iPhone);
          final button = find.descendant(
            of: find.byType(ToastBottomInset),
            matching: find.byType(FilledButton),
          );
          expect(button, findsOneWidget);

          h.services.toasts.info(
            "Card declined on invoice 0042. The customer wasn't charged.",
          );
          // The card grows in from a post-frame start: a frame to start it,
          // one to finish it.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(milliseconds: 300));

          final toast = find.textContaining('Card declined on invoice 0042');
          expect(toast, findsOneWidget);
          final actions = tester.getRect(find.byType(ToastBottomInset));
          expect(
            tester.getRect(toast).bottom,
            lessThanOrEqualTo(actions.top),
            reason: 'the toast sits above the pinned actions',
          );
          expect(
            tester.getRect(toast).overlaps(tester.getRect(button)),
            isFalse,
          );
          await h.close(tester);
        },
        variant: TargetPlatformVariant.only(
          iPhone ? TargetPlatform.iOS : TargetPlatform.android,
        ),
      );
    }

    testWidgets('the lift goes when the screen does', (tester) async {
      final h = await CollectHarness.start(tester);
      await tester.pump();
      expect(h.services.toasts.bottomInset.value, greaterThan(0));

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(CollectCardPaymentScreen), findsNothing);
      expect(h.services.toasts.bottomInset.value, 0);
      await h.close(tester);
    });
  });
}
