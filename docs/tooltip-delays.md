# Tooltip delays

Companion to CLAUDE.md § Design system (v2). How long a tooltip waits before it appears, where a
sidebar row's tooltip goes, and why. The numbers live in `InTooltip` (`lib/app/design_tokens.dart`);
the theme default is set in `lib/app/theme.dart`.

## Tooltip delays are `InTooltip` tiers, never a literal

A tooltip waits `InTooltip.labelDelay` when it is the control's only label and `InTooltip.hintDelay`
when it adds to a label already on screen. Two tiers, nothing in between:

| Tier | Delay | When | Examples |
|---|---|---|---|
| Label | 700 ms (`InTooltip.labelDelay`, the theme default) | The tooltip is the only thing naming the control | Icon buttons, the collapsed sidebar rail, a sidebar tile's ellipsized label, a truncated calendar chip |
| Hint | 1500 ms (`InTooltip.hintDelay`, passed at the call site) | The control already shows its label; the tooltip adds a shortcut, a count's meaning, "Copy", a format | An expanded sidebar row's `G`-then-letter hint, a sidebar badge's "3 overdue", the list's New button, a copyable value, the weekly grid's `1.5 / 1:30` |

A `Tooltip` with no `waitDuration` takes the label tier from `TooltipThemeData`. Pass
`InTooltip.hintDelay` only for the hint tier, and never a literal `Duration`.

**Why.** Material's default `waitDuration` is zero (`material_ui` `tooltip.dart`, `_defaultWaitDuration`),
and before this the theme set none. So most of the app's tooltips appeared the instant the pointer
crossed a control on its way somewhere else. The handful that did set a delay used 300, 400, 500 and
600 ms with no rule. A self-hosted beta user (November 2026, Safari, mouse) asked for 4 to 5 seconds
after the sidebar's `Kunden  G dann C` tooltip kept landing on the next row.

**Why not 4 to 5 seconds.** No platform uses anything close to that: Windows waits about 0.5 s, macOS about
1 s, browsers' native `title` 0.5 to 1 s. At 4 s an icon-only control effectively has no label, since
nobody holds the pointer still that long, and the collapsed rail would become unusable to learn. The
complaint was about the zero-delay tooltips and the redundant hint covering the next row; the two tiers
fix the first, the placement below fixes the second. A delay preference was considered and rejected:
users would not find a slider, and the complaint was about wrong defaults, not taste.

**Warm state.** Flutter already shows the next tooltip at once while a previous one is still open
(`RawTooltipState._handleMouseEnter`: `withDelay: tooltipsToDismiss.isNotEmpty ? Duration.zero : hoverDelay`).
Its window is the 100 ms exit delay plus the fade. Don't widen it with a longer `exitDuration`: that
is what makes moving down a stack of rows show every row's tooltip in turn.

## A sidebar row's tooltip opens beside the row, and a shortcut tooltip never takes the pointer

`tooltipBesideTarget(direction)` (`lib/ui/core/widgets/shortcut_tooltip.dart`) is a
`TooltipPositionDelegate` that centres the tooltip vertically on its target and puts it on the
target's end side, then the start side, then Material's above / below if neither fits.
`SidebarNavItem` passes it for rows, expanded or on the collapsed rail; tiles keep Material's
placement. Above / below put the tooltip on the neighbouring row, which is where the pointer is
usually heading.

`ShortcutTooltip` sets `ignorePointer: true`. Material defaults `ignorePointer` on only for a plain
`message` (`widget.ignorePointer ?? widget.message != null`), so a `richMessage` tooltip took the
pointer. A tooltip drawn over the next row then stayed open while the pointer was on it, and hid that
row from hover and click.
