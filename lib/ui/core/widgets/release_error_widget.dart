import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/version.dart';
import 'package:admin/l10n/localization.dart';

/// What a widget that threw while building shows in a release or profile
/// build, in place of Flutter's plain light-grey box. Installed by `main.dart`
/// (`ErrorWidget.builder = releaseErrorWidgetBuilder`) everywhere but debug,
/// which keeps the framework's red screen.
///
/// The grey box told a user nothing and gave us nothing to go on:
/// invoiceninja/app#211 was a whole window of it on an Intel Mac, before
/// sign-in, so Sentry (opt-in per signed-in account) sent nothing either.
/// This names the error and offers **Copy Error**, so a report carries the
/// exception. The error itself has already reached `FlutterError.onError`
/// (Sentry and the debug capture store) by the time this builds.
///
/// It can be asked to build anywhere — above `MaterialApp`, with no theme,
/// no `Localization` and no `Directionality`, or in a list cell — so:
/// - every dependency is optional: tokens fall back to [InTheme.light] /
///   [InTheme.dark] by platform brightness, strings to English;
/// - every inherited lookup it makes is caught, so a broken `Localization`
///   or theme above it cannot make it throw and recurse through the builder;
/// - [_ErrorBox] fills a bounded axis, takes a panel-sized 560×360 on an
///   unbounded one (where the framework's box takes 100000 and a centred
///   panel would sit off screen), and reports zero intrinsics, so it is safe
///   under an `IntrinsicHeight` or in a scrollable, where a `LayoutBuilder`
///   would throw;
/// - below [kReleaseErrorPanelMinSize] it paints a plain neutral box and
///   neither paints, hit-tests nor lets focus into the panel: a broken cell
///   gets no panel, a broken screen does.
Widget releaseErrorWidgetBuilder(FlutterErrorDetails details) =>
    ReleaseErrorWidget(details: details);

/// The smallest box that shows the panel; anything smaller is a plain box.
const Size kReleaseErrorPanelMinSize = Size(280, 220);

/// Longest exception text shown on screen; Copy Error carries all of it.
const int _kShownMessageMax = 1200;

/// Stack lines Copy Error carries — enough to name the frame that threw.
const int _kCopiedStackLines = 40;

class ReleaseErrorWidget extends StatefulWidget {
  const ReleaseErrorWidget({required this.details, super.key});

  final FlutterErrorDetails details;

  @override
  State<ReleaseErrorWidget> createState() => _ReleaseErrorWidgetState();

  /// What Copy Error puts on the clipboard: the build, the platform, the
  /// exception and the top of its stack.
  @visibleForTesting
  static String reportText(FlutterErrorDetails details) {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    final buffer = StringBuffer()
      ..writeln('Invoice Ninja ${AppVersion.kClientVersion} ($platform)')
      ..writeln()
      ..writeln(_exceptionText(details));
    final stack = details.stack?.toString().trim() ?? '';
    if (stack.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(stack.split('\n').take(_kCopiedStackLines).join('\n'));
    }
    return buffer.toString().trim();
  }

  static String _exceptionText(FlutterErrorDetails details) {
    try {
      return details.exceptionAsString().trim();
    } catch (_) {
      // A toString that throws must not take the error screen down with it.
      return details.exception.runtimeType.toString();
    }
  }
}

class _ReleaseErrorWidgetState extends State<ReleaseErrorWidget> {
  /// Whether the box is big enough to show the panel — set by
  /// [_RenderErrorBox] after layout, read by the panel to keep focus out of
  /// a Copy Error button nobody can see.
  final ValueNotifier<bool> _shown = ValueNotifier(false);

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  InTheme _theme() {
    try {
      final themed = Theme.of(context).extension<InTheme>();
      if (themed != null) return themed;
    } catch (_) {
      // Whatever broke may be above the theme; the defaults still render.
    }
    final brightness =
        MediaQuery.maybePlatformBrightnessOf(context) ??
        PlatformDispatcher.instance.platformBrightness;
    return brightness == Brightness.dark ? InTheme.dark : InTheme.light;
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme();
    Widget box = _ErrorBox(
      background: theme.surfaceAlt,
      shown: _shown,
      child: _ErrorPanel(details: widget.details, theme: theme, shown: _shown),
    );
    if (Directionality.maybeOf(context) == null) {
      box = Directionality(textDirection: TextDirection.ltr, child: box);
    }
    return box;
  }
}

class _ErrorPanel extends StatefulWidget {
  const _ErrorPanel({
    required this.details,
    required this.theme,
    required this.shown,
  });

  final FlutterErrorDetails details;
  final InTheme theme;
  final ValueListenable<bool> shown;

