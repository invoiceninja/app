import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/mobile_app_promo_controller.dart';
import 'package:admin/app/services.dart';
import 'package:admin/domain/desktop_app_promo.dart';
import 'package:admin/domain/mobile_app_promo.dart';
import 'package:admin/domain/web_app_banner.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/copy_entity_link.dart';
import 'package:admin/ui/core/fold_geometry.dart';
import 'package:admin/ui/core/widgets/copy_value_row.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';
import 'package:admin/ui/core/widgets/feature_row.dart';
import 'package:admin/ui/features/mobile_promo/mobile_app_promo_dialog.dart';

/// Opens whichever promo this build runs (`currentAppPromoKind`): the desktop
/// app on a phone, the phone app everywhere else. The automatic opener and
/// every permanent entry go through here.
Future<MobilePromoResult?> showAppPromoDialog(
  BuildContext context, {
  bool isManual = false,
}) => currentDesktopPromoTargets().isNotEmpty
    ? showDesktopAppPromoDialog(context, isManual: isManual)
    : showMobileAppPromoDialog(context, isManual: isManual);

/// Opens the "get the desktop app" promo (docs/desktop-app-promo.md) for this
/// build and the signed-in account. [isManual] is an open the user asked
/// for — About, Device Settings, Integrations — which never moves the
/// automatic schedule.
Future<MobilePromoResult?> showDesktopAppPromoDialog(
  BuildContext context, {
  bool isManual = false,
}) {
  final session = context.read<Services>().auth.session.value;
  final controller = context.read<MobileAppPromoController?>();
  return showDialog<MobilePromoResult>(
    context: context,
    anchorPoint: foldAnchorPoint(context),
    // As the phone-app promo: a stray tap beside the card isn't an answer.
    barrierDismissible: false,
    builder: (_) => DesktopAppPromoDialog(
      targets: currentDesktopPromoTargets(),
      account: MobilePromoAccount.fromSession(session),
      controller: controller,
      isManual: isManual,
    ),
  );
}

/// The desktop-app promo card: a phone can't install a desktop app, so it
/// hands the download link over — the share sheet (AirDrop, Mail, a note to
/// self) or the clipboard — beside a short pitch.
///
/// Every store rule is decided before it is built: [targets] is the Mac only
/// on Apple's builds (guideline 2.3.10, `desktopPromoTargets`), and this
/// widget names no computer it wasn't handed — the tests pump it with each
/// platform's targets directly.
class DesktopAppPromoDialog extends StatefulWidget {
  const DesktopAppPromoDialog({
    required this.targets,
    required this.account,
    this.controller,
    this.isManual = false,
    this.urlOf = nativeAppUrl,
    super.key,
  }) : assert(targets.length > 0);

  final List<DesktopPromoTarget> targets;

  /// Only the server half is read: a self-hosted address to sign in to, and
  /// whether it is on a private network.
  final MobilePromoAccount account;

  /// Told about engagement and "Don't show again" as they happen. Null in a
  /// harness without one.
  final MobileAppPromoController? controller;
  final bool isManual;

  /// Each target's download page — [nativeAppUrl], or a test's.
  final DesktopAppUrlOf urlOf;

  @override
  State<DesktopAppPromoDialog> createState() => _DesktopAppPromoDialogState();
}

class _DesktopAppPromoDialogState extends State<DesktopAppPromoDialog> {
  /// As the phone-app promo: a tap or key landing in the first half-second
  /// was aimed at what was under the card, and must not spend a reminder.
  static const Duration _armDelay = Duration(milliseconds: 500);

  late DesktopPromoTarget _target = widget.targets.first;
  bool _armed = false;
  bool _engaged = false;
  Timer? _armTimer;

  @override
  void initState() {
    super.initState();
    _armTimer = Timer(_armDelay, () => _armed = true);
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    super.dispose();
  }

  String get _url => desktopPromoUrl(_target, urlOf: widget.urlOf);

  bool get _isLastReminder => widget.controller?.isLastReminder ?? false;

  VoidCallback _guard(VoidCallback action) => () {
    if (_armed) action();
  };

  void _engage() {
    if (!_engaged) setState(() => _engaged = true);
    unawaited(widget.controller?.markEngaged());
  }

  void _pop(MobilePromoResult result) => Navigator.of(context).pop(result);

  void _dismiss() =>
      _pop(_engaged ? MobilePromoResult.engaged : MobilePromoResult.snoozed);

  void _dontShowAgain() {
    unawaited(widget.controller?.finish());
    _pop(MobilePromoResult.dismissed);
  }

  /// The share sheet — on iPad anchored to the button ([buttonContext]) —
  /// or, where none can be raised, the clipboard (`shareOrCopyLink`).
  Future<void> _share(BuildContext buttonContext) async {
    _engage();
    await shareOrCopyLink(
      buttonContext,
      _url,
      label: context.tr('desktop_app_promo_link_label'),
    );
  }

