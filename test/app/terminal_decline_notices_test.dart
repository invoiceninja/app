import 'dart:async';

import 'package:admin/app/terminal_controller.dart';
import 'package:admin/app/terminal_decline_notices.dart';
import 'package:admin/data/models/api/terminal_models.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/features/shell/_shell_test_helpers.dart';
import '../ui/features/terminal/_terminal_fakes.dart';

/// A card declined while nobody was watching (the app closed while it was
/// being charged) is told once, at the company's next activation, and only
/// then cancelled and forgotten (App Review 5.12;
/// docs/in-person-payments.md).
void main() {
  TerminalCompletion answer(String status, {bool declined = false}) =>
      TerminalCompletion(
        status: status,
        paymentId: status == 'recorded' ? 'pay_1' : '',
        applied: Decimal.zero,
        unapplied: Decimal.zero,
        invoiceBalance: null,
        brand: declined ? 'visa' : '',
        last4: declined ? '4242' : '',
        receiptUrl: '',
        declined: declined,
      );

  group('the server\'s answer', () {
    test('declined, with the card', () {
      final c = TerminalCompletion.fromJson(const {
        'status': 'requires_payment_method',
        'declined': true,
        'brand': 'visa',
        'last4': '4242',
      });
      expect(c.declined, isTrue);
      expect(c.status, 'requires_payment_method');
      expect((c.brand, c.last4), ('visa', '4242'));
    });

    test('an older server says nothing: not declined', () {
      final c = TerminalCompletion.fromJson(const {
        'status': 'requires_payment_method',
      });
      expect(c.declined, isFalse);
      expect((c.brand, c.last4), ('', ''));
    });
  });

  /// A signed-in fixture, a terminal over fakes, the notices, and a pumped
  /// app whose toast host shows what they say.
  Future<
    (
      TerminalController,
      FakeTerminalRepo,
      TerminalDeclineNotices,
      ValueNotifier<bool>,
      List<String>,
      ShellFixture,
    )
  >
  boot(WidgetTester tester) async {
    final fixture = await buildFixture(
      companies: [
        FakeCompany(id: 'co1', name: 'Acme', isAdmin: true, isOwner: true),
      ],
    );
    addTearDown(fixture.dispose);
    final repo = FakeTerminalRepo();
    final terminal = TerminalController(
      repository: repo,
      platform: FakeTerminalPlatform(),
      auth: fixture.services.auth,
      prefs: fixture.services.devicePrefs,
      platformReady: true,
    );
    addTearDown(terminal.dispose);
    final locked = ValueNotifier(false);
    addTearDown(locked.dispose);
    final notices = TerminalDeclineNotices(
      terminal: terminal,
      toasts: fixture.services.toasts,
      session: fixture.services.auth.session,
      credentials: fixture.services.auth.credentials,
      requiresBiometricUnlock: locked,
    );
    final went = <String>[];
    final key = GlobalKey();
    await tester.pumpWidget(
      wrapWithShell(fixture.services, SizedBox(key: key)),
    );
    notices.attach(go: went.add, contextOf: () => key.currentContext);
    addTearDown(notices.detach);
    return (terminal, repo, notices, locked, went, fixture);
  }

  bool pending(ShellFixture fixture, String pi) =>
      (fixture.services.devicePrefs.read(DevicePrefKeys.pendingCardPayments) ??
              '')
          .contains(pi);

  group('the sweep', () {
    testWidgets('a declined card is returned, still pending, with its '
        'invoice; settling cancels and forgets it', (tester) async {
      final (terminal, repo, _, _, _, fixture) = await boot(tester);
      await terminal.notePending(
        companyId: 'co1',
        invoiceId: 'inv_1',
        invoiceNumber: '0042',
        paymentIntentId: 'pi_1',
      );
      repo.completes.add(answer('requires_payment_method', declined: true));

      final found = await terminal.sweepPending('co1');

      expect(found, hasLength(1));
      expect(found.single.invoiceId, 'inv_1');
      expect(found.single.invoiceNumber, '0042');
      expect(found.single.paymentIntentId, 'pi_1');
      expect(pending(fixture, 'pi_1'), isTrue);
      expect(repo.calls.where((c) => c.startsWith('cancel')), isEmpty);

      repo.cancels.add(answer('canceled'));
      await terminal.settleUnseenDecline(found.single);

      expect(repo.calls, contains('cancel:pi_1'));
      expect(pending(fixture, 'pi_1'), isFalse);
    });

    testWidgets('not declined, or an older server that can\'t say: nothing '
        'is told and the payment stays pending', (tester) async {
      final (terminal, repo, _, _, _, fixture) = await boot(tester);
      await terminal.notePending(
        companyId: 'co1',
        invoiceId: 'inv_1',
        paymentIntentId: 'pi_1',
      );
      await terminal.notePending(
        companyId: 'co1',
        invoiceId: 'inv_2',
        paymentIntentId: 'pi_2',
      );
      repo.completes
        ..add(answer('processing'))
        // An older server's answer for a declined card: no `declined`.
        ..add(
          TerminalCompletion.fromJson(const {
            'status': 'requires_payment_method',
          }),
        );

      expect(await terminal.sweepPending('co1'), isEmpty);

      expect(pending(fixture, 'pi_1'), isTrue);
      expect(pending(fixture, 'pi_2'), isTrue);
      expect(repo.calls.where((c) => c.startsWith('cancel')), isEmpty);
    });

    testWidgets('a recorded charge stays pending, for the invoice\'s own '
        'check to say so; another company\'s is never asked about; a failure '
        'waits for next time', (tester) async {
      final (terminal, repo, _, _, _, fixture) = await boot(tester);
      await terminal.notePending(
        companyId: 'co1',
        invoiceId: 'inv_1',
        paymentIntentId: 'pi_1',
      );
      await terminal.notePending(
        companyId: 'co_other',
        invoiceId: 'inv_9',
        paymentIntentId: 'pi_9',
      );
      await terminal.notePending(
        companyId: 'co1',
        invoiceId: 'inv_3',
        paymentIntentId: 'pi_3',
      );
      repo.completes
        ..add(answer('recorded'))
        ..add(StateError('offline'));

      expect(await terminal.sweepPending('co1'), isEmpty);

      expect(repo.calls.where((c) => c == 'complete'), hasLength(2));
      expect(pending(fixture, 'pi_1'), isTrue);
      expect(pending(fixture, 'pi_9'), isTrue);
      expect(pending(fixture, 'pi_3'), isTrue);
    });
  });

  group('the notice', () {
    testWidgets('told once, with Open to the invoice; then cancelled and '
        'forgotten', (tester) async {
      final (terminal, repo, notices, _, went, fixture) = await boot(tester);
      await terminal.notePending(
        companyId: 'co1',
        invoiceId: 'inv_1',
        invoiceNumber: '0042',
        paymentIntentId: 'pi_1',
      );
      repo.completes.add(answer('requires_payment_method', declined: true));
      repo.cancels.add(answer('canceled'));

      await notices.sweep('co1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(
          "Card declined on invoice 0042. The customer wasn't charged.",
        ),
        findsOneWidget,
      );
      expect(repo.calls, contains('cancel:pi_1'));
      expect(pending(fixture, 'pi_1'), isFalse);

      final toast = fixture.services.toasts.toasts.single;
      expect(toast.action?.label, 'Open');
      toast.action!.onPressed();
      expect(went, ['/invoices/inv_1']);

      // The next activation has nothing left to tell.
      await notices.sweep('co1');
      await tester.pump();
      expect(fixture.services.toasts.toasts.single.count, 1);
      expect(repo.calls.where((c) => c == 'complete'), hasLength(1));
    });

    testWidgets('never over the lock screen: held, still pending, and told '
        'once the user is through', (tester) async {
      final (terminal, repo, notices, locked, _, fixture) = await boot(tester);
      await terminal.notePending(
        companyId: 'co1',
        invoiceId: 'inv_1',
        paymentIntentId: 'pi_1',
      );
      repo.completes.add(answer('requires_payment_method', declined: true));
      repo.cancels.add(answer('canceled'));
      locked.value = true;

      await notices.sweep('co1');
      await tester.pump();

      expect(fixture.services.toasts.toasts, isEmpty);
      expect(pending(fixture, 'pi_1'), isTrue);
      expect(repo.calls.where((c) => c.startsWith('cancel')), isEmpty);

      locked.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // An entry from before the number was kept names no invoice.
      expect(
        find.text("A card payment was declined. The customer wasn't charged."),
        findsOneWidget,
      );
      expect(repo.calls, contains('cancel:pi_1'));
    });

    testWidgets('a session that ends first tells nothing: the payment is '
        'found again', (tester) async {
      final (terminal, repo, notices, locked, _, fixture) = await boot(tester);
      await terminal.notePending(
        companyId: 'co1',
        invoiceId: 'inv_1',
        paymentIntentId: 'pi_1',
      );
      repo.completes.add(answer('requires_payment_method', declined: true));
      locked.value = true;
      await notices.sweep('co1');

      notices.reset();
      locked.value = false;
      await tester.pump();

      expect(fixture.services.toasts.toasts, isEmpty);
      expect(pending(fixture, 'pi_1'), isTrue);
    });
  });

  group('review of 5e1821f8', () {
    testWidgets('several declines are one toast, with a count', (tester) async {
      final (terminal, repo, notices, _, went, fixture) = await boot(tester);
      for (final n in ['1', '2']) {
        await terminal.notePending(
          companyId: 'co1',
          invoiceId: 'inv_$n',
          invoiceNumber: '004$n',
          paymentIntentId: 'pi_$n',
        );
        repo.completes.add(answer('requires_payment_method', declined: true));
        repo.cancels.add(answer('canceled'));
      }

      await notices.sweep('co1');
      await tester.pump();

      final toast = fixture.services.toasts.toasts.single;
      expect(
        toast.message,
        "2 card payments were declined. The customers weren't charged.",
      );
      // Long enough to be read: never the default few seconds.
      expect(toast.duration, greaterThanOrEqualTo(const Duration(seconds: 10)));
      toast.action!.onPressed();
      expect(went, ['/invoices']);
    });

    testWidgets('only while the app is in front: held in the background, '
        'told on resume', (tester) async {
      final (terminal, repo, notices, _, _, fixture) = await boot(tester);
      await terminal.notePending(
        companyId: 'co1',
        invoiceId: 'inv_1',
        invoiceNumber: '0042',
        paymentIntentId: 'pi_1',
      );
      repo.completes.add(answer('requires_payment_method', declined: true));
      repo.cancels.add(answer('canceled'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      await notices.sweep('co1');
      await tester.pump();
      expect(fixture.services.toasts.toasts, isEmpty);
      expect(pending(fixture, 'pi_1'), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      notices.onResumed();
      await tester.pump();

      expect(fixture.services.toasts.toasts, hasLength(1));
    });

    testWidgets('a second activation while the first is still settling '
        'tells nothing twice', (tester) async {
      final (terminal, repo, notices, _, _, fixture) = await boot(tester);
      await terminal.notePending(
        companyId: 'co1',
        invoiceId: 'inv_1',
        invoiceNumber: '0042',
        paymentIntentId: 'pi_1',
      );
      repo.completes
        ..add(answer('requires_payment_method', declined: true))
        ..add(answer('requires_payment_method', declined: true));
      final cancel = Completer<TerminalCompletion>();
      repo.cancels.add(cancel);

      await notices.sweep('co1');
      await tester.pump();
      // A → B → A: the cancel is still on its way.
      await notices.sweep('co1');
      await tester.pump();

      final toast = fixture.services.toasts.toasts.single;
      expect(toast.count, 1);
      cancel.complete(answer('canceled'));
      await tester.pump();
      expect(pending(fixture, 'pi_1'), isFalse);
    });

    testWidgets('a cancel that fails, or finds the charge still open, keeps '
        'the entry — and the next sweep tells nothing again', (tester) async {
      final (terminal, repo, notices, _, _, fixture) = await boot(tester);
      await terminal.notePending(
        companyId: 'co1',
        invoiceId: 'inv_1',
        invoiceNumber: '0042',
        paymentIntentId: 'pi_1',
      );
      repo.completes.add(answer('requires_payment_method', declined: true));
      repo.cancels.add(StateError('offline'));

      await notices.sweep('co1');
      await tester.pump();
      await tester.pump();
      expect(fixture.services.toasts.toasts.single.count, 1);
      expect(pending(fixture, 'pi_1'), isTrue);

      // Next activation: still declined, cancel answers `processing`.
      repo.completes.add(answer('requires_payment_method', declined: true));
      repo.cancels.add(answer('processing'));
      await notices.sweep('co1');
      await tester.pump();
      await tester.pump();
      expect(fixture.services.toasts.toasts.single.count, 1);
      expect(pending(fixture, 'pi_1'), isTrue);

      // And once it is cancelled for good, forgotten.
      repo.completes.add(answer('requires_payment_method', declined: true));
      repo.cancels.add(answer('canceled'));
      await notices.sweep('co1');
      await tester.pump();
      await tester.pump();
      expect(fixture.services.toasts.toasts.single.count, 1);
      expect(pending(fixture, 'pi_1'), isFalse);
    });
  });
}
