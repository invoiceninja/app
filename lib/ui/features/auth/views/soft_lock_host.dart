import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/native_window.dart';
import 'package:admin/app/services.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/toast_controller.dart';
import 'package:admin/ui/core/widgets/toast_host.dart';
import 'package:admin/ui/features/auth/view_models/lock_view_model.dart';
import 'package:admin/ui/features/auth/widgets/lock_panel.dart';

/// The soft lock (docs/soft-lock.md): the signed-in app locked **in place**.
///
/// Wraps the whole routed app in `main.dart`'s builder, above the router's
/// Navigator, and while [locked] lays an opaque [LockPanel] over it — never a
/// redirect to `/lock`, which would dispose an open editor and its unsaved
/// changes. Nothing under the lock is rebuilt or remounted: the wrappers below
/// are always present and only their flags change (CLAUDE.md § Forms: a
/// focused field never changes its place in the tree).
///
/// While locked:
///
/// * **Pointer.** The panel is a later [Stack] child, so it is hit first and a
///   Stack stops at the first child hit; the app gets no tap, hover or
///   scroll. The app sits in its own [TapRegionSurface], so a tap on the
///   panel is not an "outside tap" to the app's menus and pickers either.
/// * **Keyboard.** The app is under [ExcludeFocus] — whatever it had focused
///   (and the soft keyboard's text connection with it) is let go, and nothing
///   in it can take focus back — while the panel holds focus in its own scope,
///   whose trap ends every key the panel doesn't use. The app's whole keyboard
///   layer hangs off focus inside the shell (docs/keyboard.md), so none of it
///   is consulted. The focus the app had is restored on unlock.
/// * **Back.** Android's back would pop the router beneath, so a child of the
///   router's [backButtonDispatcher] takes priority and swallows it (closing
///   the panel's own dialog first).
/// * **Screen readers.** The app is under [ExcludeSemantics].
/// * **Dialogs.** Every dialog, menu and sheet the app had open lives in the
///   router's Navigator, under the panel. The panel's own dialogs (the sign-out
///   confirmation, the unsynced-work prompt) open in a Navigator of its own,
///   and its toasts in a [ToastHost] of its own, both above the app.
///
/// Deep links, shared files, a widget's Start and the review prompt wait on
/// `AuthRepository.appLocked` and replay after the unlock (`ArrivalGate`).
class SoftLockHost extends StatefulWidget {
  const SoftLockHost({
    super.key,
    required this.locked,
    required this.child,
    this.backButtonDispatcher,
    this.titleBand,
  });

  /// `AuthRepository.softLocked`.
  final ValueListenable<bool> locked;

  /// The routed app.
  final Widget child;

  /// The router's root dispatcher (`GoRouter.backButtonDispatcher`); null in a
  /// harness without a router.
  final BackButtonDispatcher? backButtonDispatcher;

  /// True while the frameless window draws its own title bar
  /// (`NativeWindow.customFrame` where `WindowFrame.paintsTitleBar()`): the
  /// panel leaves that band uncovered, so the window can still be moved,
  /// minimised and closed. `WindowFrame` hides its history arrows while
  /// locked, so nothing else in the band acts on the app.
  final ValueListenable<bool>? titleBand;

  @override
  State<SoftLockHost> createState() => _SoftLockHostState();
}

class _SoftLockHostState extends State<SoftLockHost> {
  /// What had focus in the app when it locked, put back on unlock.
  FocusNode? _restore;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _locked = widget.locked.value;
    widget.locked.addListener(_onLockedChanged);
  }

  @override
  void didUpdateWidget(SoftLockHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locked != widget.locked) {
      oldWidget.locked.removeListener(_onLockedChanged);
      widget.locked.addListener(_onLockedChanged);
      _onLockedChanged();
    }
  }

  @override
  void dispose() {
    widget.locked.removeListener(_onLockedChanged);
    super.dispose();
  }

  void _onLockedChanged() {
    final locked = widget.locked.value;
    if (locked == _locked) return;
    if (locked) {
      // Taken now, before the rebuild's ExcludeFocus lets it go.
      final primary = FocusManager.instance.primaryFocus;
      _restore = identical(primary, FocusManager.instance.rootScope)
          ? null
          : primary;
    } else {
      final restore = _restore;
      _restore = null;
      if (restore != null) {
        // After the frame that lifts the ExcludeFocus — until then the node
        // still can't take focus.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (restore.context != null && restore.canRequestFocus) {
            restore.requestFocus();
          }
        });
      }
    }
    setState(() => _locked = locked);
  }

  @override
  Widget build(BuildContext context) {
    final band = widget.titleBand;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Always these three, in this order: only the flags change, so the
        // app under them is never remounted.
        TapRegionSurface(
          child: ExcludeFocus(
            excluding: _locked,
            child: ExcludeSemantics(excluding: _locked, child: widget.child),
          ),
        ),
        if (_locked)
          band == null
              ? _SoftLockOverlay(
                  backButtonDispatcher: widget.backButtonDispatcher,
                )
              : ValueListenableBuilder<bool>(
                  valueListenable: band,
                  builder: (context, drawn, child) => Padding(
                    padding: EdgeInsets.only(
                      top: drawn ? kAppTitleBarHeight : 0,
                    ),
                    child: child,
                  ),
                  child: _SoftLockOverlay(
                    backButtonDispatcher: widget.backButtonDispatcher,
                  ),
                ),
      ],
    );
  }
}

class _SoftLockOverlay extends StatefulWidget {
  const _SoftLockOverlay({required this.backButtonDispatcher});

