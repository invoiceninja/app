import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/domain/sidebar_badge_modes.dart' show SidebarBadgeTone;
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/shell/widgets/search_palette_results.dart';
import 'package:admin/ui/features/shell/widgets/sidebar_badge.dart';

/// The search palette's category bar: All, then every category with hits,
/// each with its count (docs/search-palette.md).
///
/// Drawn in the vocabulary of a list's status strip (`EntityListStatusTabs`)
/// — an underlined label and a `SidebarBadge` count on a scrolling row with
/// position-gated edge fades — so it reads as the same control users already
/// know from every list screen. That widget is not reused directly: it is
/// built around live Drift count streams and badge-mode tabs, where these
/// counts are a plain number known up front and a count can be a floor
/// ("23+") when the server capped its answer.
class SearchPaletteScopeBar extends StatefulWidget {
  const SearchPaletteScopeBar({
    required this.scopes,
    required this.selectedId,
    required this.onSelect,
    this.tapGroup,
    super.key,
  });

  /// `all` first. A scope's id is also its label's localization key.
  final List<PaletteScope> scopes;
  final String selectedId;
  final ValueChanged<String> onSelect;

  /// The search field's `TapRegion` group: a tap on a category is then not a
  /// tap outside the field, so the soft keyboard stays up.
  final Object? tapGroup;

  @override
  State<SearchPaletteScopeBar> createState() => _SearchPaletteScopeBarState();
}

class _SearchPaletteScopeBarState extends State<SearchPaletteScopeBar> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(SearchPaletteScopeBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) _revealSelected();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Tab moves the selection along a bar wider than its pane, so the
  /// selected category is kept in view. Scrolls this bar only — never
  /// `Scrollable.ensureVisible`, which would also scroll the results.
  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final box = _keys[widget.selectedId]?.currentContext?.findRenderObject();
      if (box == null) return;
      _scroll.position.ensureVisible(
        box,
        alignment: 0.5,
        duration: InMotion.of(context)(InMotion.fast),
        curve: InMotion.out,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final bar = Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NotificationListener<ScrollMetricsNotification>(
            // A resize that leaves `pixels` alone reaches no controller
            // listener; without this the fades keep the old width's state.
            onNotification: (_) {
              if (mounted) setState(() {});
              return false;
            },
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final scope in widget.scopes)
                        _ScopeTab(
                          key: _keys.putIfAbsent(scope.id, GlobalKey.new),
                          scope: scope,
                          active: scope.id == widget.selectedId,
                          onTap: () => widget.onSelect(scope.id),
                        ),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _scroll,
                      builder: (context, _) {
                        final p =
                            _scroll.hasClients &&
                                _scroll.position.hasContentDimensions
                            ? _scroll.position
                            : null;
                        final atStart =
                            p == null || p.pixels <= p.minScrollExtent;
                        final atEnd =
                            p == null || p.pixels >= p.maxScrollExtent;
                        return Stack(
                          children: [
                            if (!atStart) _edgeFade(tokens, leading: true),
                            if (!atEnd) _edgeFade(tokens, leading: false),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: tokens.border.withValues(alpha: 0.6)),
        ],
      ),
    );
    final group = widget.tapGroup;
    return group == null ? bar : TapRegion(groupId: group, child: bar);
  }

  /// A gradient hinting at more categories past one edge, shown only while
  /// there are — the same gate as the status strip's.
  Widget _edgeFade(InTheme tokens, {required bool leading}) =>
      PositionedDirectional(
        top: 0,
        bottom: 0,
        start: leading ? 0 : null,
        end: leading ? null : 0,
        child: Container(
          width: 24,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: leading
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              end: leading
                  ? AlignmentDirectional.centerStart
                  : AlignmentDirectional.centerEnd,
              colors: [tokens.surface.withValues(alpha: 0), tokens.surface],
            ),
          ),
        ),
      );
}

class _ScopeTab extends StatelessWidget {
  const _ScopeTab({
    required this.scope,
    required this.active,
    required this.onTap,
    super.key,
  });

  final PaletteScope scope;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final label = context.tr(scope.id);
    final count = scope.atLeast ? '${scope.count}+' : '${scope.count}';
    final colors = SidebarBadge.colorsFor(
      tokens,
      SidebarBadgeTone.neutral,
      active: active,
    );
    final announced = context.tr(
      scope.atLeast
          ? 'search_scope_at_least_announcement'
          : 'search_scope_announcement',
      {'scope': label, 'count': '${scope.count}'},
    );
    return Semantics(
      role: SemanticsRole.tab,
      selected: active,
      label: announced,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        // A tap must not take focus from the field: that would lower the
        // soft keyboard and end typing.
        canRequestFocus: false,
        child: ConstrainedBox(
          // A floor, never a fixed height: a fixed one slices descenders at
          // a large text scale.
          constraints: BoxConstraints(
            minHeight: Env.isTouchPrimary ? InSizes.touchTarget : 0,
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: InSpacing.md(context),
              vertical: InSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? tokens.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? tokens.ink : tokens.ink2,
                    ),
                  ),
                  const SizedBox(width: InSpacing.sm),
                  // `SidebarBadge`'s shape, with room for a floor ("23+"),
                  // drawn left to right so a right-to-left locale never
                  // reads it as "+23".
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.bg,
                      borderRadius: BorderRadius.circular(InRadii.r1),
                      border: Border.all(color: tokens.border),
                    ),
                    child: LtrText(
                      count,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: colors.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