  @override
  State<_ErrorPanel> createState() => _ErrorPanelState();
}

class _ErrorPanelState extends State<_ErrorPanel> {
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(
        ClipboardData(text: ReleaseErrorWidget.reportText(widget.details)),
      );
    } catch (_) {
      // A refused clipboard (a browser without permission) leaves the copy
      // icon as it was; the error itself is already on screen.
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    // No `Localization` above a failure at the root: English, as the boot
    // screens that render before `Services` exists.
    // Caught: a broken Custom Labels overlay throws from inside
    // `Localization`, and this widget is what draws that failure.
    String tr(String key, String english) {
      try {
        final value = Localization.of(context)?.lookup(key);
        return value == null || value == key ? english : value;
      } catch (_) {
        return english;
      }
    }

    var message = ReleaseErrorWidget._exceptionText(widget.details);
    if (message.length > _kShownMessageMax) {
      message = '${message.substring(0, _kShownMessageMax)}…';
    }
    return Material(
      color: t.surfaceAlt,
      // No `SafeArea`: above `MaterialApp` there may be no `MediaQuery`,
      // and the padding below clears a notch on its own.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(InSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 32, color: t.overdue),
                const SizedBox(height: InSpacing.sm),
                Semantics(
                  header: true,
                  headingLevel: 1,
                  child: Text(
                    tr('an_error_occurred', 'An error occurred'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: InSpacing.sm),
                Flexible(
                  child: SingleChildScrollView(
                    child: Directionality(
                      // An exception is code, not prose: left to right in
                      // every language (docs/right-to-left-layout.md).
                      textDirection: TextDirection.ltr,
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: t.ink2,
                          fontSize: 13,
                          fontFamily: kMonoFontFamily,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: InSpacing.xl),
                ValueListenableBuilder<bool>(
                  valueListenable: widget.shown,
                  builder: (context, shown, child) =>
                      ExcludeFocus(excluding: !shown, child: child!),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 40),
                      foregroundColor: t.ink,
                    ),
                    onPressed: _copy,
                    icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
                    label: Text(tr('copy_error', 'Copy Error')),
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

/// Sizes like the framework's `RenderErrorBox` and shows [child] only when
/// that size is at least [kReleaseErrorPanelMinSize].
class _ErrorBox extends SingleChildRenderObjectWidget {
  const _ErrorBox({
    required this.background,
    required this.shown,
    required super.child,
  });

  final Color background;
  final ValueNotifier<bool> shown;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderErrorBox(background, shown);

  @override
  void updateRenderObject(BuildContext context, _RenderErrorBox renderObject) {
    renderObject
      ..background = background
      ..shown = shown;
  }
}

class _RenderErrorBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderErrorBox(this._background, this.shown);

  /// The size taken on an unbounded axis: room for the panel, where the
  /// framework's `RenderErrorBox` takes 100000 and the panel, centred in
  /// that, would sit 50000 px down a list.
  static const Size _kUnbounded = Size(560, 360);

  /// Told, after each layout that changes it, whether the panel shows.
  ValueNotifier<bool> shown;

  Color _background;
  set background(Color value) {
    if (value == _background) return;
    _background = value;
    markNeedsPaint();
  }

  bool _showsChild = false;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    Size(
      constraints.hasBoundedWidth ? constraints.maxWidth : _kUnbounded.width,
      constraints.hasBoundedHeight ? constraints.maxHeight : _kUnbounded.height,
    ),
  );

  // Zero intrinsics, like `RenderErrorBox`: an `IntrinsicHeight` row asks,
  // and must not make the panel lay out at a size it never gets.
  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 0;
  @override
  double computeMinIntrinsicHeight(double width) => 0;
  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  void performLayout() {
    _showsChild =
        child != null &&
        size.width >= kReleaseErrorPanelMinSize.width &&
        size.height >= kReleaseErrorPanelMinSize.height;
    // A small box still lays its panel out — at the panel's own minimum,
    // where it fits — and skips painting and hit-testing it, while `shown`
    // keeps focus out of it: a mounted subtree left unlaid is what focus
    // traversal measures and throws on (docs/upstream-workarounds.md,
    // entry 17).
    child?.layout(
      BoxConstraints.tight(_showsChild ? size : kReleaseErrorPanelMinSize),
    );
    if (shown.value != _showsChild) {
      // Not during layout: the notifier rebuilds the panel's focus gate.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached) shown.value = _showsChild;
      });
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawRect(offset & size, Paint()..color = _background);
    if (_showsChild) context.paintChild(child!, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _showsChild && child!.hitTest(result, position: position);

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_showsChild) super.visitChildrenForSemantics(visitor);
  }
}
