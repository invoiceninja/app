import 'package:admin/app/corrupt_store_boot.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/login_response_api_model.dart';
import 'package:admin/data/repositories/auth/auth_helpers.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/auth_service.dart';
import 'package:admin/data/services/password_cache.dart';
import 'package:admin/data/services/token_storage.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/db/_corrupt_pages_interceptor.dart';

/// `refreshWithToken` answers with one company; nothing else is reachable
/// from the demo sign-in.
class _DemoAuthService implements AuthService {
  @override
  Future<LoginResponseApi> refreshWithToken({
    required String baseUrl,
    required bool isHosted,
    required String token,
  }) async => LoginResponseApi(
    data: [
      UserCompanyApi(
        user: const UserSummaryApi(id: 'demo_user'),
        company: const CompanyEnvelopeApi(id: 'co_demo', name: 'Demo'),
        token: SessionTokenApi(token: token),
        account: const AccountEnvelopeApi(
          id: 'acct_demo',
          defaultCompanyId: 'co_demo',
        ),
      ),
    ],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  // The web demo, as shipped: the store opened cleanly, a sign-out wipe the
  // previous load owed was still pending, and that wipe met a corrupt page
  // (`DELETE FROM "recurring_invoices"`, SQLITE_CORRUPT). `loginWithToken`
  // threw, `main` logged "Demo token bootstrap failed", and the visitor sat
  // on /login — on every load, because nothing ever repaired the store.
  group('the demo boot over a store that is corrupt after it opens', () {
    late InMemoryTokenStorage storage;
    late bool markStored;
    late bool storeIsCorrupt;
    late int destroyed;
    late int reloads;

    setUp(() async {
      storage = InMemoryTokenStorage();
      // What a previous load's failed sign-out wipe left behind.
      await storage.write(kAuthWipePendingKey, 'true');
      markStored = false;
      storeIsCorrupt = true;
      destroyed = 0;
      reloads = 0;
    });

    /// One page load of `_bootstrap`, from the open to the decision whose
    /// alternative was /login: the open, the demo sign-in (caught, as `main`
    /// catches it), then [corruptStoreBootStep] — whose reload is faked.
    Future<({bool signedIn, CorruptStoreBootStep step})> bootOnce({
      bool resetCures = true,
    }) async {
      final opened = await openAppDatabase(
        openExecutor: () async => storeIsCorrupt
            ? NativeDatabase.memory().interceptWith(CorruptPagesInterceptor())
            : NativeDatabase.memory(),
        destroyStore: () async {
          destroyed++;
          if (resetCures) storeIsCorrupt = false;
          return true;
        },
        markCorrupt: () async => markStored = true,
        readCorruptMark: () async => markStored,
        clearCorruptMark: () async => markStored = false,
        // The demo: a visitor has no work for the reset to wait on.
        corruptResetWaitsForOutbox: false,
      );
      final auth = AuthRepository(
        db: opened.db,
        authService: _DemoAuthService(),
        tokenStorage: storage,
        passwordCache: PasswordCache(),
      );
      try {
        await auth.loginWithToken(
          baseUrl: 'https://demo.invoiceninja.com',
          isHosted: false,
          token: 'demo_token',
        );
      } catch (_) {
        // `main`: "Demo token bootstrap failed".
      }
      final step = await corruptStoreBootStep(
        corruption: opened.corruption,
        db: opened.db,
        hadCorruptMark: opened.hadCorruptMark,
        waitsForOutbox: false,
        isWeb: true,
      );
      if (step == CorruptStoreBootStep.reload) reloads++;
      final signedIn = auth.isAuthenticated;
      await opened.db.close();
      return (signedIn: signedIn, step: step);
    }

    test('reloads once, and the reload signs the visitor in', () async {
      final first = await bootOnce();
      expect(first.signedIn, isFalse);
      expect(
        first.step,
        CorruptStoreBootStep.reload,
        reason: 'carrying on here is the /login dead end',
      );
      expect(markStored, isTrue);

      final second = await bootOnce();
      expect(destroyed, 1, reason: 'the reload\'s open reset the store');
      expect(markStored, isFalse);
      expect(second.signedIn, isTrue);
      expect(second.step, CorruptStoreBootStep.carryOn);
      expect(reloads, 1);
      expect(
        await storage.read(kAuthWipePendingKey),
        isNull,
        reason: 'the wipe the sign-out owed ran on the fresh store',
      );
    });

    test('never reloads twice when the reset does not cure it', () async {
      await bootOnce(resetCures: false);
      final second = await bootOnce(resetCures: false);
      expect(destroyed, 1);
      expect(second.signedIn, isFalse);
      expect(
        second.step,
        CorruptStoreBootStep.showRepairScreen,
        reason: 'a second automatic reload is the start of a loop',
      );
      expect(reloads, 1);
      expect(markStored, isTrue, reason: 'Try again still repairs it');
    });
  });

  group('corruptStoreBootStep', () {
    /// An opened store whose watch has (or has not) met corruption.
    Future<OpenedDatabase> openWatched({
      required bool corrupt,
      bool markWorks = true,
    }) async {
      final opened = await openAppDatabase(
        openExecutor: () async =>
            NativeDatabase.memory().interceptWith(CorruptPagesInterceptor()),
        destroyStore: () async => true,
        markCorrupt: () async => markWorks,
      );
      if (corrupt) {
        await expectLater(opened.db.wipe(), throwsA(anything));
      }
      return opened;
    }

    Future<CorruptStoreBootStep> stepFor(
      OpenedDatabase opened, {
      bool isWeb = true,
      bool hadCorruptMark = false,
      bool waitsForOutbox = false,
    }) async {
      final step = await corruptStoreBootStep(
        corruption: opened.corruption,
        db: opened.db,
        hadCorruptMark: hadCorruptMark,
        waitsForOutbox: waitsForOutbox,
        isWeb: isWeb,
      );
      await opened.db.close();
      return step;
    }

    test('carries on when nothing was found', () async {
      expect(
        await stepFor(await openWatched(corrupt: false)),
        CorruptStoreBootStep.carryOn,
      );
    });

    test('reloads on web once the mark is stored', () async {
      expect(
        await stepFor(await openWatched(corrupt: true)),
        CorruptStoreBootStep.reload,
      );
    });

    test('shows the repair screen when the mark did not stick', () async {
      // The next open could not see it, so a reload would loop.
      expect(
        await stepFor(await openWatched(corrupt: true, markWorks: false)),
        CorruptStoreBootStep.showRepairScreen,
      );
    });

    test(
      'shows the repair screen after this launch already repaired',
      () async {
        expect(
          await stepFor(await openWatched(corrupt: true), hadCorruptMark: true),
          CorruptStoreBootStep.showRepairScreen,
        );
      },
    );

    test('carries on natively: the mark repairs the next launch', () async {
      expect(
        await stepFor(await openWatched(corrupt: true), isWeb: false),
        CorruptStoreBootStep.carryOn,
      );
    });

    test('carries on while the outbox holds work a reset would lose', () async {
      final opened = await openWatched(corrupt: true);
      await opened.db.outboxDao.enqueue(
        OutboxCompanion.insert(
          companyId: 'co',
          entityType: 'client',
          entityId: 'c_1',
          mutationKind: 'update',
          payload: '{}',
          idempotencyKey: 'k1',
          nextAttemptAt: 0,
          createdAt: 0,
        ),
      );
      expect(
        await stepFor(opened, waitsForOutbox: true),
        CorruptStoreBootStep.carryOn,
      );
    });
  });
}
