import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:admin/data/services/apple_sign_in.dart';

/// The plugin's own channel; under `flutter test` it skips its platform gate
/// and asks the channel, so the credential Apple's sheet returns can be faked.
const _channel = MethodChannel('com.aboutyou.dart_packages.sign_in_with_apple');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void answer(Future<Object?> Function() reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) {
          expect(call.method, 'performAuthorizationRequest');
          return reply();
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Map<String, Object?> credential({
    String? identityToken = 'id-token',
    String authorizationCode = 'auth-code',
  }) => {
    'type': 'appleid',
    'identityToken': identityToken,
    'authorizationCode': authorizationCode,
  };

  group('reauthenticate', () {
    test('returns the identity token and the authorization code — the '
        'code is what lets the server revoke a deleted account', () async {
      answer(() async => credential());

      final reauth = await AppleSignIn.reauthenticate();

      expect(reauth?.identityToken, 'id-token');
      expect(reauth?.authorizationCode, 'auth-code');
    });

    test('an empty authorization code is no code', () async {
      answer(() async => credential(authorizationCode: ''));

      final reauth = await AppleSignIn.reauthenticate();

      expect(reauth?.identityToken, 'id-token');
      expect(reauth?.authorizationCode, isNull);
    });

    test('no identity token is no re-authentication', () async {
      answer(() async => credential(identityToken: null));

      expect(await AppleSignIn.reauthenticate(), isNull);
    });

    test('a dismissed sheet is null, not an error', () async {
      answer(
        () async => throw PlatformException(
          code: 'authorization-error/canceled',
          message: 'canceled',
        ),
      );

      expect(await AppleSignIn.reauthenticate(), isNull);
    });

    test('any other failure is thrown', () async {
      answer(
        () async => throw PlatformException(
          code: 'authorization-error/failed',
          message: 'failed',
        ),
      );

      await expectLater(
        AppleSignIn.reauthenticate(),
        throwsA(isA<SignInWithAppleAuthorizationException>()),
      );
    });
  });

  test('identityToken is still the token alone', () async {
    answer(() async => credential());

    expect(await AppleSignIn.identityToken(), 'id-token');
  });
}