  final BackButtonDispatcher? backButtonDispatcher;

  @override
  State<_SoftLockOverlay> createState() => _SoftLockOverlayState();
}

class _SoftLockOverlayState extends State<_SoftLockOverlay>
    with WidgetsBindingObserver {
  late final LockViewModel _vm;
  final ToastController _toasts = ToastController();
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'Soft lock');
  final FocusNode _unlockFocus = FocusNode(debugLabel: 'Soft lock: Unlock');
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  ChildBackButtonDispatcher? _back;

  /// Prompt the next time the app is resumed: set when the lock went up while
  /// the app was not in front, and when it truly went to the background. Not
  /// set by `inactive` — the OS prompt itself makes the app inactive, and a
  /// cancel would otherwise reopen the prompt forever.
  bool _promptOnResume = false;

  /// One pending focus re-check at a time.
  bool _reclaimScheduled = false;

  @override
  void initState() {
    super.initState();
    final services = context.read<Services>();
    _vm = LockViewModel(
      auth: services.auth,
      biometric: services.biometric,
      allowDeviceCredential: true,
    );
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocusChanged);
    final root = widget.backButtonDispatcher;
    if (root != null) {
      _back = root.createChildBackButtonDispatcher()
        ..addCallback(_onBack)
        ..takePriority();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusPanel();
      if (_isResumed) {
        unawaited(_unlock());
      } else {
        _promptOnResume = true;
      }
    });
  }

  @override
  void dispose() {
    _back?.removeCallback(_onBack);
    FocusManager.instance.removeListener(_onFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    _vm.dispose();
    _toasts.dispose();
    _scope.dispose();
    _unlockFocus.dispose();
    super.dispose();
  }

  static bool get _isResumed {
    final state = WidgetsBinding.instance.lifecycleState;
    // Null before the engine has reported one (a widget test): in front.
    return state == null || state == AppLifecycleState.resumed;
  }

  Future<void> _unlock() async {
    if (!mounted) return;
    await _vm.unlock(context.tr('please_authenticate'));
  }

  Future<void> _signOut() async {
    final context = _navigator.currentContext;
    if (context == null) return;
    await signOutFromLock(context, _vm, canOpenOutbox: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // A prompt in flight (the device-passcode screen is its own activity
        // on Android) hides the app too; that is not the user leaving.
        if (!_vm.busy) _promptOnResume = true;
      case AppLifecycleState.resumed:
        if (_promptOnResume && !_vm.busy) {
          _promptOnResume = false;
          unawaited(_unlock());
        }
        _onFocusChanged();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Back closes the panel's own dialog, and otherwise does nothing: never
  /// the router beneath.
  Future<bool> _onBack() async {
    final navigator = _navigator.currentState;
    if (navigator != null && navigator.canPop()) {
      unawaited(navigator.maybePop());
    }
    return true;
  }

  /// Focus belongs inside the panel while it is up. The app beneath can't take
  /// it (ExcludeFocus), but a closing dialog or the root scope can end up
  /// with it; take it back, post-frame and only while the app is in front —
  /// a suspend parks focus on the root scope and restores it itself.
  void _onFocusChanged() {
    if (_reclaimScheduled || !mounted) return;
    if (_scope.hasFocus) return;
    _reclaimScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reclaimScheduled = false;
      if (!mounted || _scope.hasFocus || !_isResumed) return;
      _focusPanel();
    });
  }

  /// Unlock when it can take focus; the panel's scope while a prompt has it
  /// disabled.
  void _focusPanel() {
    if (_vm.busy || _unlockFocus.context == null) {
      _scope.requestFocus();
    } else {
      _unlockFocus.requestFocus();
    }
  }

  /// The last stop for a key inside the panel: the panel's own controls and
  /// the default shortcuts below have had it. Ends there, so nothing above
  /// the panel sees it — except a ⌘ / Ctrl chord, left to the OS (⌘Q, ⌘H)
  /// rather than swallowed.
  KeyEventResult _trap(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed || keyboard.isControlPressed) {
      return KeyEventResult.skipRemainingHandlers;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // The panel's own Navigator announces its single page as "cannot pop";
    // WidgetsApp applies the last such notice it sees, which would leave
    // Android's back with the OS after the unlock (docs/architecture.md § Why
    // Android system back needs three things to keep working). The app's own
    // navigators speak for themselves.
    return NotificationListener<NavigationNotification>(
      onNotification: (_) => true,
      child: ChangeNotifierProvider<ToastController>.value(
        value: _toasts,
        // The trap sits ABOVE the scope, so a key still ends there when focus
        // has fallen back onto the scope node itself.
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _trap,
          child: FocusScope(
            node: _scope,
            child: Shortcuts(
              shortcuts: WidgetsApp.defaultShortcuts,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  HeroControllerScope.none(
                    child: Navigator(
                      key: _navigator,
                      pages: [
                        MaterialPage<void>(
                          key: const ValueKey('soft_lock'),
                          child: LockPanel(
                            key: const ValueKey('soft_lock_panel'),
                            vm: _vm,
                            title: context.tr('locked'),
                            message: context.tr('soft_lock_message'),
                            onUnlock: () => unawaited(_unlock()),
                            onSignOut: () => unawaited(_signOut()),
                            unlockFocusNode: _unlockFocus,
                          ),
                        ),
                      ],
                      onDidRemovePage: (_) {},
                    ),
                  ),
                  Positioned.fill(child: ToastHost(controller: _toasts)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
