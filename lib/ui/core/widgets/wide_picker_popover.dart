import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The narrowest a picker's options popover is drawn, whatever its field's
/// width — room for a "+ Create «name»" row and a product name in the
/// line-item table's Item column (invoiceninja/app#215).
const double kPickerPopoverMinWidth = 280;

/// The widest a picker's options popover is drawn, however wide its field.
const double kPickerPopoverMaxWidth = 360;

/// The gap a widened popover keeps from the far edge of the overlay.
const double kPickerPopoverEdgeMargin = 8;

/// How wide to draw a popover for a field [fieldWidth] wide, with [room] from
/// the field's leading edge to the overlay's far edge (less the margin).
///
/// Never narrower than the popover was before it could widen — the field's
/// own width, capped at [maxWidth] — so a field already running off the
/// screen (a scrolled table) keeps the popover it had.
@visibleForTesting
double pickerPopoverWidth({
  required double fieldWidth,
  required double room,
  double minWidth = kPickerPopoverMinWidth,
  double maxWidth = kPickerPopoverMaxWidth,
}) {
  final floor = math.min(fieldWidth, maxWidth);
  final wanted = fieldWidth.clamp(minWidth, maxWidth);
  return math.max(floor, math.min(wanted, room));
}

/// Wraps what a `RawAutocomplete.optionsViewBuilder` returns so the popover
/// can be wider than its field.
///
/// **Why it takes a second overlay.** `RawAutocomplete` lays the options view
/// out in `ConstrainedBox(tight: field width × available height) → Align`
/// (`widgets/autocomplete.dart`, `_buildOptionsView`), so nothing returned
/// from the builder can be wider than the field. Painting past that box is
/// easy; *tapping* past it is not — `RenderBox.hitTest` checks its own size
/// before its children, so the SDK's box drops every pointer outside the
/// field's width, and the right-hand half of a widened row would be dead.
/// So this fills the SDK's box with an empty placeholder (it paints nothing
/// and hit-tests nothing, so a tap below a short list still dismisses), reads
/// that box's geometry through its own `OverlayPortal`, and draws [child] in
/// that portal at the width [pickerPopoverWidth] picks.
///
/// What that costs, and how it is paid back:
///
///  - **The tap-region group.** The SDK wraps its options view in
///    `TextFieldTapRegion`, but the portal's child is no longer under that
///    render object, so this wraps [child] in its own — without it a tap on
///    an option would count as outside and `dismissPickerOnTapOutside` would
///    close the list under the finger. Focus exclusion, the highlight
///    notifier and `BackDismissiblePickerOverlay` are all element-tree
///    lookups, so they still reach [child] unchanged.
///  - **Which way it opened.** `OptionsViewOpenDirection.mostSpace` is decided
///    inside the SDK. Its box always reaches the overlay's bottom edge when it
///    opens down and the top edge when it opens up, so whichever edge the
///    placeholder sits on says which; [child] is then pinned to that box's top
///    or bottom, as the SDK's own `Align` would.
///  - **The far edge.** The width is capped at the room from the field's
///    leading edge to the overlay's far edge, less [edgeMargin] — the right
///    edge in LTR, the left in RTL, where the popover grows leftward from the
///    field's right edge — so a phone never overflows.
///
/// **Still no `Align` of our own** (docs/pickers.md): the placeholder fills
/// the SDK's box on purpose, because it is the box's geometry that is read;
/// [child] itself is positioned by a `CustomSingleChildLayout`, never by
/// filling anything.
///
/// The SDK applies the field's whole paint transform to its popover; this
/// keeps only the translation. Nothing in the app scales or rotates a picker.
class WidePickerPopover extends StatefulWidget {
  const WidePickerPopover({
    super.key,
    required this.child,
    this.minWidth = kPickerPopoverMinWidth,
    this.maxWidth = kPickerPopoverMaxWidth,
    this.edgeMargin = kPickerPopoverEdgeMargin,
  });

  /// The popover. It is laid out at exactly the chosen width, and no taller
  /// than the SDK's box.
  final Widget child;

  final double minWidth;
  final double maxWidth;
  final double edgeMargin;

  @override
  State<WidePickerPopover> createState() => _WidePickerPopoverState();
}

class _WidePickerPopoverState extends State<WidePickerPopover> {
  // Shown before it mounts: this subtree exists only while the SDK's options
  // view does, so mounted == open, and showing now (after the SDK's own
  // `show`) puts this portal above the SDK's in z-order.
  final _portal = OverlayPortalController()..show();

  @override
  Widget build(BuildContext context) {
    // Back is the caller's: every host passes a `BackDismissiblePickerOverlay`
    // as [child], and this portal lives exactly as long as the SDK's own.
    // lint: allow-no-overlay-back-dismiss re-hosts a RawAutocomplete popover
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: _buildPopover,
      child: const SizedBox.expand(),
    );
  }

  Widget _buildPopover(BuildContext context, OverlayChildLayoutInfo info) {
    if (info.childPaintTransform.determinant() == 0.0) {
      return const SizedBox.shrink();
    }
    final box = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    // The same visible rect the SDK sized its box against.
    final overlayRect = MediaQuery.paddingOf(context).deflateRect(
      MediaQuery.viewInsetsOf(
        context,
      ).deflateRect(Offset.zero & info.overlaySize),
    );
    final opensUp =
        (box.top - overlayRect.top).abs() <
        (box.bottom - overlayRect.bottom).abs();
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final room =
        (rtl ? box.right - overlayRect.left : overlayRect.right - box.left) -
        widget.edgeMargin;
    final width = pickerPopoverWidth(
      fieldWidth: box.width,
      room: room,
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
    );
    return CustomSingleChildLayout(
      delegate: _PopoverLayout(
        box: box,
        width: width,
        opensUp: opensUp,
        rtl: rtl,
      ),
      child: TextFieldTapRegion(child: widget.child),
    );
  }
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout({
    required this.box,
    required this.width,
    required this.opensUp,
    required this.rtl,
  });

  /// The SDK's options box, in overlay coordinates.
  final Rect box;
  final double width;
  final bool opensUp;
  final bool rtl;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(width: width).copyWith(maxHeight: box.height);

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    rtl ? box.right - childSize.width : box.left,
    opensUp ? box.bottom - childSize.height : box.top,
  );

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) =>
      oldDelegate.box != box ||
      oldDelegate.width != width ||
      oldDelegate.opensUp != opensUp ||
      oldDelegate.rtl != rtl;
}
