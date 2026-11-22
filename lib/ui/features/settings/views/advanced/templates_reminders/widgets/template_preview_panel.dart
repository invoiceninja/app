import 'package:material_ui/material_ui.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/data/services/templates_api.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/html_web_view.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/utils/html_preview.dart';
import 'package:admin/ui/features/settings/views/advanced/templates_reminders/preview_controller.dart';

/// Live preview of the rendered email template. Listens to a
/// [PreviewController] for state transitions (idle / loading / loaded /
/// error) and renders the appropriate UI.
///
/// Platform switch on the success branch:
///
/// * iOS / Android / macOS / Windows — [HtmlWebView] loads the full HTML
///   wrapper returned from `/api/v1/templates` in a native web view (WebView2
///   on Windows). CSS, inline images, and the server's template chrome all
///   render as a mail client renders them; no script runs.
/// * Web (incl. mobile browsers) + Linux, and a Windows whose WebView2
///   runtime is missing — a web `<iframe>` platform view hits a skwasm
///   positioning bug under the project's `--wasm` build, and Linux has no web
///   view the app ships, so we render the server-substituted body HTML with
///   `flutter_widget_from_html_core` (`HtmlWidget`). Inline styles apply;
///   `<style>`-block CSS from the wrapper does not — acceptable for a
///   preview. The server-side variable substitution still happens (the
///   `/templates` POST runs on every debounced edit); only the rendering
///   layer differs.
///
/// [HtmlWebView.supported] checks `kIsWeb` first, and that is load-bearing:
/// a mobile browser reports iOS/Android as its `defaultTargetPlatform`.
class TemplatePreviewPanel extends StatelessWidget {
  const TemplatePreviewPanel({super.key, required this.controller});

  final PreviewController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.inTheme;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(InRadii.r3),
        border: Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: _PreviewStates(controller: controller),
    );
  }
}

/// The preview's states. While the next preview loads (a debounced edit),
/// the last one stays up under a thin progress bar rather than giving way
/// to a spinner: unmounting it would tear down its web view (and on
/// Windows its WebView2 process) on every keystroke, and start another.
class _PreviewStates extends StatefulWidget {
  const _PreviewStates({required this.controller});

  final PreviewController controller;

  @override
  State<_PreviewStates> createState() => _PreviewStatesState();
}

