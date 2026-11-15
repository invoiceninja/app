import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/app_selection_area.dart';
import 'package:admin/ui/core/widgets/notify.dart';

/// Writes [value] to the system clipboard, fires a light haptic on touch
/// platforms, and surfaces the standard `copied_to_clipboard` toast.
///
/// Shared by [CopyableValue], `CellCopyHover`, and any bespoke copy button so
/// every copy in the app gives identical feedback. The toast value is
/// ellipsized so a long URL / address doesn't blow out the snackbar.
///
/// [label] names the thing in the toast instead of the payload — pass it when
/// [value] is a blob (a log dump, a design JSON, a cURL command) that reads as
/// noise inside "Copied … to the clipboard". Every caller should still route
/// through here rather than reaching for a placeholder-free key: the bundled
/// `copied_to_clipboard` string is translated in every locale by Transifex,
/// whereas an app-local replacement would carry only the app's own machine
/// translations (`_app_pending_<locale>.json`).
///
/// [messenger] is for a caller whose context may be popped before the toast
/// lands (see `outbox_screen`); it's threaded straight to [Notify.success].
Future<void> copyToClipboard(
  BuildContext context,
  String value, {
  String? label,
  ScaffoldMessengerState? messenger,
}) async {
  final message = context.tr('copied_to_clipboard', {
    'value': ellipsizeForToast(label ?? value),
  });
  await Clipboard.setData(ClipboardData(text: value));
  // Light confirmation buzz on touch — distinguishes an intentional copy from
  // a mis-tap. No-op / skipped off mobile.
  if (Env.isMobile) {
    await HapticFeedback.selectionClick();
  }
  if (!context.mounted) return;
  Notify.success(context, message, messenger: messenger);
}

/// Trims an over-long value so the confirmation toast stays a single line.
String ellipsizeForToast(String s, {int max = 40}) {
  if (s.length <= max) return s;
  return '${s.substring(0, max)}…';
}

/// The small copy affordance: a bordered chip with a copy glyph that writes
/// [value] to the clipboard on click.
///
/// Keyboard-focusable by default (Tab + Enter copies) — pass
/// [canRequestFocus] `false` for dense surfaces like table cells where Tab
/// should walk rows, not stop on every cell.
class CopyIconButton extends StatelessWidget {
  const CopyIconButton({
    super.key,
    required this.value,
    this.canRequestFocus = true,
  });

  final String value;
  final bool canRequestFocus;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final radius = BorderRadius.circular(InRadii.r1);
    return Tooltip(
      message: context.tr('copy'),
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: tokens.border),
        ),
        child: InkWell(
          onTap: () => copyToClipboard(context, value),
          borderRadius: radius,
          canRequestFocus: canRequestFocus,
          child: Semantics(
            button: true,
            label: context.tr('copy'),
            child: SizedBox(
              width: 22,
              height: 22,
              child: Icon(Icons.content_copy, size: 14, color: tokens.ink3),
            ),
          ),
        ),
      ),
    );
  }
}

/// Adds a copy affordance to a read-only value display.
///
/// - **Desktop / web (mouse):** a [CopyIconButton] fades in on hover. With
///   [fillWidth] (the default) the icon is pinned to the trailing edge so it
///   forms a consistent column down a stack of rows and never overlaps a
///   wrapped value, while the value text stays left next to its label. Keyboard
///   users can Tab to the button; with [floatIcon] they Tab to the value and
///   press Enter. There is deliberately **no** tap-to-copy on
///   the value here — a click must still place a cursor / start a selection.
/// - **Native mobile (touch):** no icon; tapping the value copies it (or
///   long-press, for values whose tap is already taken — e.g. a launchable
///   link). A light haptic fires on copy. Inside an [AppSelectionArea] a
///   long-press on any other value selects a word instead, and a tap while a
///   selection shows dismisses it without copying.
///
/// Renders [child] unchanged (no affordance) when [value] is empty.
///
/// The platform split is intentional: tap-to-copy is limited to touch
/// (`Env.isTouchPrimary`), so a desktop click keeps placing a selection
/// instead of copying, and every other platform gets the hover icon.
class CopyableValue extends StatefulWidget {
  const CopyableValue({
    super.key,
    required this.value,
    required this.child,
    this.enableTapToCopy = true,
    this.enableLongPressToCopy = false,
    this.fillWidth = true,
    this.floatIcon = false,
    this.iconAlignment = CrossAxisAlignment.start,
  });