  Future<void> _copy() async {
    _engage();
    await copyToClipboard(
      context,
      _url,
      label: context.tr('desktop_app_promo_link_label'),
    );
  }

  // The room the route gives the card, never `MediaQuery`: on a foldable
  // held half-open the dialog opens in one half of the fold
  // (`DisplayFeatureSubScreen`), while `MediaQuery.size` is still the whole
  // window, which drew the 720-wide tablet layout into a ~420 half
  // (docs/foldables.md). Measured on every build, so a fold or an unfold
  // under the open card re-lays it out.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _card(context, constraints.biggest),
  );

  Widget _card(BuildContext context, Size size) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    // A tablet: the pitch beside the link, as the phone-app promo lays out.
    final wide = size.width >= 800 && size.height >= 560 && scale < 1.3;
    // A phone, measured in lines of text rather than points: an iPhone SE,
    // or a big phone at a large text size. Below 700 the laptop glyph and
    // some of the scrim give way, so the pitch is on screen with the link;
    // below 560 (a 4-inch phone) the features keep their titles only.
    final room = size.height / scale;
    final compact = !wide && room < 700;
    final titlesOnly = !wide && room < 560;
    final tokens = context.inTheme;
    final close = PositionedDirectional(
      top: InSpacing.xs,
      end: InSpacing.xs,
      child: IconButton(
        visualDensity: VisualDensity.standard,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(InSizes.touchTarget),
        ),
        tooltip: context.tr('close'),
        icon: Icon(Icons.close, color: tokens.ink3),
        onPressed: _guard(_dismiss),
      ),
    );
    final Widget body;
    if (wide) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Stack(
                children: [
                  PositionedDirectional(
                    top: 0,
                    bottom: 0,
                    end: 0,
                    width: 320,
                    child: ColoredBox(color: tokens.accentSoft),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 400,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            InSpacing.xl,
                            InSpacing.xl,
                            InSpacing.xl,
                            InSpacing.sm,
                          ),
                          child: _pitch(context),
                        ),
                      ),
                      SizedBox(
                        width: 320,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            InSpacing.xl,
                            InSpacing.xxl + InSpacing.sm,
                            InSpacing.xl,
                            InSpacing.xl,
                          ),
                          child: _sendIt(context, showIcon: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: tokens.border),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: InSpacing.xl,
              vertical: InSpacing.md(context),
            ),
            child: _footer(context),
          ),
        ],
      );
    } else {
      // A phone: what to do comes before why, so Share is on screen when
      // the card opens, and the footer is pinned below the scroll, so the
      // way out is too.
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                InSpacing.xl,
                InSpacing.xl,
                InSpacing.xl,
                InSpacing.md(context),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context),
                  SizedBox(height: InSpacing.lg(context)),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(InSpacing.lg(context)),
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(InRadii.r3),
                    ),
                    child: _sendIt(context, showIcon: !compact),
                  ),
                  SizedBox(height: InSpacing.lg(context)),
                  _features(context, titlesOnly: titlesOnly),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: tokens.border),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: InSpacing.xl,
              vertical: InSpacing.md(context),
            ),
            child: _footer(context),
          ),
        ],
      );
    }
    // Esc on a tablet's keyboard: the route's own handler is off while the
    // barrier isn't dismissible, so the card brings its own.
    return Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            _guard(_dismiss)();
            return null;
          },
        ),
      },
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: EdgeInsets.symmetric(
          horizontal: size.width < 600 ? 16 : 40,
          vertical: compact ? 16 : 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 720 : 480),
          child: Stack(children: [body, close]),
        ),
      ),
    );
  }

  /// The title, subtitle and features: the wide layout's left column.
  Widget _pitch(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      _header(context),
      const SizedBox(height: InSpacing.xl),
      _features(context),
    ],
  );

  /// The two reasons a phone user wants the desktop app too. Not "works
  /// offline" or "the same data": the phone app does both, and the subtitle
  /// already says so.
  Widget _features(BuildContext context, {bool titlesOnly = false}) {
    const features = <(IconData, String, String)>[
      (
        Icons.space_dashboard_outlined,
        'desktop_app_promo_screen_title',
        'desktop_app_promo_screen_body',
      ),
      (
        Icons.keyboard_outlined,
        'desktop_app_promo_keyboard_title',
        'desktop_app_promo_keyboard_body',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (icon, title, body) in features)
          FeatureRow(
            icon: icon,
            title: context.tr(title),
            body: titlesOnly ? '' : context.tr(body),
          ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final tokens = context.inTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          // Clear of the ✕, which sits over the title's line.
          padding: const EdgeInsetsDirectional.only(end: InSpacing.xl),
          child: Semantics(
            header: true,
            headingLevel: 1,
            namesRoute: true,
            child: Text(
              context.tr('desktop_app_promo_title'),
              style: TextStyle(
                fontSize: 22,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: tokens.ink,
              ),
            ),
          ),
        ),
        const SizedBox(height: InSpacing.xs + 2),
        Text(
          context.tr('desktop_app_promo_subtitle'),
          style: TextStyle(fontSize: 14, height: 1.4, color: tokens.ink2),
        ),
      ],
    );
  }

  Widget _sendIt(BuildContext context, {required bool showIcon}) {
    final tokens = context.inTheme;
    final a = widget.account;
    final small = TextStyle(fontSize: 12, height: 1.4, color: tokens.ink3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.targets.length > 1) ...[
          // Text only: the platforms' own marks are their owners' artwork,
          // and a generic glyph per segment would tell them apart by nothing.
          // Scaled down rather than wrapped at a large text size: a segment
          // broke "Windows" across two lines.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SegmentedButton<DesktopPromoTarget>(
              showSelectedIcon: false,
              segments: [
                for (final t in widget.targets)
                  ButtonSegment(
                    value: t,
                    label: Text(t.displayName, maxLines: 1, softWrap: false),
                  ),
              ],
              selected: {_target},
              onSelectionChanged: (s) => setState(() => _target = s.first),
            ),
          ),
          SizedBox(height: InSpacing.lg(context)),
        ],
        if (showIcon) ...[
          Icon(Icons.laptop_outlined, size: 40, color: tokens.accentInk),
          const SizedBox(height: InSpacing.sm),
        ],
        Text(
          context.tr('desktop_app_promo_send_hint'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: tokens.ink,
          ),
        ),
        SizedBox(height: InSpacing.md(context)),
        // Side by side where they fit, which keeps the pitch on an iPhone
        // SE's first screen; stacked, Share on top, where they don't.
        OverflowBar(
          alignment: MainAxisAlignment.center,
          spacing: InSpacing.sm,
          overflowAlignment: OverflowBarAlignment.center,
          children: [
            Builder(
              builder: (buttonContext) => FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                onPressed: _guard(() => unawaited(_share(buttonContext))),
                icon: Icon(Icons.adaptive.share),
                label: Text(context.tr('desktop_app_promo_share')),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
              onPressed: _guard(() => unawaited(_copy())),
              icon: const Icon(Icons.link, size: 18),
              // Its own key, in the Share button's case: the shared
              // `copy_link` is title case, and untranslated in a dozen
              // locales.
              label: Text(context.tr('desktop_app_promo_copy')),
            ),
          ],
        ),
        SizedBox(height: InSpacing.md(context)),
        // What changes when another computer is picked, so a screen
        // reader hears it.
        Semantics(
          liveRegion: true,
          child: Text(
            context.tr(desktopPromoStepKey(_target, _url)),
            textAlign: TextAlign.center,
            style: small,
          ),
        ),
        if (a.serverUrl case final url?) ...[
          SizedBox(height: InSpacing.md(context)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              context.tr('desktop_app_promo_server_url'),
              style: TextStyle(fontSize: 13, height: 1.4, color: tokens.ink2),
            ),
          ),
          CopyValueRow(value: url),
          if (a.privateNetwork) ...[
            const SizedBox(height: InSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                context.tr('desktop_app_promo_same_network'),
                style: small,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _footer(BuildContext context) {
    final tokens = context.inTheme;
    final controller = widget.controller;
    // As the phone-app promo: Remind me later only on an automatic open with
    // one still to come; Don't show again only where it says more than Close.
    // On a requested open that is while automatic opens remain to be ended
    // (`showsSidebarCard` is exactly that, though this side has no card).
    final snoozes = !widget.isManual && !_isLastReminder && !_engaged;
    final offersDontShow =
        controller != null &&
        !_engaged &&
        (widget.isManual ? controller.showsSidebarCard : !_isLastReminder);
    final dismiss = OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
      autofocus: true,
      onPressed: _guard(_dismiss),
      child: Text(
        context.tr(snoozes ? 'mobile_app_promo_remind_later' : 'close'),
        textAlign: TextAlign.center,
      ),
    );
    // Side by side while both fit; stacked, the way out on top, when they
    // don't (a long locale, a large text size). An ellipsis made both
    // unreadable ("Don't sho…", "Remind m…").
    return OverflowBar(
      alignment: offersDontShow
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.end,
      spacing: InSpacing.md(context),
      overflowSpacing: InSpacing.xs,
      overflowAlignment: OverflowBarAlignment.end,
      overflowDirection: VerticalDirection.up,
      children: [
        if (offersDontShow)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: tokens.ink3),
            onPressed: _guard(_dontShowAgain),
            child: Text(
              context.tr('mobile_app_promo_dont_show_again'),
              textAlign: TextAlign.center,
            ),
          ),
        dismiss,
      ],
    );
  }
}