class _PreviewStatesState extends State<_PreviewStates> {
  TemplatePreview? _last;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TemplatePreviewState>(
        valueListenable: widget.controller,
        builder: (context, state, _) {
          switch (state) {
            case TemplatePreviewLoaded(:final preview):
              _last = preview;
            case TemplatePreviewIdle() || TemplatePreviewError():
              _last = null;
            case TemplatePreviewLoading():
              break;
          }
          final last = _last;
          if (last != null) {
            return Stack(
              children: [
                _PreviewBody(preview: last),
                if (state is TemplatePreviewLoading)
                  const PositionedDirectional(
                    top: 0,
                    start: 0,
                    end: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            );
          }
          return switch (state) {
            TemplatePreviewIdle() => const _PreviewPlaceholder(),
            TemplatePreviewLoading() => const _PreviewLoading(),
            TemplatePreviewLoaded(:final preview) => _PreviewBody(
              preview: preview,
            ),
            TemplatePreviewError(:final kind) => _PreviewError(
              kind: kind,
              onRetry: widget.controller.refresh,
            ),
          };
        },
      );
}

/// Fills the panel's bounded height when one is given (side-by-side right
/// column, fullscreen `_PreviewSheet`), and falls back to a fixed 600px
/// when the panel is laid out without a height bound. Keeps every preview
/// state the same height and prevents the `RenderFlex overflowed` that a
/// hard-coded 600 caused inside a shorter parent.
class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => c.hasBoundedHeight
          ? SizedBox.expand(child: child)
          : SizedBox(height: 600, child: child),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder();

  @override
  Widget build(BuildContext context) {
    final t = context.inTheme;
    return _PreviewFrame(
      child: Container(
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: InSpacing.lg(context)),
        child: Text(
          context.tr('template_preview_placeholder'),
          textAlign: TextAlign.center,
          style: TextStyle(color: t.ink2, fontSize: 14),
        ),
      ),
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading();

  @override
  Widget build(BuildContext context) {
    return const _PreviewFrame(
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.kind, required this.onRetry});

  final TemplatePreviewErrorKind kind;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNetwork = kind == TemplatePreviewErrorKind.network;
    final labelKey = isNetwork
        ? 'no_internet_connection'
        : 'error_refresh_page';
    return _PreviewFrame(
      child: Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isNetwork ? Icons.wifi_off : Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              context.tr(labelKey),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              // Network errors can't be solved by an immediate retry —
              // disable the button so the user knows to fix connectivity
              // first. Timeout and server-side errors are retryable.
              onPressed: isNetwork ? null : onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

/// The subject and the email. Keeps the user's zoom across previews (each
/// debounced edit is a new one), and the fit the web view reported, for the
/// zoom control to start from.
class _PreviewBody extends StatefulWidget {
  const _PreviewBody({required this.preview});

  final TemplatePreview preview;

  @override
  State<_PreviewBody> createState() => _PreviewBodyState();
}

class _PreviewBodyState extends State<_PreviewBody> {
  /// The user's zoom; null fits the email to the pane.
  double? _zoom;

  /// The fit the web view last reported.
  double _fit = 1;

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    return LayoutBuilder(
      builder: (context, c) {
        // A native web view where there is one; the HtmlWidget render
        // elsewhere. See the class doc.
        final body = HtmlWebView(
          html: preview.wrapper,
          // An email is read on white, whatever the app's theme: on a dark
          // surface a transparent web view showed dark text on dark.
          background: Colors.white,
          zoom: _zoom,
          onFitZoom: (fit) {
            if (mounted && fit != _fit) setState(() => _fit = fit);
          },
          fallback: (_) => _HtmlPreview(body: preview.body),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewSubjectBar(
              subject: preview.subject,
              // Only a web view zooms; the fallback reflows to its width.
              zoom: HtmlWebView.supported
                  ? _PreviewZoom(
                      zoom: _zoom ?? _fit,
                      fitted: _zoom == null,
                      onZoom: (zoom) => setState(() => _zoom = zoom),
                    )
                  : null,
            ),
            if (c.hasBoundedHeight)
              Expanded(child: body)
            else
              SizedBox(height: 600, child: body),
          ],
        );
      },
    );
  }
}

class _PreviewSubjectBar extends StatelessWidget {
  const _PreviewSubjectBar({required this.subject, this.zoom});

  final String subject;

  /// The zoom control, at the end of the bar.
  final Widget? zoom;

  @override
  Widget build(BuildContext context) {
    final t = context.inTheme;
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsetsDirectional.only(
        start: InSpacing.lg(context),
        // The zoom buttons carry their own padding.
        end: zoom == null ? InSpacing.lg(context) : InSpacing.xs,
        top: zoom == null ? InSpacing.md(context) : InSpacing.xs,
        bottom: zoom == null ? InSpacing.md(context) : InSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Text(
            '${context.tr('subject')}: ',
            style: theme.textTheme.bodySmall?.copyWith(color: t.ink2),
          ),
          Expanded(
            child: Text(
              subject.isEmpty ? '—' : subject,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: t.ink,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?zoom,
        ],
      ),
    );
  }
}

/// − 60 % + over the email, and a Fit button once the user has zoomed. The
/// one zoom a desktop has (macOS's web view has no magnification, and
/// WebView2 here gets no Ctrl+wheel), and on touch it says the email can be
/// zoomed at all, beside the pinch. A beta user could do neither
/// ("You can't zoom in or out to see the email preview").
class _PreviewZoom extends StatelessWidget {
  const _PreviewZoom({
    required this.zoom,
    required this.fitted,
    required this.onZoom,
  });

  /// The zoom on screen: the user's, or the fit.
  final double zoom;

  /// Whether that is the fit (no Fit button then).
  final bool fitted;

  /// A new zoom; null goes back to the fit.
  final ValueChanged<double?> onZoom;

  @override
  Widget build(BuildContext context) {
    final t = context.inTheme;
    final touch = Env.isTouchPrimary;
    Widget button({
      required Key key,
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) => IconButton(
      key: key,
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      // A 44 px target on touch, never inflated to 48 in the bar; compact
      // with a pointer (docs/touch-targets.md).
      constraints: touch
          ? const BoxConstraints.tightFor(width: 44, height: 44)
          : null,
      style: touch
          ? const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap)
          : null,
      visualDensity: touch ? null : VisualDensity.compact,
    );
    final out = previewZoomStep(zoom, zoomIn: false);
    final inward = previewZoomStep(zoom, zoomIn: true);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          key: const ValueKey('preview_zoom_out'),
          icon: Icons.remove,
          tooltip: context.tr('zoom_out'),
          onPressed: out == zoom ? null : () => onZoom(out),
        ),
        Semantics(
          liveRegion: true,
          child: SizedBox(
            width: 44,
            child: LtrText(
              '${(zoom * 100).round()}%',
              key: const ValueKey('preview_zoom_level'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: t.ink2),
            ),
          ),
        ),
        button(
          key: const ValueKey('preview_zoom_in'),
          icon: Icons.add,
          tooltip: context.tr('zoom_in'),
          onPressed: inward == zoom ? null : () => onZoom(inward),
        ),
        if (!fitted)
          button(
            key: const ValueKey('preview_zoom_fit'),
            icon: Icons.fit_screen_outlined,
            tooltip: context.tr('fit_to_width'),
            onPressed: () => onZoom(null),
          ),
      ],
    );
  }
}

/// Renders the server-substituted email body HTML via
/// `flutter_widget_from_html_core` on the web and Linux (anywhere without a
/// usable web view). Rebuilds re-parse the new HTML — no manual lifecycle needed.
class _HtmlPreview extends StatelessWidget {
  const _HtmlPreview({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    // Render the email body on white in both light and dark mode: the real
    // email (and the mobile WebView / PDF preview) is white, so painting it on
    // the dark app surface would be dark-on-dark and unreadable. Force black
    // text to read on the forced-white background regardless of app brightness.
    // `_PreviewBody` always hands this a bounded height (Expanded / SizedBox),
    // so the inner scroll view lays out fine.
    return ColoredBox(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: InSpacing.lg(context),
          vertical: InSpacing.md(context),
        ),
        child: HtmlWidget(
          body,
          textStyle: const TextStyle(color: Colors.black),
        ),
      ),
    );
  }
}
