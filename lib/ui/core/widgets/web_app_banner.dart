import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/idle_timeout_controller.dart';
import 'package:admin/app/services.dart';
import 'package:admin/domain/web_app_banner.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/utils/external_url.dart';

/// Slim strip across the top of the authenticated shell, on the web build
/// only, suggesting Invoice Ninja Web (the React app, hosted only) and the
/// native app for the browser's operating system — admin-portal's "flutter
/// web warning" strip, as a suggestion rather than a warning. The links are
/// [webAppBannerLinks]'s; each opens in a new tab.
///
/// The ✕ hides it in this browser for good (`WebAppBannerController`, a
/// device preference a sign-out keeps).
///
/// Never in the demo (`Env.isDemoBuild`, `Env.demoMode`, a session on the
/// demo server): the demo build's own strip is in this slot, and a visitor to
/// shared sample data is not choosing an app.
///
/// Stands down while the offline strip or the session-expiry strip is up —
/// the two other strips the web can show. Each of them says something the
/// user has to act on now, and one strip at a time keeps one owner of the top
/// inset (CLAUDE.md § Design system, "One surface, one safe-area owner"). The
/// certificate strip never shows on the web: the browser does the TLS.
class WebAppBanner extends StatefulWidget {
  const WebAppBanner({
    super.key,
    this.isWeb = kIsWeb,
    this.isDemoBuild = Env.isDemoBuild,
    this.demoMode = Env.demoMode,
  });

  final bool isWeb;
  final bool isDemoBuild;
  final bool demoMode;

  @override
  State<WebAppBanner> createState() => _WebAppBannerState();
}

class _WebAppBannerState extends State<WebAppBanner> {
  /// Hoisted so a rebuild doesn't re-subscribe. Null off the web, where
  /// nothing here reads [Services] at all.
  Stream<bool>? _online;

  bool get _inert => !widget.isWeb || widget.isDemoBuild || widget.demoMode;

  @override
  Widget build(BuildContext context) {
    // Before any `Services` read: off the web (every widget test of the
    // shell) this is nothing, and touches nothing.
    if (_inert) return const SizedBox.shrink();
    final services = context.read<Services>();
    final banner = services.webAppBanner;
    final expiring =
        context.read<IdleTimeoutController?>()?.expiringSoon ?? const _Never();
    final online = _online ??= services.connectivity.isOnlineStream;
    // The stream outermost and always mounted: it is single-subscription,
    // so a StreamBuilder remounted after the strip hid would listen twice.
    return StreamBuilder<bool>(
      stream: online,
      builder: (context, snapshot) => ListenableBuilder(
        listenable: Listenable.merge([banner, services.auth.session, expiring]),
        builder: (context, _) {
          final session = services.auth.session.value;
          if (snapshot.data == false || banner.dismissed || expiring.value) {
            return const SizedBox.shrink();
          }
          if (session == null || session.isDemo) {
            return const SizedBox.shrink();
          }
          final links = webAppBannerLinks(
            platform: defaultTargetPlatform,
            isHosted: session.isHosted,
            whiteLabeled: session.isWhiteLabeledSelfHost,
          );
          if (links.isEmpty) return const SizedBox.shrink();
          return WebAppStrip(
            links: links,
            onDismiss: () => unawaited(banner.dismiss()),
          );
        },
      ),
    );
  }
}

/// A [ValueListenable] that is always false: the idle-timeout seam when no
/// controller is provided.
class _Never implements ValueListenable<bool> {
  const _Never();

  @override
  bool get value => false;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// The strip itself — public so its layout is testable without [Services].
class WebAppStrip extends StatelessWidget {
  const WebAppStrip({required this.links, required this.onDismiss, super.key});

  final WebAppBannerLinks links;
  final VoidCallback onDismiss;

  static String _nativeLabelKey(NativeAppPlatform platform) =>
      switch (platform) {
        NativeAppPlatform.ios => 'web_app_banner_get_ios',
        NativeAppPlatform.android => 'web_app_banner_get_android',
        NativeAppPlatform.mac => 'web_app_banner_get_mac',
        NativeAppPlatform.windows => 'web_app_banner_get_windows',
        NativeAppPlatform.linux => 'web_app_banner_get_linux',
      };

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final touch = Env.isTouchPrimary;
    // Pointer: a slim one-line strip, like the demo build's. Touch keeps the
    // 44 px target on every button (CLAUDE.md § Design system — gated on the
    // platform, never the viewport).
    final buttonHeight = touch ? InSizes.touchTarget : 28.0;
    final webUrl = links.webAppUrl;
    final nativeUrl = links.nativeUrl;
    final nativePlatform = links.nativePlatform;
    final message = context.tr(
      webUrl != null && nativeUrl != null
          ? 'web_app_banner_both'
          : webUrl != null
          ? 'web_app_banner_web_only'
          : 'web_app_banner_native_only',
    );
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: tokens.accentInk,
      minimumSize: Size(48, buttonHeight),
      padding: const EdgeInsets.symmetric(horizontal: InSpacing.sm),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      // Standard, or the desktop theme's compact density takes 8 off the
      // minimum (docs/touch-targets.md, trap 2).
      visualDensity: VisualDensity.standard,
    );
    return Material(
      key: const ValueKey('web_app_banner'),
      color: tokens.accentSoft,
      // The same inset handling as `OfflineBanner`, which this never shows
      // beside (see [WebAppBanner]).
      child: Semantics(
        container: true,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: InSpacing.lg(context),
              end: InSpacing.xs,
              top: 1,
              bottom: 1,
            ),
            child: Row(
              children: [
                Icon(Icons.devices_outlined, size: 16, color: tokens.accentInk),
                const SizedBox(width: InSpacing.sm),
                Expanded(
                  // One line on a desktop; on a phone the sentence keeps the
                  // first line and the buttons wrap under it.
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: InSpacing.xs,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: InSpacing.sm,
                        ),
                        child: Text(
                          message,
                          style: TextStyle(color: tokens.ink2, fontSize: 12),
                        ),
                      ),
                      if (webUrl != null)
                        TextButton(
                          key: const ValueKey('web_app_banner_open_web'),
                          style: buttonStyle,
                          onPressed: () => openExternalUrl(context, webUrl),
                          child: Text(context.tr('web_app_banner_open_web')),
                        ),
                      if (nativeUrl != null && nativePlatform != null)
                        TextButton(
                          key: const ValueKey('web_app_banner_get_app'),
                          style: buttonStyle,
                          onPressed: () => openExternalUrl(context, nativeUrl),
                          child: Text(
                            context.tr(_nativeLabelKey(nativePlatform)),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('web_app_banner_dismiss'),
                  tooltip: context.tr('web_app_banner_dismiss'),
                  onPressed: onDismiss,
                  icon: Icon(Icons.close, size: 16, color: tokens.ink2),
                  padding: EdgeInsets.zero,
                  // Standard, or the desktop theme's compact density takes 8 off
                  // the explicit size (docs/touch-targets.md, trap 2).
                  visualDensity: VisualDensity.standard,
                  constraints: BoxConstraints.tightFor(
                    width: buttonHeight,
                    height: buttonHeight,
                  ),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
