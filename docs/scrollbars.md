# Scroll bars

Companion to CLAUDE.md § Design system (v2). CLAUDE.md is at its size cap, so the rules for the
pointer platforms' scroll bar live only here: what it looks like, the "Always show scroll bars"
switch, and why that switch pins each thumb in a widget instead of in the theme. The code is
`lib/ui/core/widgets/in_scrollbar.dart` (`InScrollbar`, `InScrollBehavior`) and
`pointerScrollbarTheme` in `lib/app/theme.dart`.

Beta feedback: *"The scroll bar can be difficult to locate at times. Improving its visibility would
enhance navigation, especially with large amounts of data."* Before this, `theme.dart` set no
`ScrollbarThemeData`, so a desktop or a desktop browser drew Material's default: an 8 px thumb in
`onSurface` at 10 % opacity on light (about #E8E8E8 on white, 1.2:1), that fades 600 ms after the
scrolling stops. Hovering the edge brings it back, but only if you know it is there.

## A pointer platform's scroll bar is an `InScrollbar`, and a hand-placed one is too

**Every scroll bar on a pointer platform is an `InScrollbar` — a scroll view's own vertical bar
through `InScrollBehavior` (`MaterialApp.scrollBehavior` in `main.dart`), a hand-placed bar by
writing `InScrollbar(` where `Scrollbar(` would have gone.** A bare `Scrollbar` still gets the
look from the theme but misses "Always show scroll bars".

- **Pointer platform** is `!Env.isTouchPrimary` (`pointerScrollbars`): macOS, Windows, Linux, and a
  desktop browser. A phone's or tablet's browser reports iOS / Android and keeps Material's
  scroll bar, exactly as `docs/touch-targets.md` § Touch targets are gated on the platform, not the
  viewport explains. On a touch platform `InScrollbar` builds Material's `Scrollbar` with the
  caller's arguments, so the hand-placed bars are unchanged there, and `InScrollBehavior` returns
  Material's answer (no bar at all).
- **Horizontal scroll views get no bar of their own**, as in Material. The wide entity table
  (`entity_list_screen_scaffold.dart`), the line-item table (`line_item_table_desktop.dart`) and
  the Tasks weekly grid (`weekly_grid.dart`) place an `InScrollbar` by hand. The invoice designer's
  page (`wysiwyg_canvas.dart`) and What's New do too.
- `test/lint/no_bare_scrollbar_test.dart` fails a bare `Scrollbar(` anywhere in `lib/` but
  `in_scrollbar.dart`, which builds Material's on a touch platform.

## A wide table's row bar sits on the card's edge, not the table's

**On a pointer platform the standalone wide entity table draws its rows' vertical bar as an
`InScrollbar` around the whole card (`_vScroll`, `notificationPredicate: depth == 1 && vertical`),
and turns the rows' own bar off.** The rows' list is nested inside the sideways
`SingleChildScrollView`, so its own bar sat at the table's right edge: past the last column, off
screen whenever the columns overflow the pane, until the user panned all the way across. That is
the "large amounts of data" half of the beta report. The rows are the only vertical scroll view
one level under the sideways one, so depth 1 picks out their notifications. An embedded list
shrink-wraps into its record page and has no vertical scroll of its own, and a touch platform
draws no vertical bar there at all, so both keep the old tree. Pinned by the entity-list case in
`in_scrollbar_surfaces_test.dart`, which checks the bar is inside a 900 px window while the rows
run past it.

## The thumb is bolder ink, grows under the pointer, and is never a pill

**At rest the thumb is `InSizes.scrollbarThumb` (10 px) in `ink3`; under the pointer it grows to
`InSizes.scrollbarThumbActive` (14 px) in `ink2` over a faint track (`ink` at 6 %, `border`
edge); dragged it is `ink`. The corners are `InRadii.r0` (3 px), because `r1` (6 px) on a 10 px
thumb rounds it into a pill.**

- Colours come only from `InTheme` tokens, so every palette (the six presets and a custom one) and
  both brightnesses get a thumb in its own ink. No token was added for it. `ink3` is the palette's
  muted-text colour, about 4:1 against the surface in Sand light and 4.4:1 in Espresso dark.
  Material's light idle thumb was about 1.2:1.
- `pointerScrollbarTheme(tokens)` is the one definition. `buildInTheme` installs it as
  `scrollbarTheme` on a pointer platform (`pointerScrollbars:` overrides that, for tests), so any
  stock `Scrollbar` (Flutter's own dropdown menu, a package) matches. `InScrollbar` paints from the
  same theme and falls back to `pointerScrollbarTheme` of the ambient `InTheme` when there is no
  app theme.
- The growth and the track fade in over `InMotion.fast` through `InMotion.of(context)`, so reduced
  motion makes them instant (`docs/motion-and-haptics.md`). The show / hide fade is Material's
  300 ms, also through `InMotion`.
- **The track shows only under the pointer or during a drag, pinned or not.** Material's own
  `Scrollbar` paints a track only while the thumb is pinned (`showScrollbar && trackVisibility`),
  so a fading Material bar can never show one. That is one reason `InScrollbar` is a
  `RawScrollbar` subclass and not a `Scrollbar` with a theme. Making the theme's
  `thumbVisibility` resolve to true on hover would draw the track, but it leaves the thumb stuck:
  Material's `handleHoverExit` calls `super` (which starts the fade timer only if `showScrollbar`
  is false) before clearing its own hover flag, so the timer never starts.

## "Always show scroll bars" is a device preference, off by default, and only on a pointer platform

**Device Settings → Appearance → Always Show Scroll Bars (`DevicePrefKeys.alwaysShowScrollbars`,
device scope, default off) keeps each thumb drawn while its scroll view can scroll. The row and
its search entry exist only on a pointer platform.**

- The owner is `AlwaysShowScrollbarsController` (a `DevicePref<bool>`), provided at the root in
  `main.dart`. `InScrollbar` reads it through `watchAlwaysShowScrollbars(context)`, so flipping it
  pins or unpins every bar on the next frame without a scroll.
- Device scope: how this screen reads, like list density. A sign-out keeps it.
- The row sits under Density in the Appearance card. Its search keys (`always_show_scrollbars`,
  `always_show_scrollbars_help`) are gated by `_scrollbarsShown` in `settings_search_catalog.dart`,
  so a phone's settings search never offers a row that is not there.
- A caller's own `thumbVisibility: true` (What's New while its notes overflow, the line-item table
  while it scrolls sideways) still pins. Their old `false` became `null`, so the switch applies
  where they did not pin.

