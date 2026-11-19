# Lazy lists and keep-alives

Companion to CLAUDE.md § Design system (v2). Why every lazy list in `lib/` says whether its rows may be kept alive, what happens when one is, and how a crash report now names the screen it came from.

## Every lazy list decides on keep-alives: off, a fixed extent, or a reason

`ListView`, `ListView.builder` / `.separated`, `SliverList.*` and `SliverChildBuilderDelegate` / `SliverChildListDelegate` default to `addAutomaticKeepAlives: true`. With that default a row that asks to be kept alive is *parked* when it scrolls out of range: it stays attached, but it is not laid out again. A hovered `InkWell` asks while its highlight lasts. A focused `EditableText` asks while it has focus.

That is harmless until the parked row is also showing an overlay. A `Tooltip` (any `OverlayPortal`) adds a `_RenderDeferredLayoutBox` to the nearest `Overlay`. That box is laid out only through its surrogate, which sits inside the row, or when the theater lays itself out, and adding the box does not dirty the theater. If the tooltip comes up in the same frame that scrolls the row past the cache extent, the row is collected without being laid out and parked, and the box never gets a size. `_RenderTheaterMixin.hitTestChildren` still hit-tests it:

- release: `Null check operator used on a null value` in `RenderBox.hitTest` (`box.dart`, the `_size!`);
- debug: `Cannot hit test a render box that has never been laid out`, then `'!_debugDuringDeviceUpdate': is not true` in `MouseTracker` on every later frame.

It throws on every pointer event, so the app stops reacting to the mouse. The window keeps drawing and the keyboard still works, so a user reads it as a freeze and closes the app. The framework bug is [flutter/flutter#193566](https://github.com/flutter/flutter/issues/193566), open as of Flutter 3.50.0, and tracked as `docs/upstream-workarounds.md` entry 31.

**How it reached us.** Sentry FLUTTER-ADMIN-1F, 2026-11-18: 61 such errors in one second from a Windows user on 5.1.30, who reported the app freezing while typing in a quote's Item cell. The same error shape is on 5.1.21 (Flutter 3.47.7), so it predates the 3.50 upgrade. The release stack cannot say which list it was: AOT folds identical `hitTestChildren` bodies under one name (`_RenderValueLayoutBuilder.hitTestChildren` appears dozens of times), and Sentry carried no screen. A fuzz test drove the real `LineItemTableDesktop` (typing, arrows, option hovers, wheel flicks, same-frame bursts; 40 seeds × 300 steps) and never hit it. The product popover sets `itemExtent: 48` and the line-item rows sit in a shrink-wrapped list under a `SingleChildScrollView`, so neither can park a row. Hence the app-wide rule, and the route breadcrumbs below.

**The rule.** Each lazy list does one of three things:

1. `addAutomaticKeepAlives: false`. A row that scrolls out of range is disposed with its tooltip. Right for any list whose rows hold no state that must outlive scrolling: record lists, popovers, pickers, menus. It is also right for a list with a single child (login, a tab body), which can never be scrolled out of range. Turning it off also drops the framework's `_SelectionKeepAlive`, so under `AppSelectionArea` (the activity feed, a DocuNinja document) a text selection that runs past the cache extent loses the rows scrolled away. That trade is deliberate: a lost selection is recoverable, while a frozen mouse is not.
2. A fixed `itemExtent`, `itemExtentBuilder` or `prototypeItem`. Each row then gets tight constraints, which makes it a relayout boundary, and a dirty boundary is still laid out from the pipeline's dirty list while parked. The product popover and the report table are this shape.
3. `// lint: allow-keep-alives <reason>` on the list's line or the one above, for a list whose rows' own state must survive scrolling: form fields (a field scrolled away keeps its text and focus), a drag in progress (the kanban board), cards that keep themselves alive (the dashboard). These stay exposed to the bug and are the trade.

`test/lint/lazy_list_keep_alives_test.dart` enforces it. `ReorderableListView` and `SliverReorderableList` take no `addAutomaticKeepAlives`, so the lint does not read them. Their lists are short sheets and shrink-wrapped tables, and a shrink-wrapped list in an unbounded parent lays out every row. `GridView` is not read either, because its tiles get tight constraints.

**The test that pins it.** `test/ui/core/list/lazy_list_keep_alive_freeze_test.dart` hovers a row's `IconButton` (with a `Tooltip`) and jumps the list in the same frame. With keep-alives on it asserts the framework error. With them off, or with a fixed extent, the next hit test is clean. A failed device update leaves the debug `MouseTracker` asserting forever, so the test swaps in a fresh one (`initMouseTracker()`) before it ends. Its first case is the signal that #193566 is fixed.

## A crash report names the screen through a route breadcrumb

`lib/app/route_breadcrumbs.dart` (`RouteBreadcrumbs`, wired in `main.dart` next to `NavHistoryController`) listens to the router and, on each change of route **pattern**, calls `addNavigationBreadcrumb(from:, to:)` from `package:store_services`. The real package sends Sentry a `navigation` breadcrumb. The F-Droid twin is a no-op, and so is the real one until `runWithCrashReporting` has started the SDK (debug builds, web, a self-hosted build without a DSN).

It records `/quotes/:id/edit`, never `/quotes/Wpmbk5ezJn/edit?tab=items`: the pattern names the screen, while a location carries record ids and query state. Moving between two records on the same screen records nothing. The breadcrumb still passes the `beforeBreadcrumb` scrubber. Pinned by `test/app/route_breadcrumbs_test.dart`.
