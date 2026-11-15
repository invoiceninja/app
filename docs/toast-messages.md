# Toast messages

Companion to CLAUDE.md § Design system (v2). Why a toast once rendered as a blank card stretched to ~2.4× its height, what `ToastController.show` now normalizes, and what that means for code that produces a toast.

## Toast strings are normalized centrally

**Toast strings are normalized centrally — don't hand-guard them.** `ToastController.show` (`lib/ui/core/widgets/toast_controller.dart`) collapses the message to a single trimmed line, keeps at most `kToastDetailMaxLines` non-blank detail lines, drops a blank-labelled action, promotes the detail into the title when the message is blank, and **queues nothing at all** when there's nothing renderable (returning `null`, plus a debug-only `Logger` warning with a stack trace so the producer shows up in the diagnostics log). That's the fix for a class of bug where a raw server string — `ApiException.message` is non-nullable, so `{"message":""}` arrives blank, and `ApiClient._raiseFromResponse` splices 240 raw bytes of a 5xx HTML page into it — painted a blank card stretched to ~2.4× normal height (`IntrinsicHeight` sizes the card to its text, and blank lines occupy full line boxes). Consequences for new code: **never rely on newlines in a toast *title*** (use `' · '` to join, as `import_export_screen._msg` does); don't add local `message.isEmpty ? … : …` guards — `Notify.error` / `Notify.warning` already fall back to `tr('an_error_occurred')`; and note the context-free path (`Notify.capture` → `toasts?.error(...)`) has **no** such fallback, so a captured-controller caller must pass a `tr()`-derived string, never a raw server one.

## A bottom toast is lifted above pinned actions

**A toast never covers actions pinned to the bottom of a screen.** On a phone the toast sits at the bottom, which is exactly where a checkout pins its one button — on an iPhone the Tap to Pay on iPhone button, which App Review (5.3) wants never obscured; the unseen-decline notice landed on top of it. `ToastBottomInset` wraps the pinned actions (`CollectStageLayout` does it for every in-person payment stage) and reports its height to `ToastController.setBottomInset`; `ToastHost` adds the tallest reported height to the narrow layout's `bottom`. Three details keep it honest:

- It reports **after the frame** (the height isn't known during build, and a notifier poked during build throws in a sibling `ListenableBuilder`), and gives the height up from `dispose` — mid-frame, so the host defers that one rebuild to the frame's end.
- It reports **only while its route is on top** (`ModalRoute.isCurrent`): a dialog or another screen over it gets its toast at the ordinary bottom.
- `bottomInset` is a notifier of its own, so a change never rebuilds anything that listens for toasts. The wide (top-end) layout ignores it.

`collect_fallback_screen_test` ("a toast never covers the pinned actions") pins it. In a widget test a toast's card grows in from a post-frame start: pump once to start it and once more to finish it before measuring.