  /// The exact string written to the clipboard.
  final String value;

  /// The value's display widget (plain `Text`, `LinkText`, monospace amount…).
  final Widget child;

  /// Mobile single-tap copies the value. Turn off when [child] handles its own
  /// tap (e.g. a link that launches a URL).
  final bool enableTapToCopy;

  /// Mobile long-press copies the value. Use for link-bearing values whose tap
  /// is taken, so long-press still yields the underlying string.
  final bool enableLongPressToCopy;

  /// When true (default) the value fills the available width and the hover icon
  /// sits at the trailing edge — the right look inside a labeled detail row.
  /// Pass false for an inline value (e.g. the header `#number`) so the icon
  /// hugs the value instead of stretching across an unbounded row.
  final bool fillWidth;

  /// Pointer only: draw the hover icon in an overlay just past the value's
  /// trailing edge instead of reserving a slot for it in the layout.
  ///
  /// For an inline value with something after it on its line — a document
  /// number followed by its status pills, a client name mid-way through a
  /// dotted subtitle. A reserved slot there is 30 px of nothing between the
  /// value and its neighbour at rest (the "stray gap" `DetailSubtitle` warns
  /// about); floating, the layout is exactly [child]'s and the icon covers
  /// the neighbour's leading edge only while the value is hovered. Leave it
  /// off where nothing follows the value: a reserved slot can never be
  /// clipped by the edge of the pane, and this one can. Wins over
  /// [fillWidth]. Touch is unaffected.
  ///
  /// The icon is in the tree only while it shows, so the value is itself a
  /// tab stop: focused from the keyboard it shows the icon, and Enter or
  /// Space copies. It also carries a semantic Copy action.
  ///
  /// Never float beside a control the pointer travels to next — the chip
  /// lands on top of it (the party name before a call button; see
  /// `BillingDocPartyLine`, which keeps a slot after the button instead).
  final bool floatIcon;

  /// Pointer only, reserved-slot layout: where the icon sits against the
  /// value. `start` (the default) lines it up with a label row's first line;
  /// pass `center` beside a value taller than the icon, such as a headline.
  final CrossAxisAlignment iconAlignment;

  @override
  State<CopyableValue> createState() => _CopyableValueState();
}

class _CopyableValueState extends State<CopyableValue> {
  bool _hovering = false;

  // Floating icon ([CopyableValue.floatIcon]) only.
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  Timer? _hideTimer;

  /// Long enough to cross the gap between the value and the icon, short
  /// enough that the icon is gone before the pointer reaches the next thing.
  static const Duration _hideDelay = Duration(milliseconds: 150);

  /// How many of the value and the icon the pointer is over (it crosses a
  /// gap between them), and whether the value holds keyboard focus.
  int _floatHovers = 0;
  bool _floatFocused = false;

  void _syncFloating() {
    _hideTimer?.cancel();
    if (_floatHovers > 0 || _floatFocused) {
      if (!_portal.isShowing) _portal.show();
      return;
    }
    _hideTimer = Timer(_hideDelay, () {
      if (mounted && _portal.isShowing) _portal.hide();
    });
  }

