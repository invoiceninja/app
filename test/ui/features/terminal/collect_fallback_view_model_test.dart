import 'dart:async';

import 'package:admin/app/terminal_controller.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/terminal_models.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/invoice_status.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/password_cache.dart';
import 'package:admin/data/services/terminal_server_error.dart';
import 'package:admin/data/services/token_storage.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';
import 'package:admin/ui/features/terminal/view_models/collect_card_payment_view_model.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_services/store_services.dart';

import '_terminal_fakes.dart';

/// "Pay another way" and the decline receipt (App Review 4.8, 5.10;
/// docs/in-person-payments.md): the fallback only over a card that was not
/// charged, its cancel in the background, and a way back that starts a
/// collection of its own.
void main() {
  late AppDatabase db;
  late AuthRepository auth;
  late DevicePrefsStore prefs;
  late FakeTerminalRepo repo;
  late FakeTerminalPlatform platform;
  late TerminalController terminal;
  var ids = 0;
  var refetches = 0;
  Invoice? refetched;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final authService = FakeAuthService();
    auth = AuthRepository(
      db: db,
      authService: authService,
      tokenStorage: InMemoryTokenStorage(),
      passwordCache: PasswordCache(),
    );
    authService.queueLogin(fakeEnvelope());
    await auth.login(
      baseUrl: 'https://test',
      isHosted: false,
      email: 'a',
      password: 'b',
    );
    prefs = DevicePrefsStore(db);
    await prefs.load();
    repo = FakeTerminalRepo();
    platform = FakeTerminalPlatform();
    terminal = TerminalController(
      repository: repo,
      platform: platform,
      auth: auth,
      prefs: prefs,
      platformReady: true,
    );
    ids = 0;
    refetches = 0;
    refetched = null;
  });
  tearDown(() async {
    terminal.dispose();
    await db.close();
  });

  final invoice = emptyInvoice().copyWith(
    id: 'inv_1',
    number: '0042',
    statusId: InvoiceStatus.sent,
    amount: Decimal.fromInt(100),
    balance: Decimal.fromInt(100),
  );

  Future<CollectCardPaymentViewModel> ready() async {
    final vm = CollectCardPaymentViewModel(
      companyId: 'co_a',
      invoice: invoice,
      terminal: terminal,
      repository: repo,
      isAdmin: true,
      merchantDisplayName: 'Acme',
      precision: 2,
      newId: () => 'col_${++ids}',
      pollDelay: Duration.zero,
      refetchInvoice: () async {
        refetches++;
        return refetched;
      },
    );
    await vm.start();
    expect(vm.canCollect, isTrue);
    return vm;
  }

  /// A card read, then declined when charged.
  Future<CollectCardPaymentViewModel> declined() async {
    final vm = await ready();
    repo.creates.add(fakeIntent());
    platform.session.reads.add(fakeCard);
    repo.finalizes.add(fakeFinalize(10000));
    platform.session.confirms.add(
      const TerminalError(TerminalErrorCode.declined),
    );
    await vm.collect();
    expect(vm.stage, CollectStage.declined);
    return vm;
  }

  /// A card charged, with the server answering [status].
  Future<CollectCardPaymentViewModel> charged(String status) async {
    final vm = await ready();
    repo.creates.add(fakeIntent());
    platform.session.reads.add(fakeCard);
    repo.finalizes.add(fakeFinalize(10000));
    platform.session.confirms.add(
      const TerminalPaymentOutcome(
        paymentIntentId: 'pi_1',
        status: 'succeeded',
      ),
    );
    for (var i = 0; i < 3; i++) {
      repo.completes.add(fakeCompletion(status));
    }
    await vm.collect();
    return vm;
  }

  group('Pay another way', () {
    test('over a declined card it shows at once, and the PaymentIntent is '
        'cancelled in the background', () async {
      final vm = await declined();
      final cancel = Completer<TerminalCompletion>();
      repo.cancels.add(cancel);

      vm.payAnotherWay();

      // Showing before the server has answered the cancel.
      expect(vm.payingAnotherWay, isTrue);
      expect(vm.stage, CollectStage.cancelled);
      await pumpEventQueue();
      expect(repo.calls, contains('cancel:pi_1'));

      cancel.complete(fakeCompletion('canceled'));
      await pumpEventQueue();
      expect(vm.payingAnotherWay, isTrue);
      expect(vm.stage, CollectStage.cancelled);
      vm.dispose();
    });

    for (final (status, stage) in [
      ('rejected', CollectStage.unrecorded),
      ('recording', CollectStage.recording),
      ('requires_confirmation', CollectStage.checking),
    ]) {
      test('never once a card may have been charged: ${stage.name}', () async {
        final vm = await charged(status);
        expect(vm.stage, stage);
        expect(vm.canPayAnotherWay, isFalse);

        vm.payAnotherWay();

        expect(vm.payingAnotherWay, isFalse);
        expect(repo.calls.where((c) => c.startsWith('cancel')), isEmpty);
        expect(vm.declineReceiptAvailable, isFalse);
        vm.dispose();
      });
    }

    test('a cancel that finds the card charged after all gives the screen '
        'to that answer', () async {
      final vm = await declined();
      repo.cancels.add(fakeCompletion('recorded'));

      vm.payAnotherWay();
      await pumpEventQueue();

      expect(vm.stage, CollectStage.approved);
      expect(vm.payingAnotherWay, isFalse);
      // And the way back collects nothing again.
      await vm.backToReader();
      expect(vm.stage, CollectStage.approved);
      expect(repo.createdCollectionIds, ['col_1']);
      vm.dispose();
    });

    test('a cancelled payment may be paid another way too, with nothing left '
        'to cancel', () async {
      final vm = await declined();
      repo.cancels.add(fakeCompletion('canceled'));
      await vm.cancel();
      expect(vm.stage, CollectStage.cancelled);
      final cancels = repo.calls.where((c) => c.startsWith('cancel')).length;

      vm.payAnotherWay();
      await pumpEventQueue();

      expect(vm.payingAnotherWay, isTrue);
      expect(repo.calls.where((c) => c.startsWith('cancel')).length, cancels);
      vm.dispose();
    });

    test('back waits for the cancel, fetches the invoice, quotes again, then '
        'starts a collection of its own', () async {
      final vm = await declined();
      final cancel = Completer<TerminalCompletion>();
      repo.cancels.add(cancel);
      vm.payAnotherWay();
      await pumpEventQueue();
      repo.calls.clear();
      refetched = invoice.copyWith(balance: Decimal.fromInt(100));
      repo.creates.add(fakeIntent());
      final read = Completer<TerminalCollected>();
      platform.session.reads.add(read);

      final back = vm.backToReader();
      await pumpEventQueue();
      // Nothing until the cancel is answered.
      expect(vm.restarting, isTrue);
      expect(refetches, 0);
      expect(repo.calls, isEmpty);

      cancel.complete(fakeCompletion('canceled'));
      await pumpEventQueue();

      expect(refetches, 1);
      expect(vm.stage, CollectStage.waiting);
      expect(vm.payingAnotherWay, isFalse);
      expect(vm.restarting, isFalse);
      final quote = repo.calls.indexWhere((c) => c.startsWith('quote'));
      final create = repo.calls.indexWhere((c) => c.startsWith('create'));
      expect(quote, isNonNegative);
      expect(create, greaterThan(quote));
      // Its own collection, never the cancelled one's id.
      expect(repo.createdCollectionIds, ['col_1', 'col_2']);
      expect(vm.declineReceiptAvailable, isFalse);

      read.completeError(const TerminalError(TerminalErrorCode.canceled));
      await back;
      vm.dispose();
    });

    test('an invoice paid online meanwhile is never collected again', () async {
      final vm = await declined();
      repo.cancels.add(fakeCompletion('canceled'));
      vm.payAnotherWay();
      await pumpEventQueue();
      repo.calls.clear();
      refetched = invoice.copyWith(
        statusId: InvoiceStatus.paid,
        balance: Decimal.zero,
      );

      await vm.backToReader();

      expect(vm.stage, CollectStage.cancelled);
      expect(vm.problem?.serverCode, TerminalServerError.alreadyPaid);
      expect(vm.payingAnotherWay, isFalse);
      expect(repo.calls, isEmpty);
      vm.dispose();
    });

    test('an invoice that can\'t be fetched again is never collected '
        'without a fresh press', () async {
      final vm = await declined();
      repo.cancels.add(fakeCompletion('canceled'));
      vm.payAnotherWay();
      await pumpEventQueue();

      await vm.backToReader();

      expect(vm.stage, CollectStage.configure);
      expect(vm.invoiceUnchecked, isTrue);
      expect(repo.createdCollectionIds, ['col_1']);
      vm.dispose();
    });

    test(
      'a payment is entered by hand only once the cancel found no charge',
      () async {
        final vm = await declined();
        final cancel = Completer<TerminalCompletion>();
        repo.cancels.add(cancel);
        vm.payAnotherWay();
        var settled = false;
        final wait = vm.settledWithoutCharge().then((ok) => settled = ok);
        await pumpEventQueue();
        expect(settled, isFalse);

        cancel.complete(fakeCompletion('canceled'));
        await wait;

        expect(settled, isTrue);
        vm.dispose();
      },
    );
  });

  group('review of 5e1821f8', () {
    test(
      'a cancel still unanswered never lands on the new collection',
      () async {
        final vm = await declined();
        final cancel = Completer<TerminalCompletion>();
        repo.cancels.add(cancel);
        // Cancel, then the fallback from Cancelled: the cancel is in flight.
        unawaited(vm.cancel());
        await pumpEventQueue();
        expect(vm.stage, CollectStage.cancelled);
        vm.payAnotherWay();
        refetched = invoice;
        repo.creates.add(fakeIntent('pi_2'));
        final read = Completer<TerminalCollected>();
        platform.session.reads.add(read);

        final back = vm.backToReader();
        await pumpEventQueue();
        // Nothing new starts while the old cancel is unanswered.
        expect(repo.createdCollectionIds, ['col_1']);

        cancel.complete(fakeCompletion('canceled'));
        await pumpEventQueue();

        expect(vm.stage, CollectStage.waiting);
        expect(vm.paymentReference, 'pi_2');
        expect(repo.createdCollectionIds, ['col_1', 'col_2']);
        read.completeError(const TerminalError(TerminalErrorCode.canceled));
        repo.cancels.add(fakeCompletion('canceled'));
        await back;
        vm.dispose();
      },
    );

    test('a create answered after Cancel is cancelled, never adopted by the '
        'new collection', () async {
      final vm = await ready();
      final create = Completer<TerminalIntent>();
      repo.creates.add(create);
      unawaited(vm.collect());
      await pumpEventQueue();
      expect(vm.stage, CollectStage.creating);
      await vm.cancel();
      expect(vm.stage, CollectStage.cancelled);
      vm.payAnotherWay();
      refetched = invoice;
      repo.creates.add(fakeIntent('pi_2'));
      final read = Completer<TerminalCollected>();
      platform.session.reads.add(read);
      repo.cancels.add(fakeCompletion('canceled'));

      final back = vm.backToReader();
      await pumpEventQueue();
      create.complete(fakeIntent('pi_1'));
      await pumpEventQueue();

      expect(repo.calls, contains('cancel:pi_1'));
      expect(vm.stage, CollectStage.waiting);
      expect(vm.paymentReference, 'pi_2');
      read.completeError(const TerminalError(TerminalErrorCode.canceled));
      repo.cancels.add(fakeCompletion('canceled'));
      await back;
      vm.dispose();
    });

    test(
      'a payment is entered by hand only on a confirmed no-charge answer',
      () async {
        final vm = await declined();
        // Every attempt to cancel fails: nobody knows.
        for (var i = 0; i < 6; i++) {
          repo.cancels.add(const NetworkException('offline'));
        }
        vm.payAnotherWay();

        expect(await vm.settledWithoutCharge(), isFalse);

        // Asked again, and answered: now it is known.
        repo.cancels.add(fakeCompletion('canceled'));
        expect(await vm.settledWithoutCharge(), isTrue);
        vm.dispose();
      },
    );

    test(
      'back to an invoice whose deposit was just paid online never '
      'collects it again: the amount is the invoice\'s new one, to check',
      () async {
        final deposit = invoice.copyWith(partial: Decimal.fromInt(40));
        final vm = CollectCardPaymentViewModel(
          companyId: 'co_a',
          invoice: deposit,
          terminal: terminal,
          repository: repo,
          isAdmin: true,
          merchantDisplayName: 'Acme',
          precision: 2,
          newId: () => 'col_${++ids}',
          pollDelay: Duration.zero,
          refetchInvoice: () async => refetched,
        );
        await vm.start();
        expect(vm.amount, Decimal.fromInt(40));
        repo.creates.add(fakeIntent());
        platform.session.reads.add(fakeRead(4000));
        repo.finalizes.add(fakeFinalize(4000));
        platform.session.confirms.add(
          const TerminalError(TerminalErrorCode.declined),
        );
        await vm.collect();
        repo.cancels.add(fakeCompletion('canceled'));
        vm.payAnotherWay();
        await pumpEventQueue();
        refetched = deposit.copyWith(
          partial: Decimal.zero,
          balance: Decimal.fromInt(60),
          paidToDate: Decimal.fromInt(40),
        );

        await vm.backToReader();

        expect(vm.stage, CollectStage.configure);
        expect(vm.amount, Decimal.fromInt(60));
        expect(vm.invoiceChanged, isTrue);
        expect(repo.createdCollectionIds, ['col_1']);
        vm.dispose();
      },
    );

    test('Try another card forgets the declined charge: no receipt for a '
        'card that then can\'t be read', () async {
      final vm = await declined();
      expect(vm.declineReceiptAvailable, isTrue);
      platform.session.reads.add(
        const TerminalError(TerminalErrorCode.cardNotRead),
      );

      await vm.tryAnotherCard();

      expect(vm.stage, CollectStage.declined);
      expect(vm.declineReceiptAvailable, isFalse);
      vm.dispose();
    });
  });

  group('Send decline receipt', () {
    test('only for a card that was charged and declined, never one that '
        'merely couldn\'t be read', () async {
      final vm = await ready();
      repo.creates.add(fakeIntent());
      platform.session.reads.add(
        const TerminalError(TerminalErrorCode.cardNotRead),
      );
      await vm.collect();
      expect(vm.stage, CollectStage.declined);

      expect(vm.declineReceiptAvailable, isFalse);
      expect(await vm.sendDeclineReceipt('sam@example.com'), isFalse);
      expect(repo.calls.where((c) => c.startsWith('receipt')), isEmpty);
      vm.dispose();
    });

    test('hidden on a server that can\'t send a decline receipt', () async {
      final d = FakeTerminalRepo.defaultConfig;
      repo.configAnswer = TerminalConfig(
        enabled: d.enabled,
        planOk: d.planOk,
        gateways: d.gateways,
        declineReceipts: false,
      );
      final vm = await declined();

      expect(vm.stage, CollectStage.declined);
      expect(vm.declineReceiptAvailable, isFalse);
      expect(await vm.sendDeclineReceipt('sam@example.com'), isFalse);
      expect(repo.calls.where((c) => c.startsWith('receipt')), isEmpty);
      vm.dispose();
    });

    test(
      'a decline the server reports (requires_payment_method) counts',
      () async {
        final vm = await ready();
        repo.creates.add(fakeIntent());
        platform.session.reads.add(fakeCard);
        repo.finalizes.add(fakeFinalize(10000));
        platform.session.confirms.add(
          const TerminalError(TerminalErrorCode.outcomeUnknown),
        );
        repo.completes.add(fakeCompletion('requires_payment_method'));

        await vm.collect();

        expect(vm.stage, CollectStage.declined);
        expect(vm.declineReceiptAvailable, isTrue);
        vm.dispose();
      },
    );

    test('sending, then sent — to the same PaymentIntent, on the fallback '
        'too', () async {
      final vm = await declined();
      expect(vm.declineReceiptAvailable, isTrue);
      repo.cancels.add(fakeCompletion('canceled'));
      vm.payAnotherWay();
      await pumpEventQueue();
      expect(vm.declineReceiptAvailable, isTrue);
      repo.receiptGate = Completer<void>();

      final send = vm.sendDeclineReceipt(' sam@example.com ');
      await pumpEventQueue();
      expect(vm.declineReceipt, DeclineReceiptState.sending);
      // A second press while it goes out sends nothing more.
      expect(await vm.sendDeclineReceipt('sam@example.com'), isFalse);

      repo.receiptGate!.complete();
      expect(await send, isTrue);

      expect(vm.declineReceipt, DeclineReceiptState.sent);
      expect(repo.calls.where((c) => c.startsWith('receipt')), [
        'receipt:pi_1:sam@example.com',
      ]);
      vm.dispose();
    });

    test('a failure says why and may be tried again', () async {
      final vm = await declined();
      repo.receiptError = const NetworkException('offline');

      expect(await vm.sendDeclineReceipt('sam@example.com'), isFalse);

      expect(vm.declineReceipt, DeclineReceiptState.failed);
      expect(vm.declineReceiptProblem?.code, TerminalErrorCode.network);
      // The stage's own problem (the decline) is untouched.
      expect(vm.problem?.code, TerminalErrorCode.declined);

      repo.receiptError = null;
      expect(await vm.sendDeclineReceipt('sam@example.com'), isTrue);
      expect(vm.declineReceipt, DeclineReceiptState.sent);
      expect(vm.declineReceiptProblem, isNull);
      vm.dispose();
    });

    test('the server\'s limit ends it', () async {
      final vm = await declined();
      repo.receiptError = TerminalServerError.from(
        const RateLimitedException(
          message: 'Too many',
          body: {'message': 'Too many', 'error_code': 'receipt_limit'},
        ),
      );

      expect(await vm.sendDeclineReceipt('sam@example.com'), isFalse);
      expect(vm.declineReceipt, DeclineReceiptState.limit);

      repo.receiptError = null;
      expect(await vm.sendDeclineReceipt('sam@example.com'), isFalse);
      expect(repo.calls.where((c) => c.startsWith('receipt')).length, 1);
      vm.dispose();
    });

    test(
      'a plain throttle (a 429 with no code) is a failure, not the limit',
      () {
        expect(TerminalServerError.from(const RateLimitedException()), isNull);
      },
    );
  });
}
