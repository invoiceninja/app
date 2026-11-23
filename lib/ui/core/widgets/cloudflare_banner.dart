import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/services/api_credentials.dart';
import 'package:admin/data/services/cloudflare/cloudflare_clearance.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/cloudflare_check.dart';

/// Strip across the top of the authenticated shell while the signed-in
/// server's Cloudflare zone is asking this device to verify it is human
/// (invoiceninja/invoiceninja#13484, docs/cloudflare-challenge.md).
///
/// Nothing reaches the server until the check passes, and the outbox holds
/// every change meanwhile (`CloudflareChallengeException` is a not-sent
/// error), so the strip stays up until a request gets through.
///
/// **It never opens the check on its own.** A background sync can be
/// challenged at any moment — every 30 minutes on a default zone — and a
/// full-screen page then would land over a dialog or a half-typed edit; and
/// on a zone that refuses the app's own requests even after a pass, an
/// automatic check would pass at once from the web view's cookie and open
/// again, forever. Verify is the user's tap.
///
/// On a device with no web view to show the check in (Linux, the web), and
/// for a server the check is never offered for (hosted, the demo, plain
/// http), it explains instead, with no button.
class CloudflareBanner extends StatefulWidget {
  const CloudflareBanner({super.key});

  @override
  State<CloudflareBanner> createState() => _CloudflareBannerState();
}

class _CloudflareBannerState extends State<CloudflareBanner> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    // Before any `Services` read: a shell pumped without the provider (a
    // widget test) shows nothing and touches nothing.
    final store = context.read<CloudflareClearanceStore?>();
    if (store == null) return const SizedBox.shrink();
    final services = context.read<Services>();
    return ValueListenableBuilder<ApiCredentials?>(
      valueListenable: services.auth.credentials,
      builder: (context, creds, _) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final server = creds == null || !creds.isAuthenticated
              ? null
              : Uri.tryParse(creds.baseUrl);
          final waiting = server == null || server.host.isEmpty
              ? null
              : store.outstandingFor(server);
          if (waiting == null) return const SizedBox.shrink();
          // Hosted, the demo, or plain http: every request is still held, so
          // the strip says why, but there is nothing to verify here.
          final canVerify = store.canVerify(waiting.url);
          return _CloudflareStrip(
            message: cloudflareWaitMessage(
              context,
              waiting,
              canVerify: canVerify,
            ),
            onVerify: !cloudflareCheckAvailable || !canVerify
                ? null
                : _checking
                ? () {}
                : () => _verify(waiting, creds!.companyId),
            busy: _checking,
          );
        },
      ),
    );
  }

  Future<void> _verify(CloudflareChallenge waiting, String companyId) async {
    if (_checking) return;
    setState(() => _checking = true);
    final services = context.read<Services>();
    final passed = await showCloudflareCheck(context, url: waiting.url);
    if (mounted) setState(() => _checking = false);
    if (!passed) return;
    // What coming back online does: send what waited — now, not when each
    // row's not-sent park runs out — and let screens that asked something
    // meanwhile ask again.
    if (companyId.isNotEmpty) {
      unawaited(services.sync.retryNotSentRows(companyId: companyId));
    }
    services.backOnline.fire();
    unawaited(services.refreshScheduler.requestSoon());
  }
}

class _CloudflareStrip extends StatelessWidget {
  const _CloudflareStrip({
    required this.message,
    required this.onVerify,
    required this.busy,
  });

  final String message;

  /// Null where this device can't show the check (no web view).
  final VoidCallback? onVerify;

  /// The check is open: the button stays, inert.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Material(
      key: const ValueKey('cloudflare_banner'),
      color: tokens.partialSoft,
      // The same inset handling as `CertificateBanner`.
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: InSpacing.lg(context),
            vertical: InSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: tokens.partial),
              const SizedBox(width: InSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  // Never clamped: the only explanation the user gets.
                  style: TextStyle(color: tokens.ink2, fontSize: 13),
                ),
              ),
              if (onVerify != null) ...[
                const SizedBox(width: InSpacing.sm),
                TextButton(
                  key: const ValueKey('cloudflare_banner_verify'),
                  onPressed: busy ? null : onVerify,
                  child: Text(context.tr('verify')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
