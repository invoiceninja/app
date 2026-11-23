import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/login_response_api_model.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/auth_service.dart';
import 'package:admin/data/services/password_cache.dart';
import 'package:admin/data/services/token_storage.dart';
import 'package:admin/ui/features/auth/view_models/login_view_model.dart';

/// Cloudflare's "Verify you are human" in the server's place on the login
/// screen (invoiceninja/invoiceninja#13484, docs/cloudflare-challenge.md): a
/// self-hosted server's is held for the check, never called unreachable; the
/// hosted service's is explained, with no web view.

CloudflareChallengeException _challenge(String url) =>
    CloudflareChallengeException(
      url: Uri.parse('$url/api/v1/login'),
      statusCode: 403,
      rayId: '8f1a2b3c4d5e6f70-AMS',
    );

class _Challenged implements AuthService {
  _Challenged(this.url);

  final String url;
  int precheckCalls = 0;

  @override
  Future<LoginPrecheck?> precheck({
    required String baseUrl,
    required bool isHosted,
    required String email,
  }) async {
    precheckCalls++;
    throw _challenge(url);
  }

  @override
  Future<LoginResponseApi> login({
    required String baseUrl,
    required bool isHosted,
    required String email,
    required String password,
    String? oneTimePassword,
    String? secret,
  }) async => throw _challenge(url);

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  LoginViewModel vmFor(String url, {required bool hosted}) =>
      LoginViewModel(
          auth: AuthRepository(
            db: db,
            authService: _Challenged(url),
            tokenStorage: InMemoryTokenStorage(),
            passwordCache: PasswordCache(),
          ),
        )
        ..setHosted(hosted)
        ..setUrlOverride(hosted ? '' : url)
        ..setEmail('a@b.test')
        ..setPassword('pw');

  test('a self-hosted server\'s challenge is held for the check — not a '
      'toast, and never "server unreachable"', () async {
    final vm = vmFor('https://invoice.example.com', hosted: false);
    expect(await vm.continueToCredentials(), isFalse);
    expect(vm.cloudflareChallenge, isNotNull);
    expect(vm.hasRequestError, isFalse);
    expect(vm.urlErrorKey, isNull);
    expect(vm.step, LoginStep.email);

    vm.clearCloudflareChallenge();
    expect(vm.cloudflareChallenge, isNull);
  });

  test('the hosted service\'s is explained, with no check offered', () async {
    final vm = vmFor('https://invoicing.co', hosted: true);
    await vm.continueToCredentials();
    expect(vm.cloudflareChallenge, isNull);
    expect(vm.errorKey, 'cloudflare_challenge_hosted');
  });
}
