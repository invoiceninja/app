import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';

/// A tappable row inside a settings card that leads to another settings
/// page: a tinted icon square, a title over a one-line status, an optional
/// count, and a chevron. Payment Settings' setup card (Payment Gateways,
/// Payment Types) is the first user.
///
/// Borrowed from the settings home's `_SettingsHomeRow`, made to stand out
/// inside a card: the hover / focus fill is an inset rounded tile
/// (`InRadii.r2`, `surfaceAlt`, never a pill), painted on a local
/// transparent `Material` (CLAUDE.md bans `Ink`).
///
/// [warning] turns the icon square amber (`warningSoft` / `warning`) — the
/// row then IS the page's warning, e.g. "no gateway connected".
///
/// [status] null with [statusPending] true draws a blank status line of the
/// same height, so a row whose data has not answered yet does not jump when
/// it does (and never flashes a wrong state).
///
/// See `docs/settings-screens.md` § Payment Settings opens with a setup card
/// of two navigation rows.
class SettingsNavRow extends StatefulWidget {
  const SettingsNavRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.status,
    this.statusPending = false,
    this.count,
    this.warning = false,
  });

  final IconData icon;
  final String title;
  final String? status;
  final bool statusPending;
  final int? count;
  final bool warning;
  final VoidCallback onTap;

  /// The row's floor. A `minHeight`, never a fixed height, so a large text
  /// scale grows the row instead of clipping it.
  static const double minHeight = 56;

  @override
  State<SettingsNavRow> createState() => _SettingsNavRowState();
}

class _SettingsNavRowState extends State<SettingsNavRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(InRadii.r2),
    );
    final statusStyle = theme.textTheme.bodySmall?.copyWith(color: tokens.ink2);
    final status = widget.status;
    final count = widget.count;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          type: MaterialType.transparency,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            customBorder: shape,
            hoverColor: tokens.surfaceAlt,
            focusColor: tokens.surfaceAlt,
            onHover: (v) => setState(() => _hovered = v),
            onFocusChange: (v) => setState(() => _focused = v),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: SettingsNavRow.minHeight,
              ),
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: InSpacing.md(context),
                  vertical: InSpacing.sm,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: widget.warning
                            ? tokens.warningSoft
                            : tokens.accentSoft,
                        borderRadius: BorderRadius.circular(InRadii.r2),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        widget.icon,
                        size: 20,
                        color: widget.warning
                            ? tokens.warning
                            : tokens.accentInk,
                      ),
                    ),
                    SizedBox(width: InSpacing.md(context)),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: tokens.ink,
                            ),
                          ),
                          if (status != null)
                            Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: statusStyle,
                            )
                          else if (widget.statusPending)
                            // Same height as a status line, read as nothing.
                            ExcludeSemantics(
                              child: Text(' ', maxLines: 1, style: statusStyle),
                            ),
                        ],
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: InSpacing.sm),
                      LtrText(
                        '$count',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.ink3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    const SizedBox(width: InSpacing.xs),
                    // `chevron_right` matches the text direction, so it
                    // points outward in RTL too.
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: _hovered || _focused ? tokens.ink2 : tokens.ink3,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
