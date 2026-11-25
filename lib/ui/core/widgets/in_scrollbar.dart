import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/always_show_scrollbars_controller.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/theme.dart';

/// Whether "Always show scroll bars" is on, subscribing [context] so it
/// rebuilds when the switch flips (docs/scrollbars.md).
///
/// Off when no [AlwaysShowScrollbarsController] is provided — a widget test
/// that doesn't care gets the default.
bool watchAlwaysShowScrollbars(BuildContext context) =>
    context.watch<AlwaysShowScrollbarsController?>()?.value ?? false;

/// Whether this device draws the pointer scroll bar: everywhere but a touch
/// platform (`Env.isTouchPrimary` — a phone's browser included, a desktop
/// browser not). Touch keeps Material's scroll bar untouched.
bool get pointerScrollbars => !Env.isTouchPrimary;

/// The app's [ScrollBehavior] (`MaterialApp.scrollBehavior`): Material's, but
/// a vertical scroll view's own scroll bar on a pointer platform is an
/// [InScrollbar] (docs/scrollbars.md).
///
/// Horizontal scroll views still get none of their own — the wide tables
/// place an [InScrollbar] by hand — and touch platforms get Material's
/// answer, which is no scroll bar at all.
class InScrollBehavior extends MaterialScrollBehavior {
  const InScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (!pointerScrollbars ||
        axisDirectionToAxis(details.direction) != Axis.vertical) {
      return super.buildScrollbar(context, child, details);
    }
    return InScrollbar(controller: details.controller, child: child);
  }
}

/// The app's scroll bar: on a pointer platform a thicker, ink-coloured thumb
/// that grows over a faint track under the pointer, and stays drawn while
/// "Always show scroll bars" is on; on a touch platform exactly Material's
/// [Scrollbar] (docs/scrollbars.md).
///
/// Use it wherever a scroll bar is placed by hand — `Scrollbar(` would miss
/// the preference. A scroll view's own vertical bar is already one
/// ([InScrollBehavior]).
///
/// **The thumb is pinned only while its controller has exactly one
/// position.** A theme-level `thumbVisibility: true` makes every scroll bar
/// assert, a frame later, that its controller has one attached position —
/// "has no ScrollPosition attached" for a bar placed above a scroll view that
/// has not attached yet, "attached to more than one ScrollPosition" for two
/// scroll views on one `PrimaryScrollController`. This widget asks first, on
/// every build and every metrics change, and the bar it builds asks again
/// each time it would show, so such a bar just fades as it always did.
class InScrollbar extends StatefulWidget {
  const InScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility,
    this.interactive,
    this.notificationPredicate,
    this.scrollbarOrientation,
  });

  final Widget child;

  /// The scroll view's controller. Null falls back to the
  /// [PrimaryScrollController], as [Scrollbar] does — pass one: on a pointer
  /// platform a scroll view does not take the primary controller on its own.
  final ScrollController? controller;

  /// Null follows "Always show scroll bars"; a value is the caller's own rule
  /// (What's New pins its notes while they overflow). On a pointer platform
  /// either is honoured only while [controller] has exactly one position.
  final bool? thumbVisibility;

  final bool? interactive;
  final ScrollNotificationPredicate? notificationPredicate;
  final ScrollbarOrientation? scrollbarOrientation;

  @override
  State<InScrollbar> createState() => _InScrollbarState();
}

class _InScrollbarState extends State<InScrollbar> {
  /// Whether the controller had exactly one position at the last look.
  bool _pinnable = false;

  bool _checkPinnable() {
    final controller =
        widget.controller ?? PrimaryScrollController.maybeOf(context);
    return controller != null && controller.positions.length == 1;
  }

  /// A scroll view attaching under a hand-placed bar reports its first
  /// metrics after the frame that built the bar — the moment the bar can be
  /// pinned.
  bool _onMetrics(ScrollMetricsNotification _) {
    if (_checkPinnable() == _pinnable) return false;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!pointerScrollbars) {
      return Scrollbar(
        controller: widget.controller,
        thumbVisibility: widget.thumbVisibility,
        interactive: widget.interactive,
        notificationPredicate: widget.notificationPredicate,
        scrollbarOrientation: widget.scrollbarOrientation,
        child: widget.child,
      );
    }
    final wanted = widget.thumbVisibility ?? watchAlwaysShowScrollbars(context);
    _pinnable = _checkPinnable();
    final motion = InMotion.of(context);
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: _PointerScrollbar(
        controller: widget.controller,
        thumbVisibility: wanted && _pinnable,
        interactive: widget.interactive,
        notificationPredicate:
            widget.notificationPredicate ?? defaultScrollNotificationPredicate,
        scrollbarOrientation: widget.scrollbarOrientation,
        // Material's fade, through reduced motion.
        fadeDuration: motion(const Duration(milliseconds: 300)),
        timeToFade: const Duration(milliseconds: 600),
        minThumbLength: 48,
        child: widget.child,
      ),
    );
  }
}