## The pin is decided per bar, never a theme-level `thumbVisibility`

**"Always show scroll bars" never sets `ScrollbarThemeData.thumbVisibility`. `InScrollbar` pins a
thumb, and lets it be dragged, only while its controller has exactly one attached position. It
checks on every build and every metrics change, and its bar checks again each time it would show
or take a gesture.** This is what makes the switch unable to throw.

The classic failure. A `RawScrollbar` whose `showScrollbar` is true schedules a debug check that
its controller (or, with none, the `PrimaryScrollController`) has exactly one position
(`_debugCheckHasValidScrollPosition` in Flutter's `widgets/scrollbar.dart`). The check runs a
frame after every `didChangeDependencies` (a theme, `MediaQuery` or text-direction change) and
after `thumbVisibility` flips on. An interactive bar, which every desktop bar is, runs the same
check each time it starts fading in or out (`_validateInteractions`). A theme-level
`thumbVisibility: true` turns the first one on for every bar in the app, at mount and at every
theme change, scrolled or not. These are the trees where it fails:

- **Two scroll views on one controller**: "The provided ScrollController is attached to more
  than one ScrollPosition." Three surfaces wrap their body in
  `PrimaryScrollController(automaticallyInheritForPlatforms: TargetPlatform.values.toSet())`
  (`SettingsRecordBody`, What's New, the Welcome dialog). On those, every vertical scroll view
  inside that passes no controller attaches to the same controller. The Tasks filter menu gives
  its panel its own controller for exactly this reason (`task_filter_controls.dart`). A Material
  bar on such a tree is quiet until it is scrolled, then asserts as its fade starts. A theme-level
  pin makes it assert at mount.
- **A bar placed above a scroll view that has not attached yet**, or whose scroll view was swapped
  out in the same frame: "The Scrollbar's ScrollController has no ScrollPosition attached."
- **A bar with no controller over a horizontal scroll view**: it falls back to the
  `PrimaryScrollController`, and on a pointer platform no scroll view attaches to that unless told
  to. The Tasks weekly grid did this, so its first sideways scroll on a pointer platform already
  hit the fade-in check. It now owns its controller (`_HorizontalScroll`).

What `InScrollbar` does instead:

1. `_InScrollbarState.build` passes `thumbVisibility: wanted && pinnable`. `pinnable` means "the
   controller has exactly one position" at that moment. A scroll view's own bar is built by
   `InScrollBehavior` inside `Scrollable.build`, after its position has attached. A hand-placed
   bar is usually built before its child attaches, so it starts unpinned and re-checks on each
   `ScrollMetricsNotification`. Those are dispatched after layout, so a `setState` there is legal;
   one dispatched during layout waits for the next frame.
2. `_PointerScrollbarState.showScrollbar` asks again, live: pinned only if `thumbVisibility` is
   true **and** the controller still has one position.
3. `_PointerScrollbarState.enableGestures` is false unless the controller has exactly one
   position. Such a bar is passive: `RawScrollbarState` already refuses a thumb drag then
   (`_canHandleScrollGestures`), and a passive bar skips the fade-in / fade-out check, which is
   what unpinning a bar (or scrolling a shared tree) would otherwise trip. The trade: a bar given
   the wrong controller no longer asserts in debug, it just does nothing.
4. While `didChangeDependencies` runs, `showScrollbar` answers false, so the frame-later check is
   never scheduled from there. That check is debug-only. Every real use reads the live answer
   above. And the frame the check would run in can be the one in which a route or a condition
   swaps out the scroll view the bar was pinned to.

The flip-on path (`didUpdateWidget`) still schedules its check, but only after step 1 has seen one
position in that same build. The only gap left is a second scroll view attaching to the same
controller within that one frame.

**Pinned by** `test/ui/core/widgets/in_scrollbar_test.dart`. For both shared-controller trees, a
control test shows a theme-level `thumbVisibility` asserting at mount ("more than one
ScrollPosition"), and a second test shows the pin does not assert through a scroll, a theme change
and the switch. Two more cover a pinned hand-placed bar whose scroll view leaves in the same frame
as a theme change, and a hand-placed bar over a scroll view that arrives later.
`test/ui/core/widgets/in_scrollbar_surfaces_test.dart` mounts the scroll-heavy surfaces with the
switch on and asserts no exception through a drag, a wheel scroll, a hover, a theme change, the
switch and a resize: an entity list with its wide table scrolling both ways, a record screen with
pinned tabs, Device Settings, and the Tasks weekly grid.

## Duplicate bars on a hand-placed vertical bar are not new

A hand-placed vertical `InScrollbar` around a scroll view (the invoice designer's page) also gets
the scroll view's own bar from `InScrollBehavior`, and the two paint on top of each other. Material
did the same with `Scrollbar`. Both bars have the same geometry and an opaque thumb, so this only
shows as a slightly stronger track under the pointer. Turning the inner one off
(`ScrollConfiguration.of(context).copyWith(scrollbars: false)`) would also turn off every nested
scroll view's bar below it, so it is left alone.
