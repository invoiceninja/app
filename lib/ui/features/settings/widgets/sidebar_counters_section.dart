import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/db/app_database.dart' show CompanyRow;
import 'package:admin/data/models/domain/enabled_modules.dart';
import 'package:admin/domain/entity_registry.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/sidebar_badge_modes.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/widgets/watch_builder.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/ui/features/settings/widgets/setting_row.dart';
import 'package:admin/ui/features/shell/widgets/sidebar_badge.dart';

/// Search keys for the settings sidebar search. Colocated with the section so
/// adding a field updates both ends in one place (see
/// `search_catalog_consistency_test`). The tip is worded for the input: the
/// catalog gates each help key to the platform that renders it.
const kSidebarCountersSearchKeys = <String>[
  'menu_counters',
  'menu_counters_help_pointer',
  'menu_counters_help_touch',
];

/// The tip's key: "right-click" where the menu has a pointer, "long-press"
/// where it has a finger.
String menuCountersHelpKey() => Env.isTouchPrimary
    ? 'menu_counters_help_touch'
    : 'menu_counters_help_pointer';

/// The width each counter column needs: a picker, a badge and a name that
/// still reads. Two columns only when each would get this much.
const double kMenuCounterColumnMinWidth = 360;

/// Between the two counter columns.
const double _kColumnGap = 24;

/// Whether the counters lay out in two columns in [width]: each measured
/// column at least [kMenuCounterColumnMinWidth], and never on a phone.
bool menuCountersTwoColumns(double width, {required bool phone}) =>
    !phone && (width - _kColumnGap) / 2 >= kMenuCounterColumnMinWidth;

/// Device Settings → Appearance → Main menu, its second card: what each menu
/// row's count badge counts — the discoverable, keyboard-reachable half of
/// issue #9. (The other half is right-clicking, or long-pressing, the row
/// itself.)
///
/// Title-less ([FormSection.title] null): it continues the Main menu section
/// above it, and on a wide page its empty title column keeps it level with
/// that card.
///
/// The rows follow the menu's own order (`SidebarMenuController.entriesFor`,
/// i.e. `resolveMenuEntries`), so a menu the user rearranged reads the same
/// here. Two columns when each measures [kMenuCounterColumnMinWidth] or more,
/// filled top to bottom: the first half of the menu, then the second, which
/// is also the order focus moves in.
///
/// Each row previews the **real badge**, fed by the same stream and rendered in
/// the same colour the rail will use, so picking "Overdue" shows the actual red
/// number you're about to get rather than making you go and look.
class SidebarCountersSection extends StatelessWidget {
  const SidebarCountersSection({super.key});

  @override
  Widget build(BuildContext context) {
    final services = context.read<Services>();
    final companyId = services.auth.session.value?.currentCompanyId ?? '';
    if (companyId.isEmpty) return const SizedBox.shrink();
    final enabledModules =
        services.auth.session.value?.currentCompany?.enabledModules ?? 0;
    final handlers = [
      for (final h in services.entityRegistry.sidebarTop)
        if (!h.disabled &&
            h.badgeStream != null &&
            isEntityModuleEnabledForCompany(h.type, enabledModules))
          h,
    ];
    if (handlers.isEmpty) return const SizedBox.shrink();

    return WatchBuilder<CompanyRow?>(
      cacheKey: companyId,
      create: () => services.db.companiesDao.watchById(companyId),
      builder: (context, snap) {
        final trackInventory = snap.data?.trackInventory ?? false;
        return ListenableBuilder(
          listenable: Listenable.merge([
            services.sidebarBadgeModes,
            services.sidebarMenu,
          ]),
          builder: (context, _) {
            final byId = {for (final h in handlers) h.type.name: h};
            final ordered = [
              for (final entry in services.sidebarMenu.entriesFor([
                for (final h in handlers) h.type.name,
              ]))
                ?byId[entry.id],
            ];
            final rows = [
              for (final h in ordered)
                _CounterRow(
                  key: ValueKey('menu_counter_${h.type.name}'),
                  handlers: h,
                  companyId: companyId,
                  modes: availableBadgeModes(
                    h.badgeModes,
                    trackInventory: trackInventory,
                  ),
                ),
            ];
            final on = rows
                .where(
                  (r) =>
                      services.sidebarBadgeModes.modeFor(
                        r.handlers.type,
                        available: r.modes,
                      ) !=
                      kBadgeModeNone,
                )
                .length;
            return FormSection(
              title: null,
              flush: true,
              children: [
                SettingRow(
                  icon: const Icon(Icons.looks_one_outlined),
                  title: context.tr('menu_counters'),
                  // Spelled out, not `tr(menuCountersHelpKey())`: the
                  // catalog consistency scan reads each key as a literal.
                  subtitle: Env.isTouchPrimary
                      ? context.tr('menu_counters_help_touch')
                      : context.tr('menu_counters_help_pointer'),
                  stackWhenNarrow: false,
                  control: _CountersSummary(
                    on: on,
                    onReset: services.sidebarBadgeModes.hasOverrides
                        ? services.sidebarBadgeModes.resetAll
                        : null,
                  ),
                ),
                SettingBlock(child: _CounterColumns(rows: rows)),
              ],
            );
          },
        );
      },
    );
  }
}

/// "3 on" and, when anything differs from the defaults, Reset.
class _CountersSummary extends StatelessWidget {
  const _CountersSummary({required this.on, required this.onReset});