  void _floatHover(bool entered) {
    _floatHovers = (_floatHovers + (entered ? 1 : -1)).clamp(0, 2);
    _syncFloating();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  Widget _buildFloating(BuildContext context, String value) {
    return CompositedTransformTarget(
      link: _link,
      // lint: allow-no-overlay-back-dismiss pointer-only hover chip — this
      // branch is never built on touch, so there is no system back to answer.
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (overlayContext) {
          final direction = Directionality.of(context);
          return Align(
            alignment: AlignmentDirectional.topStart,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: AlignmentDirectional.centerEnd.resolve(direction),
              followerAnchor: AlignmentDirectional.centerStart.resolve(
                direction,
              ),
              offset: Offset(direction == TextDirection.rtl ? -4 : 4, 0),
              child: MouseRegion(
                onEnter: (_) => _floatHover(true),
                onExit: (_) => _floatHover(false),
                // Not a tab stop of its own: it exists only while the value
                // is hovered or focused, and focus moving onto it would take
                // it away. The keyboard copies from the value (below).
                child: CopyIconButton(value: value, canRequestFocus: false),
              ),
            ),
          );
        },
        // The icon is not in the tree until it shows, so the value itself is
        // the keyboard's and the screen reader's way in: a tab stop that
        // shows the icon while focused and copies on Enter / Space, and a
        // semantic Copy action.
        child: FocusableActionDetector(
          mouseCursor: MouseCursor.defer,
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                copyToClipboard(context, value);
                return null;
              },
            ),
          },
          onShowFocusHighlight: (focused) {
            _floatFocused = focused;
            _syncFloating();
          },
          child: Semantics(
            onCopy: () => copyToClipboard(context, value),
            child: MouseRegion(
              onEnter: (_) => _floatHover(true),
              onExit: (_) => _floatHover(false),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    if (value.isEmpty) return widget.child;

    // Touch: tap / long-press the value to copy; no hover icon.
    //
    // `isTouchPrimary`, not `isMobile` — the latter is native-only (it checks
    // `kIsWeb` first), so a phone *browser* fell through to the desktop
    // branch, where the copy icon is revealed by `MouseRegion.onEnter` and
    // therefore never appeared. Copy was unreachable on mobile web. The
    // haptic below correctly stays on `isMobile`: that one needs a real
    // platform channel. (Desktop web keeps the hover path, which preserves
    // text selection.)
    if (Env.isTouchPrimary) {
      // Inside an `AppSelectionArea` with a selection showing, a tap is spent
      // dismissing it — as a tap on text does natively — rather than also
      // copying the whole value over the user's own selection. A long-press
      // to copy is deliberate, so it always copies.
      final onTap = widget.enableTapToCopy
          ? () {
              if (AppSelectionArea.dismissSelection(context)) return;
              copyToClipboard(context, value);
            }
          : null;
      final onLongPress = widget.enableLongPressToCopy
          ? () => copyToClipboard(context, value)
          : null;
      if (onTap == null && onLongPress == null) return widget.child;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: widget.child,
      );
    }

    if (widget.floatIcon) return _buildFloating(context, value);

    // Desktop + web: hover reveals a trailing copy icon. The slot is always in
    // the layout (opacity animates) so the row doesn't shift when it appears.
    return MouseRegion(
      onEnter: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      child: Row(
        mainAxisSize: widget.fillWidth ? MainAxisSize.max : MainAxisSize.min,
        // Top-align the value (and icon) with the label — the host rows
        // (DetailInfoRow, header) are CrossAxisAlignment.start; without this
        // the 22px icon would vertically center the value below its label.
        crossAxisAlignment: widget.iconAlignment,
        children: [
          if (widget.fillWidth)
            Expanded(child: widget.child)
          else
            Flexible(child: widget.child),
          const SizedBox(width: InSpacing.sm),
          IgnorePointer(
            ignoring: !_hovering,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 100),
              opacity: _hovering ? 1.0 : 0.0,
              child: CopyIconButton(value: value),
            ),
          ),
        ],
      ),
    );
  }
}
