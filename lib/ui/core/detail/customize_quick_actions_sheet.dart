import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/domain/quick_action_prefs.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/detail/entity_detail_actions_row.dart';
import 'package:admin/ui/core/detail/entity_quick_actions.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';
import 'package:admin/ui/core/fold_geometry.dart';

/// What the editor needs to draw one action: the tile's own icon and short
/// label, and the menu's full label for the row.
@immutable
class QuickActionChoice {
  const QuickActionChoice({
    required this.id,
    required this.icon,
    required this.label,
    required this.shortLabel,
  });

  final String id;
  final IconData icon;
  final String label;
  final String shortLabel;
}

/// Open the quick-action editor for one kind of record: drag to reorder,
/// switch to show or hide.
///
/// The same two hosts as `openCustomizeMenu` — a centred dialog when wide, a
/// scroll-controlled bottom sheet when narrow — for the same reason: the
/// reorderable list needs a scrollable of its own to auto-scroll mid-drag.
/// Changes apply at once; "Reset to defaults" is the way back.
Future<void> openCustomizeQuickActions(
  BuildContext context, {
  required String entityLabel,
  required List<QuickActionChoice> choices,
  required ValueListenable<List<QuickActionPref>> prefs,
  required ValueChanged<List<QuickActionPref>> onChanged,
  required VoidCallback onReset,
  required bool Function(List<QuickActionPref>) isDefault,
}) {
  Widget body(BuildContext _) => ValueListenableBuilder<List<QuickActionPref>>(
    valueListenable: prefs,
    builder: (context, value, _) => CustomizeQuickActionsBody(
      entityLabel: entityLabel,
      choices: choices,
      prefs: value,
      onChanged: onChanged,
      onReset: isDefault(value) ? null : onReset,
    ),
  );
  if (MediaQuery.sizeOf(context).width >= Breakpoints.wide) {
    return showDialog<void>(
      context: context,
      anchorPoint: foldAnchorPoint(context),
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: body(ctx),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: FractionallySizedBox(heightFactor: 0.92, child: body(ctx)),
    ),
  );
}

/// The editor itself, controlled: it draws [prefs] and reports every change.
///
/// [onReset] null means the arrangement is already the default, and the
/// button is not drawn.
class CustomizeQuickActionsBody extends StatefulWidget {
  const CustomizeQuickActionsBody({
    super.key,
    required this.entityLabel,
    required this.choices,
    required this.prefs,
    required this.onChanged,
    required this.onReset,
  });

  final String entityLabel;
  final List<QuickActionChoice> choices;
  final List<QuickActionPref> prefs;
  final ValueChanged<List<QuickActionPref>> onChanged;
  final VoidCallback? onReset;

  @override
  State<CustomizeQuickActionsBody> createState() =>
      _CustomizeQuickActionsBodyState();
}

class _CustomizeQuickActionsBodyState extends State<CustomizeQuickActionsBody> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final byId = {for (final c in widget.choices) c.id: c};
    final prefs = [
      for (final p in widget.prefs)
        if (byId.containsKey(p.id)) p,
    ];
    final shown = [
      for (final p in prefs)
        if (p.visible) byId[p.id]!,
    ];
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: tokens.ink2);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              context.tr('quick_actions'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Text(widget.entityLabel, style: muted),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: context.tr('close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Divider(height: 1, color: tokens.border),
          // The strip as a record will draw it, on the page colour it sits on
          // there. Inert: these are pictures of tiles, not the actions.
          ColoredBox(
            color: tokens.bg,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                InSpacing.lg(context),
                InSpacing.lg(context),
                InSpacing.lg(context),
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (shown.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(bottom: InSpacing.lg(context)),
                      child: Text(
                        context.tr('quick_actions_none_shown'),
                        style: muted,
                      ),
                    )
                  else
                    ExcludeSemantics(
                      child: IgnorePointer(
                        child: EntityQuickActions<String>(
                          priority: [
                            for (final c in shown)
                              EntityQuickAction<String>(
                                item: EntityActionItem<String>(
                                  kind: c.id,
                                  icon: c.icon,
                                  label: c.label,
                                  enabled: true,
                                  onTap: () {},
                                ),
                                shortLabel: c.shortLabel,
                              ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.only(bottom: InSpacing.md(context)),
                    child: Text(context.tr('quick_actions_help'), style: muted),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: tokens.border),
          Expanded(
            child: ReorderableListView.builder(
              scrollController: _scroll,
              padding: EdgeInsets.symmetric(
                horizontal: InSpacing.lg(context),
                vertical: InSpacing.md(context),
              ),
              buildDefaultDragHandles: false,
              itemCount: prefs.length,
              onReorderItem: (oldIndex, newIndex) {
                final next = List<QuickActionPref>.from(prefs);
                next.insert(newIndex, next.removeAt(oldIndex));
                widget.onChanged(next);
              },
              itemBuilder: (context, i) {
                final pref = prefs[i];
                final choice = byId[pref.id]!;
                return _ActionRow(
                  key: ValueKey(pref.id),
                  index: i,
                  choice: choice,
                  visible: pref.visible,
                  onToggle: () =>
                      widget.onChanged(toggleQuickActionPref(prefs, i)),
                );
              },
            ),
          ),
          Divider(height: 1, color: tokens.border),
          Padding(
            padding: EdgeInsets.all(InSpacing.lg(context)),
            child: Row(
              children: [
                if (widget.onReset != null)
                  TextButton(
                    onPressed: widget.onReset,
                    child: Text(context.tr('reset_to_defaults')),
                  ),
                const Spacer(),
                PrimaryDialogAction(
                  label: context.tr('done'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row: drag handle, the action's icon and menu label, and its switch.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.index,
    required this.choice,
    required this.visible,
    required this.onToggle,
    super.key,
  });

  static double get _handleSize =>
      Env.isTouchPrimary ? InSizes.touchTarget : 20;

  final int index;
  final QuickActionChoice choice;
  final bool visible;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final color = visible ? tokens.ink : tokens.ink2;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ReorderableDragStartListener(
        index: index,
        child: Tooltip(
          message: context.tr('drag_to_reorder'),
          // `Container(color:)`, not a `SizedBox`: the listener defers to its
          // child, so only an opaque box grows the drag target to the finger
          // (see `customize_menu_sheet.dart`).
          child: Container(
            color: Colors.transparent,
            width: _handleSize,
            height: _handleSize,
            alignment: Alignment.center,
            child: Icon(Icons.drag_indicator, color: tokens.ink3, size: 20),
          ),
        ),
      ),
      title: Row(
        children: [
          Icon(choice.icon, size: 20, color: color),
          SizedBox(width: InSpacing.md(context)),
          Expanded(
            child: Text(
              choice.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
      trailing: Tooltip(
        message: context.tr(visible ? 'hide' : 'show'),
        child: Switch(value: visible, onChanged: (_) => onToggle()),
      ),
    );
  }
}
