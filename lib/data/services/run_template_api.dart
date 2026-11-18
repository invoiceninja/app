import 'dart:typed_data';

import 'package:admin/data/services/api_client.dart';
import 'package:admin/data/services/api_exception.dart';

/// Run Template: renders records through a design marked as a template
/// (`designs.is_template`) and hands back the PDF — or emails it to the
/// signed-in user.
///
/// The server does this in two steps, and both are the client's job
/// (`docs/running-a-template.md`):
///
/// 1. `POST /api/v1/<entities>/bulk` with `action: template`, `ids`,
///    `template_id` and `send_email` queues `TemplateAction` and answers
///    `{message: <hash>}`. It never answers with the PDF, and it never
///    touches the records.
/// 2. `POST /api/v1/templates/preview/<hash>` answers 409 "Still working"
///    until the job has written `templates/<hash>.pdf`, then streams the file
///    **and deletes it** — the hash can be read exactly once.
///
/// With `send_email` the job mails the PDF to the user who ran it (never to a
/// client — `TemplateAction::sendEmail` addresses `$user->email`), and there
/// is nothing to poll.
///
/// Neither call writes a record, so this is not an outbox mutation: an outbox
/// row would fire step 1 and drop the hash, which is how the action used to
/// "queue" templates that never arrived (invoiceninja/app#197).
/// `readOnly: true` keeps demo mode from refusing either call.
class RunTemplateApi {
  RunTemplateApi(this._client);

  final ApiClient _client;

  /// React polls 10 × 5 s; a multi-record template on a busy queue can take
  /// longer, so the budget here is 60 × 2 s = two minutes.
  static const Duration defaultPollInterval = Duration(seconds: 2);
  static const int defaultMaxRetries = 60;

  /// Connection failures [fetchPdf] rides out before it gives up.
  static const int maxNetworkDropsInARow = 3;

  /// Step 1. [entityPath] is the plural route segment (`invoices`,
  /// `purchase_orders`, …). Returns the job hash, or null when [sendEmail]
  /// is set — the server then answers `"email sent"`, which is not a hash.
  Future<String?> start({
    required String entityPath,
    required List<String> ids,
    required String templateId,
    required bool sendEmail,
  }) async {
    final raw = await _client.postJson(
      '/api/v1/$entityPath/bulk',
      readOnly: true,
      body: <String, dynamic>{
        'action': 'template',
        'ids': ids,
        'template_id': templateId,
        'send_email': sendEmail,
      },
    );
    if (sendEmail) return null;
    final hash = raw is Map ? raw['message'] : null;
    if (hash is! String || !_kJobId.hasMatch(hash)) {
      throw const FormatException('Run template did not return a job id');
    }
    return hash;
  }

  /// Step 2: poll until the PDF is ready. [isCancelled] is checked before
  /// each attempt so a closed viewer stops polling.
  Future<Uint8List> fetchPdf(
    String hash, {
    int maxRetries = defaultMaxRetries,
    Duration pollInterval = defaultPollInterval,
    bool Function()? isCancelled,
  }) async {
    var dropsInARow = 0;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      if (isCancelled?.call() == true) throw const RunTemplateCancelled();
      try {
        final res = await _client.postRawOrPending(
          '/api/v1/templates/preview/$hash',
          readOnly: true,
          acceptedContentTypes: const {'application/pdf'},
        );
        final bytes = res.bytes;
        if (!res.isPending && bytes != null) return bytes;
        dropsInARow = 0;
      } on ConflictException catch (_) {
        // 409 "Still working....." (`TemplatePreviewController`) — wait and
        // ask again. Anything else (a 403 from `ReportPreviewRequest`, a bare
        // 404, a 5xx) is not "not yet" and ends the poll.
        dropsInARow = 0;
      } on NetworkException catch (_) {
        // The job keeps running on the server while the connection blinks,
        // and giving up here throws away a PDF that is nearly ready — a
        // Retry has to start a new job. A few drops in a row is an outage.
        if (++dropsInARow > maxNetworkDropsInARow) rethrow;
      }
      await Future<void>.delayed(pollInterval);
    }
    throw const RunTemplateTimeout();
  }

  /// One token, as `Str::uuid()` writes it — not `"email sent"`.
  static final _kJobId = RegExp(r'^[A-Za-z0-9_-]+$');
}

/// The job did not finish inside the poll budget.
class RunTemplateTimeout implements Exception {
  const RunTemplateTimeout();

  @override
  String toString() => 'The template is still rendering';
}

/// The caller stopped waiting.
class RunTemplateCancelled implements Exception {
  const RunTemplateCancelled();
}
