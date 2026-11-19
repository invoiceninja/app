import 'package:admin/data/services/api_client.dart';
import 'package:admin/data/services/api_credentials.dart';
import 'package:admin/data/services/document_versions_api.dart';
import 'package:admin/data/services/password_cache.dart';
import 'package:admin/data/services/stored_pdf.dart';
import 'package:admin/utils/file_names.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A document's own route names its file the way its email attachment and
/// portal download are named, and `getRaw(keepServerFileName: true)` is how
/// that name reaches the save (docs/file-downloads.md).
void main() {
  ApiClient clientAnswering(String disposition) => ApiClient(
    credentials: ValueNotifier<ApiCredentials?>(
      const ApiCredentials(baseUrl: 'https://test', token: 't'),
    ),
    passwordCache: PasswordCache(),
    onUnauthorized: () async {},
    httpClient: MockClient(
      (_) async => http.Response.bytes(
        [0x25, 0x50, 0x44, 0x46],
        200,
        headers: {
          'content-type': 'application/pdf',
          'content-disposition': disposition,
        },
      ),
    ),
  );

  test('a route that asks keeps the server name with the bytes', () async {
    final bytes = await clientAnswering(
      'attachment; filename="Acme Ltd - Invoice - 0042.pdf"',
    ).getRaw('/api/v1/invoice/key/download', keepServerFileName: true);
    expect(serverFileNameOf(bytes), 'Acme Ltd - Invoice - 0042.pdf');
  });

  test('a route that does not ask keeps no name', () async {
    // A saved version: its caller names it apart, so two versions of one
    // document cannot save over each other.
    final bytes = await clientAnswering(
      'attachment; filename=Invoice_0042.pdf',
    ).getRaw('/api/v1/activities/download_entity/a');
    expect(serverFileNameOf(bytes), isNull);
  });

  test(
    'the stored render keeps its name; the live_preview fallback has none',
    () async {
      final client = clientAnswering('attachment; filename=Invoice_0042.pdf');
      final stored = await fetchStoredPdf(
        client: client,
        entity: 'invoice',
        storedPdfKey: 'key',
        entityJson: const {},
        livePreview: () async => throw StateError('not reached'),
      );
      expect(serverFileNameOf(stored), 'Invoice_0042.pdf');

      final preview = await fetchStoredPdf(
        client: client,
        entity: 'invoice',
        storedPdfKey: null,
        entityJson: const {},
        livePreview: () async => Uint8List.fromList([1]),
      );
      expect(serverFileNameOf(preview), isNull);
    },
  );

  test('a saved version is never named by the server', () async {
    // Its caller suffixes the version's date and time, so two versions of
    // one document cannot save over each other.
    final bytes = await DocumentVersionsApi(
      clientAnswering('attachment; filename=Invoice_0042.pdf'),
    ).downloadVersionPdf('a1');
    expect(serverFileNameOf(bytes), isNull);
  });
}
