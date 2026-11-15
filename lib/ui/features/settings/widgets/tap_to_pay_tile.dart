import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_icon.dart';

/// Where Tap to Pay on iPhone stands on this phone, for Device Settings →
/// Card readers (App Review 3.6, 4.3).
/// `CardReaderSection` derives it from `TerminalController` on an iPhone
/// that can take Tap to Pay on iPhone.
enum TapToPayTileState {
  /// Asking Apple and the server.
  checking,

  /// Not linked on this account, or not yet connected: Turn on.
  notSetUp,

  /// The reader is getting ready (a warm-up, or setup): its progress.
  preparing,

  /// Ready: How to use.
  ready,

  /// Not an admin, and the account isn't linked (3.8.1).
  askAdmin,

  /// iOS older than Apple accepts (1.4).
  updateIos,
}

/// The Tap to Pay on iPhone row of Device Settings → Card readers: Apple's
/// symbol and name, what stands, and the one thing to do about it.
class TapToPayTile extends StatelessWidget {
  const TapToPayTile({
    super.key,
    required this.state,
    this.progress,
    this.onTurnOn,
    this.onHowToUse,
  });

  final TapToPayTileState state;

  /// 0–1 while [TapToPayTileState.preparing] can say.
  final double? progress;
  final VoidCallback? onTurnOn;
  final VoidCallback? onHowToUse;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    String sentence(String key) =>
        context.tr(key, {'name': tapToPayNameFor(context, key)});
    final (String subtitle, Color? tone) = switch (state) {
      TapToPayTileState.checking => (
        context.tr('terminal_tile_checking'),
        null,
      ),
      TapToPayTileState.notSetUp => (
        context.tr('terminal_tile_not_set_up'),
        null,
      ),
      TapToPayTileState.preparing => (
        sentence('terminal_tap_to_pay_initializing'),
        null,
      ),
      // The tick carries the green; the word stays legible (green text is
      // 4.3–4.5:1 on the card, short of AA).
      TapToPayTileState.ready => (
        context.tr('terminal_tile_ready'),
        tokens.ink2,
      ),
      TapToPayTileState.askAdmin => (
        sentence('terminal_error_terms_not_accepted'),
        null,
      ),
      TapToPayTileState.updateIos => (
        sentence('terminal_update_ios'),
        tokens.warning,
      ),
    };
    final Widget? trailing = switch (state) {
      TapToPayTileState.checking => const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      // Tonal: the app theme paints every FilledButton in the accent, so the
      // soft colours are set here.
      TapToPayTileState.notSetUp when onTurnOn != null => FilledButton.tonal(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 40),
          backgroundColor: tokens.accentSoft,
          foregroundColor: tokens.accentInk,
        ),
        onPressed: onTurnOn,
        child: Text(context.tr('terminal_tile_turn_on')),
      ),
      TapToPayTileState.ready => TextButton(
        onPressed: onHowToUse,
        child: Text(context.tr('terminal_how_to_tap_short')),
      ),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: InSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: TapToPayIcon(size: 28, color: tokens.ink2),
              ),
              SizedBox(width: InSpacing.md(context)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('tap_to_pay_on_iphone'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tokens.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (state == TapToPayTileState.ready) ...[
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: tokens.paid,
                          ),
                          const SizedBox(width: InSpacing.xs),
                        ],
                        Expanded(
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: tone ?? tokens.ink3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: InSpacing.sm),
                trailing,
              ],
            ],
          ),
          if (state == TapToPayTileState.preparing) ...[
            const SizedBox(height: InSpacing.sm),
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: 28 + InSpacing.md(context),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(InRadii.r1),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: tokens.border,
                        color: tokens.accent,
                      ),
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(width: InSpacing.sm),
                    LtrText(
                      '${(progress! * 100).round()}%',
                      style: TextStyle(fontSize: 12, color: tokens.ink3),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
