import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_icon.dart';
import 'package:admin/ui/features/terminal/widgets/collect_stage_layout.dart';

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
    final statusTone = switch (state) {
      TapToPayTileState.ready => StageTone.success,
      TapToPayTileState.preparing ||
      TapToPayTileState.checking => StageTone.accent,
      TapToPayTileState.updateIos => StageTone.warning,
      _ => StageTone.neutral,
    };
    final ready = state == TapToPayTileState.ready;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: InSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Apple's symbol in the stages' tile, tinted like any icon and
          // otherwise as Apple draws it.
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ready ? tokens.paidSoft : tokens.accentSoft,
              borderRadius: BorderRadius.circular(InRadii.r2),
            ),
            child: TapToPayIcon(
              size: 24,
              color: ready ? tokens.paid : tokens.accentInk,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: StatusDot(tone: statusTone),
                    ),
                    const SizedBox(width: 6),
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
                if (state == TapToPayTileState.preparing) ...[
                  const SizedBox(height: InSpacing.sm),
                  StageProgress(value: progress),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: InSpacing.sm),
            trailing,
          ],
        ],
      ),
    );
  }
}
