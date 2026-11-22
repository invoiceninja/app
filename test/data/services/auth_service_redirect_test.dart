import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/api_uri.dart';
import 'package:admin/data/services/auth_service.dart';

/// A sign-in request answered with a redirect, or with something that is
/// not Invoice Ninja, must say so, never follow it with the password, and
/// never reach the user as "Method not supported for this route" or a
/// `FormatException`.
///
/// `dart:io` follows a POST only through a 303, as a GET the server answers
/// with that 404; a self-hosted `http://` address on a server that sends
/// everything to `https://` was the case that shipped (a Flatpak user).
void main() {
  AuthService serviceReturning(http.Response Function(http.Request) handler) =>
      AuthService(httpClient: MockClient((req) async => handler(req)));

  http.Response redirect(int status, String? location) => http.Response(
    '',
    status,
    headers: {if (location != null) 'location': location},
  );

  group('AuthService never follows a redirect', () {
    test('every POST goes out with followRedirects off', () async {
      bool? follows;
      final svc = serviceReturning((req) {
        follows = req.followRedirects;
        return http.Response(jsonEncode({'data': <Object>[]}), 200);
      });
      await svc.login(
        baseUrl: 'https://ninja.example.com',
        isHosted: false,
        email: 'a@b.test',
        password: 'pw',
      );
      expect(follows, isFalse);
    });

    test('an http → https redirect of the precheck names the https base', () {
      final svc = serviceReturning(
        (req) => redirect(301, req.url.replace(scheme: 'https').toString()),
      );
      expect(
        svc.precheck(
          baseUrl: 'http://ninja.example.com',
          isHosted: false,
          email: 'a@b.test',
        ),
        throwsA(
          isA<ServerRedirectException>()
              .having((e) => e.statusCode, 'statusCode', 301)
              .having(
                (e) => e.suggestedBaseUrl,
                'suggestedBaseUrl',
                'https://ninja.example.com',
              ),
        ),
      );
    });

    test('a redirect of the login itself is a ServerRedirectException', () {
      final svc = serviceReturning((_) => redirect(302, '/login'));
      expect(
        svc.login(
          baseUrl: 'https://ninja.example.com',
          isHosted: false,
          email: 'a@b.test',
          password: 'pw',
        ),
        throwsA(
          isA<ServerRedirectException>().having(
            (e) => e.suggestedBaseUrl,
            'suggestedBaseUrl',
            isNull,
          ),
        ),
      );
    });

    test('a precheck that arrived as a GET keeps step 1 (not "no answer")', () {
      final svc = serviceReturning(
        (_) => http.Response(
          jsonEncode({'message': 'Method not supported for this route'}),
          404,
        ),
      );
      expect(
        svc.precheck(
          baseUrl: 'https://ninja.example.com',
          isHosted: false,
          email: 'a@b.test',
        ),
        throwsA(
          isA<ServerException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
    });

    test(
      'an older server\'s missing precheck route still fails open',
      () async {
        final svc = serviceReturning(
          (_) => http.Response(
            jsonEncode({'message': 'Route does not exist'}),
            404,
            headers: const {'x-app-version': '5.12.0'},
          ),
        );
        expect(
          await svc.precheck(
            baseUrl: 'https://ninja.example.com',
            isHosted: false,
            email: 'a@b.test',
          ),
          isNull,
        );
      },
    );
  });

  group('an answer that is not Invoice Ninja', () {
    test('a web page at /login is UnexpectedResponseException', () {
      final svc = serviceReturning(
        (_) => http.Response('<!doctype html><title>Welcome</title>', 200),
      );
      expect(
        svc.login(
          baseUrl: 'https://www.example.com',
          isHosted: false,
          email: 'a@b.test',
          password: 'pw',
        ),
        throwsA(
          isA<UnexpectedResponseException>().having(
            (e) => e.statusCode,
            'statusCode',
            200,
          ),
        ),
      );
    });

    test('JSON that is not an object is UnexpectedResponseException', () {
      final svc = serviceReturning((_) => http.Response('[]', 200));
      expect(
        svc.login(
          baseUrl: 'https://www.example.com',
          isHosted: false,
          email: 'a@b.test',
          password: 'pw',
        ),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });
  });

  group('baseUrlFromRedirect', () {
    final login = Uri.parse('http://ninja.example.com/api/v1/login');

    test('the same route on https gives the https base', () {
      expect(
        baseUrlFromRedirect(login, 'https://ninja.example.com/api/v1/login'),
        'https://ninja.example.com',
      );
    });

    test('keeps a sub-path and a port, drops a query', () {
      expect(
        baseUrlFromRedirect(
          Uri.parse('http://h.example/ninja/api/v1/login/precheck'),
          'https://h.example:8443/ninja/api/v1/login/precheck?x=1',
        ),
        'https://h.example:8443/ninja',
      );
    });

    test('a relative location resolves against the request', () {
      expect(
        baseUrlFromRedirect(login, '/public/api/v1/login'),
        'http://ninja.example.com/public',
      );
    });

    test('anything but the same route is no suggestion', () {
      for (final location in [
        null,
        '',
        'https://ninja.example.com/',
        'https://ninja.example.com/login',
        'https://ninja.example.com/api/v1/login/',
        'ftp://ninja.example.com/api/v1/login',
        'https://user:pw@ninja.example.com/api/v1/login',
      ]) {
        expect(
          baseUrlFromRedirect(login, location),
          isNull,
          reason: '$location',
        );
      }
    });
  });
}
