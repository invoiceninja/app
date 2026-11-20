import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:admin/data/services/api_client.dart';
import 'package:admin/data/services/api_credentials.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/password_cache.dart';
import 'package:admin/data/services/run_template_api.dart';

ValueListenable<ApiCredentials?> _creds() => ValueNotifier<ApiCredentials?>(
  const ApiCredentials(baseUrl: 'https://test', token: 't'),
);

RunTemplateApi _api(MockClient fake) => RunTemplateApi(
  ApiClient(
    credentials: _creds(),
    passwordCache: PasswordCache(),
    onUnauthorized: () async {},
    httpClient: fake,
  ),
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

final _pdf = Uint8List.fromList(utf8.encode('%PDF-1.7 template'));

/// The server's two-step Run Template contract (invoiceninja/app#197): the
/// bulk `template` action only answers a job hash, and the PDF has to be
/// polled from `templates/preview/<hash>`.
void main() {
  test(
    'start posts the template bulk action and returns the job hash',
    () async {
      late http.Request sent;
      final api = _api(
        MockClient((req) async {
          sent = req;
          return _json({'message': '6f1c2a0e-1b2c-4d5e-8f90-a1b2c3d4e5f6'});
        }),
      );

      final hash = await api.start(
        entityPath: 'invoices',
        ids: const ['a', 'b'],
        templateId: 'tmpl',
        sendEmail: false,
      );

      expect(hash, '6f1c2a0e-1b2c-4d5e-8f90-a1b2c3d4e5f6');
      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/v1/invoices/bulk');
      expect(jsonDecode(sent.body), {
        'action': 'template',
        'ids': ['a', 'b'],
        'template_id': 'tmpl',
        'send_email': false,
      });
    },
  );

  test(
    'start with send_email returns null — "email sent" is not a hash',
    () async {
      final api = _api(
        MockClient((_) async => _json({'message': 'email sent'})),
      );

      final hash = await api.start(
        entityPath: 'quotes',
        ids: const ['q'],
        templateId: 'tmpl',
        sendEmail: true,
      );

      expect(hash, isNull);
    },
  );

  test(
    'start with send_email throws unless the server confirms the email',
    () async {
      for (final body in <Object>[
        {'message': '6f1c2a0e-1b2c-4d5e-8f90-a1b2c3d4e5f6'},
        {'message': 'Email sent'},
        <String, Object>{},
        ['email sent'],
      ]) {
        final api = _api(MockClient((_) async => _json(body)));
        await expectLater(
          api.start(
            entityPath: 'invoices',
            ids: const ['a'],
            templateId: 'tmpl',
            sendEmail: true,
          ),
          throwsA(isA<FormatException>()),
          reason: '$body',
        );
      }
    },
  );

  test(
    'start throws when the server answers something that is not a job id',
    () async {
      final api = _api(
        MockClient((_) async => _json({'message': 'working...'})),
      );

      expect(
        api.start(
          entityPath: 'invoices',
          ids: const ['a'],
          templateId: 'tmpl',
          sendEmail: false,
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('fetchPdf retries 409 "Still working" until the PDF arrives', () async {
    var polls = 0;
    final api = _api(
      MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/api/v1/templates/preview/h1');
        polls++;
        if (polls <= 2) return _json({'message': 'Still working.....'}, 409);
        return http.Response.bytes(
          _pdf,
          200,
          headers: const {'content-type': 'application/pdf'},
        );
      }),
    );

    final bytes = await api.fetchPdf(
      'h1',
      pollInterval: const Duration(milliseconds: 1),
    );

    expect(bytes, _pdf);
    expect(polls, 3);
  });

  test(
    'fetchPdf gives up with RunTemplateTimeout once the budget is spent',
    () async {
      var polls = 0;
      final api = _api(
        MockClient((_) async {
          polls++;
          return _json({'message': 'Still working.....'}, 409);
        }),
      );

      await expectLater(
        api.fetchPdf(
          'h1',
          maxRetries: 3,
          pollInterval: const Duration(milliseconds: 1),
        ),
        throwsA(isA<RunTemplateTimeout>()),
      );
      expect(polls, 3);
    },
  );

  test('fetchPdf stops polling once cancelled', () async {
    var polls = 0;
    var cancelled = false;
    final api = _api(
      MockClient((_) async {
        polls++;
        cancelled = true;
        return _json({'message': 'Still working.....'}, 409);
      }),
    );

    await expectLater(
      api.fetchPdf(
        'h1',
        pollInterval: const Duration(milliseconds: 1),
        isCancelled: () => cancelled,
      ),
      throwsA(isA<RunTemplateCancelled>()),
    );
    expect(polls, 1);
  });

  test(
    'fetchPdf rides out a few connection drops while the job runs',
    () async {
      var polls = 0;
      final api = _api(
        MockClient((_) async {
          polls++;
          if (polls <= RunTemplateApi.maxNetworkDropsInARow) {
            throw http.ClientException('connection reset');
          }
          return http.Response.bytes(
            _pdf,
            200,
            headers: const {'content-type': 'application/pdf'},
          );
        }),
      );

      final bytes = await api.fetchPdf(
        'h1',
        pollInterval: const Duration(milliseconds: 1),
      );

      expect(bytes, _pdf);
    },
  );

  test('fetchPdf gives up once the drops look like an outage', () async {
    var polls = 0;
    final api = _api(
      MockClient((_) async {
        polls++;
        throw http.ClientException('connection reset');
      }),
    );

    await expectLater(
      api.fetchPdf('h1', pollInterval: const Duration(milliseconds: 1)),
      throwsA(isA<NetworkException>()),
    );
    expect(polls, RunTemplateApi.maxNetworkDropsInARow + 1);
  });

  test('fetchPdf does not retry a 403 from ReportPreviewRequest', () async {
    var polls = 0;
    final api = _api(
      MockClient((_) async {
        polls++;
        return _json({'message': 'This action is unauthorized.'}, 403);
      }),
    );

    await expectLater(
      api.fetchPdf('h1', pollInterval: const Duration(milliseconds: 1)),
      throwsA(isA<ServerException>()),
    );
    expect(polls, 1);
  });

  test('fetchPdf does not retry a real server error', () async {
    var polls = 0;
    final api = _api(
      MockClient((_) async {
        polls++;
        return _json({'message': 'boom'}, 500);
      }),
    );

    await expectLater(
      api.fetchPdf('h1', pollInterval: const Duration(milliseconds: 1)),
      throwsA(isA<ApiException>()),
    );
    expect(polls, 1);
  });
}