class _PointerScrollbar extends RawScrollbar {
  const _PointerScrollbar({
    required super.child,
    super.controller,
    super.thumbVisibility,
    super.interactive,
    super.notificationPredicate,
    super.scrollbarOrientation,
    super.fadeDuration,
    super.timeToFade,
    super.minThumbLength,
  });

  @override
  _PointerScrollbarState createState() => _PointerScrollbarState();
}

class _PointerScrollbarState extends RawScrollbarState<_PointerScrollbar> {
  late final AnimationController _active = AnimationController(vsync: this)
    ..addListener(updateScrollbarPainter);
  bool _hovered = false;
  bool _dragging = false;
  bool _inDependencies = false;
  late ScrollbarThemeData _theme;
  late ScrollbarThemeData _fallback;

  ScrollController? get _controller =>
      widget.controller ?? PrimaryScrollController.maybeOf(context);

  /// Pinned only while the controller has exactly one position — asked live,
  /// so a second scroll view attaching to a shared controller unpins the bar
  /// at its next fade instead of tripping the framework's position check.
  ///
  /// False while dependencies change: `RawScrollbarState` then schedules a
  /// debug-only check, run a frame later, that the controller still has one
  /// position. The answer here is already live at every use, and that frame
  /// is the one in which a route swaps the scroll view sharing it.
  @override
  bool get showScrollbar =>
      !_inDependencies &&
      (widget.thumbVisibility ?? false) &&
      _hasSinglePosition;

  /// Interactive only while the controller has exactly one position. A bar
  /// with none or two cannot say which scroll view a drag would move —
  /// `RawScrollbarState` already offers no drag then — and an interactive
  /// one runs the same debug position check each time it fades in or out,
  /// which is what unpinning such a bar would do.
  @override
  bool get enableGestures =>
      (widget.interactive ?? _theme.interactive ?? true) && _hasSinglePosition;

  bool get _hasSinglePosition => _controller?.positions.length == 1;

  @override
  void didChangeDependencies() {
    _theme = ScrollbarTheme.of(context);
    _fallback = pointerScrollbarTheme(
      Theme.of(context).extension<InTheme>() ?? InTheme.light,
    );
    _active.duration = InMotion.of(context)(InMotion.fast);
    _inDependencies = true;
    try {
      super.didChangeDependencies();
    } finally {
      _inDependencies = false;
    }
  }

  /// The app theme's value, else [pointerScrollbarTheme]'s — a test or a
  /// surface without the app theme still paints the app's bar.
  T _resolve<T extends Object>(
    WidgetStateProperty<T?>? Function(ScrollbarThemeData) pick,
    Set<WidgetState> states,
  ) => pick(_theme)?.resolve(states) ?? pick(_fallback)!.resolve(states)!;

  @override
  void updateScrollbarPainter() {
    const rest = <WidgetState>{};
    final active = {_dragging ? WidgetState.dragged : WidgetState.hovered};
    final t = _active.value;
    final radius = _theme.radius ?? _fallback.radius;
    final track = _resolve<bool>((d) => d.trackVisibility, active);
    scrollbarPainter
      ..color = Color.lerp(
        _resolve<Color>((d) => d.thumbColor, rest),
        _resolve<Color>((d) => d.thumbColor, active),
        t,
      )!
      ..thickness = lerpDouble(
        _resolve<double>((d) => d.thickness, rest),
        _resolve<double>((d) => d.thickness, active),
        t,
      )!
      // The track shows only under the pointer or a drag, fading in with
      // the thumb's growth — whether or not the thumb is pinned.
      ..trackColor = track
          ? _fadeIn(_resolve<Color>((d) => d.trackColor, active), t)
          : const Color(0x00000000)
      ..trackBorderColor = track
          ? _fadeIn(_resolve<Color>((d) => d.trackBorderColor, active), t)
          : const Color(0x00000000)
      ..radius = radius
      ..trackRadius = radius
      ..textDirection = Directionality.of(context)
      ..crossAxisMargin =
          _theme.crossAxisMargin ?? _fallback.crossAxisMargin ?? 2
      ..mainAxisMargin = _theme.mainAxisMargin ?? 0
      ..padding = MediaQuery.paddingOf(context)
      ..scrollbarOrientation = widget.scrollbarOrientation
      ..ignorePointer = !enableGestures;
  }

  static Color _fadeIn(Color color, double t) =>
      color.withValues(alpha: color.a * t);

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    final over = isPointerOverScrollbar(
      event.position,
      event.kind,
      forHover: true,
    );
    if (over == _hovered) return;
    _hovered = over;
    _settle();
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    _hovered = false;
    _settle();
  }

  @override
  void handleThumbPressStart(Offset localPosition) {
    super.handleThumbPressStart(localPosition);
    _dragging = true;
    _settle();
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    super.handleThumbPressEnd(localPosition, velocity);
    _dragging = false;
    _settle();
  }

  void _settle() {
    if (_hovered || _dragging) {
      _active.forward();
    } else {
      _active.reverse();
    }
    updateScrollbarPainter();
  }

  @override
  void dispose() {
    _active.dispose();
    super.dispose();
  }
}