  final int on;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr('menu_counters_on', {'count': '$on'}),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.inTheme.ink2),
        ),
        if (onReset != null) ...[
          const SizedBox(width: InSpacing.sm),
          TextButton(onPressed: onReset, child: Text(context.tr('reset'))),
        ],
      ],
    );
  }
}

/// One column, or two filled top to bottom, decided by the measured width.
class _CounterColumns extends StatelessWidget {
  const _CounterColumns({required this.rows});

  final List<_CounterRow> rows;

  @override
  Widget build(BuildContext context) {
    final phone = Breakpoints.isPhone(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget column(List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        );
        if (!menuCountersTwoColumns(constraints.maxWidth, phone: phone)) {
          return column(rows);
        }
        final half = (rows.length + 1) ~/ 2;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: column(rows.sublist(0, half))),
            const SizedBox(width: _kColumnGap),
            Expanded(child: column(rows.sublist(half))),
          ],
        );
      },
    );
  }
}

class _CounterRow extends StatelessWidget {
  const _CounterRow({
    super.key,
    required this.handlers,
    required this.companyId,
    required this.modes,
  });

  final EntityHandlers handlers;
  final String companyId;

  /// What this row's picker offers — the same list the row's right-click
  /// menu reads, filtered the same way, so the two can't offer different
  /// things.
  final List<SidebarBadgeMode> modes;

  @override
  Widget build(BuildContext context) {
    final services = context.read<Services>();
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final selected = services.sidebarBadgeModes.modeFor(
      handlers.type,
      available: modes,
    );
    final mode = modes.firstWhere(
      (m) => m.id == selected,
      orElse: () => modes.first,
    );
    // Narrower on a phone, where the entity's name needs the room.
    final pickerWidth = MediaQuery.sizeOf(context).width < Breakpoints.wide
        ? 132.0
        : 180.0;
    final off = selected == kBadgeModeNone;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: Env.isTouchPrimary ? InSizes.touchTarget : 36,
        ),
        child: Row(
          children: [
            Icon(handlers.effectiveOutlinedIcon, size: 18, color: tokens.ink3),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr(handlers.effectiveLabelKey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: tokens.ink),
              ),
            ),
            // Rendered unconditionally, even on `none` (where its stream is a
            // constant zero and it collapses itself): dropping the widget out
            // of the children list would shift the dropdown into a different
            // element slot and rebuild it mid-interaction.
            _BadgePreview(
              entityType: handlers.type,
              companyId: companyId,
              mode: mode,
            ),
            const SizedBox(width: InSpacing.sm),
            // One width for every row's picker. Left to size itself a
            // `DropdownButton` is as wide as its longest option, which differs
            // per entity, so the labels and the badges beside them started at
            // a different place on every line.
            SizedBox(
              width: pickerWidth,
              child: DropdownButton<String>(
                value: selected,
                isDense: true,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                // The rows' own size, not the dropdown's larger default.
                style: theme.textTheme.bodyMedium?.copyWith(color: tokens.ink),
                // None reads muted in the closed picker, so the rows that
                // count something stand out down the column.
                selectedItemBuilder: (context) => [
                  for (final m in modes)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        context.tr(m.labelKey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: off ? tokens.ink3 : tokens.ink),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  services.sidebarBadgeModes.set(handlers.type, value);
                },
                items: [
                  for (final m in modes)
                    DropdownMenuItem(
                      value: m.id,
                      child: Text(
                        context.tr(m.labelKey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live preview of the badge this row will render in the sidebar. Same widget,
/// same query, same tone — so the setting shows its own effect.
class _BadgePreview extends StatefulWidget {
  const _BadgePreview({
    required this.entityType,
    required this.companyId,
    required this.mode,
  });

  final EntityType entityType;
  final String companyId;
  final SidebarBadgeMode mode;

  @override
  State<_BadgePreview> createState() => _BadgePreviewState();
}

class _BadgePreviewState extends State<_BadgePreview> {
  Stream<int>? _counts;
  String? _sourceKey;

  /// (Re)build the hoisted count stream only when what it counts changes.
  ///
  /// This card lives under a `ListenableBuilder` on the mode controller, so
  /// touching *one* dropdown rebuilds every row. Handing `StreamBuilder` a
  /// freshly-built stream each time makes it tear down and re-subscribe — so
  /// one dropdown change would re-run all 14 Drift queries. (It wouldn't
  /// *flicker*: `StreamBuilder.afterDisconnected` carries the last snapshot
  /// data across a stream swap. The cost is churn, not a visible blink.)
  /// Same pattern as `PartyMoneyCell._ensureStream` and the sidebar's own
  /// `_cachedBadge`.
  void _ensureStream() {
    final key =
        '${widget.entityType.name}:${widget.companyId}:${widget.mode.id}';
    if (key == _sourceKey) return;
    _sourceKey = key;
    _counts = context.read<Services>().watchEntityCount(
      widget.entityType,
      widget.companyId,
      modeId: widget.mode.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureStream();
    return StreamBuilder<int>(
      stream: _counts,
      builder: (context, snap) {
        final count = snap.data ?? 0;
        // Zero renders nothing here for the same reason it does in the rail:
        // "no overdue invoices" is the absence of a badge, not a badge reading
        // zero. Keeps the preview honest about what you'll actually see.
        if (count == 0) return const SizedBox.shrink();
        return SidebarBadge(count: count, tone: widget.mode.tone);
      },
    );
  }
}
