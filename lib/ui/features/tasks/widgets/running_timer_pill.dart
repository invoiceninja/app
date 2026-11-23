import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/features/tasks/widgets/task_actions.dart';
import 'package:admin/domain/tasks/task_day.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/tasks/widgets/running_duration_label.dart';
import 'package:admin/ui/core/widgets/toast_controller.dart';
import 'package:admin/ui/core/widgets/toast_host.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/utils/formatting.dart';

/// Persistent "running timer" surface that lets the user stop the active
/// timer from anywhere — not just from the task edit screen.
///
/// Mount once at the AppShell level (above `NavigationRail` / below
/// `NavigationBar`). Two modes in one slot, and they can never collide —
/// claiming a booking is what makes it running:
///
///  * a timer is running → the description + live duration + stop button;
///  * nothing running, but a booked block's window is open → "Due now" and a
///    start button (invoiceninja/flutter#149). This is the app's only task
///    control reachable from every screen, which is the point: the alternative
///    is finding the Tasks list, picking a view and scrolling.
///
/// Hidden when neither holds.
///
/// Tapping the pill body → opens the task's edit screen.
/// Tapping the stop icon → enqueues a save with `stop = now` on the
/// running entry; no edit-screen detour required.
///
/// The shell's railed (wide) branch floats it at [runningTimerPillBottom];
/// the narrow branch docks the same two modes under the content instead
/// ([RunningTimerDock]).
///
/// [hiddenTaskId] is the task whose edit screen is open ([taskIdBeingEdited]),
/// and both modes leave it out. That form carries its own timer, and its Stop
/// and Start change only the draft until Save — so the pill went on ticking
/// beside a form that said the timer had stopped, and its own Stop wrote a
/// second, different stop time under the draft (invoiceninja/app#204).
class RunningTimerPill extends StatefulWidget {
  const RunningTimerPill({this.hiddenTaskId, super.key});

  final String? hiddenTaskId;

  @override
  State<RunningTimerPill> createState() => _RunningTimerPillState();
}

/// How far above the bottom of the content pane the shell pins the pill.
///
/// The shell paints the pill above every screen. So it has to stay out of the
/// bottom-end corner whenever the screen underneath may have a create FAB
/// there. It then sits at 112: the button's 16 px margin, its 56 px height,
/// and a 40 px gap.
///
/// A screen shows that FAB when its own pane is narrower than
/// [Breakpoints.wide] — in the railed shell, the 600–832 px window band. The
/// dashboard also shows one on any phone, including in landscape, where the
/// window is wide enough for the shell's railed layout
/// (invoiceninja/flutter#164). Anywhere else the corner is free, and the pill
/// sits 16 from the bottom. (Below [Breakpoints.wide] the shell docks the timer
/// instead — [RunningTimerDock] — and this offset is not used.)
///
/// [screenAlwaysHasFab] is the exception to that width rule: the Tasks daily /
/// weekly / calendar views mount their FAB ungated on width **on purpose**
/// (`tasksViewAlwaysShowsFab`), so on a desktop window this returned 16 while
/// there really was a 56 px button underneath. The pill is the later `Stack`
/// child, so it won the hit test: aiming at `+` hit stop/start instead.
///
/// [bottomBar] is the height of whatever the screen pins to its bottom edge —
/// the billing editors' sticky totals, a list's selection bar — as published
/// through `ToastBottomInset` ([ToastController.bottomInset]). It is added on
/// top of either offset: a FAB floats above a `bottomNavigationBar`, and with
/// no FAB the pill would otherwise sit on the bar's trailing figure (the
/// invoice Total, on a desktop editor).
double runningTimerPillBottom({
  required double paneWidth,
  required bool isPhone,
  bool screenAlwaysHasFab = false,
  double bottomBar = 0,
}) =>
    (isPhone || screenAlwaysHasFab || paneWidth < Breakpoints.wide ? 112 : 16) +
    bottomBar;

/// The task whose edit screen [uri] shows (`/tasks/<id>/edit`), or null — the
/// one task [RunningTimerPill] and [RunningTimerDock] leave out. Not the create
/// route: a new task is not in Drift, so the pill could not show it anyway.
String? taskIdBeingEdited(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.length != 3 ||
      segments[0] != 'tasks' ||
      segments[2] != 'edit' ||
      segments[1].isEmpty ||
      segments[1] == 'new') {
    return null;
  }
  return segments[1];
}

class _RunningTimerPillState extends State<RunningTimerPill>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The running streams, held so a rebuild — the shell rebuilds this widget
  /// on every route change, the keyboard on every inset — re-subscribes only
  /// when the company or [RunningTimerPill.hiddenTaskId] actually changed.
  (String, String?)? _streamsKey;
  Stream<Task?>? _running;
  Stream<int>? _count;

  void _openStreams(Services services, String companyId) {
    final key = (companyId, widget.hiddenTaskId);
    if (key == _streamsKey) return;
    _streamsKey = key;
    _running = services.tasks.watchRunning(
      companyId: companyId,
      exceptTaskId: widget.hiddenTaskId,
    );
    _count = services.tasks.watchRunningCount(
      companyId: companyId,
      exceptTaskId: widget.hiddenTaskId,
    );
  }

  /// "Due now" is computed against `DateTime.now()` at build time, and Drift
  /// only emits when a row changes — so a booking whose window opens while the
  /// app sits in a pocket would never surface it. A periodic ticker is the
  /// wrong tool for one transition per booking (and `task_day_load.dart`
  /// refuses one for far less); the frame that actually matters to someone
  /// between jobs is the first one after they unlock the phone.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _resumes++);
    }
  }

  /// Keys [_DueNowPill], so a resume re-creates it and re-opens its stream —
  /// a rebuild alone reuses the element, and its stream with it.
  int _resumes = 0;

  /// Whether the on-screen keyboard is up on a touch device. The pill floats
  /// over the wide shell's content, and an unfolded foldable (or a tablet in
  /// landscape) with the keyboard up has ~330 pt left — the pill would sit on
  /// the field being typed in. The narrow dock already steps aside for the
  /// keyboard (`RunningTimerDock`); this is the wide twin (docs/foldables.md).
  ///
  /// Read from the `View`, not `MediaQuery`: the pill lives in the shell
  /// `Scaffold`'s body, whose `MediaQuery` has the keyboard inset removed.
  bool _keyboardUp = false;

  /// Above the ~55–70 pt shortcut bar an iPad shows over a focused field with
  /// a hardware keyboard attached, and the IME toolbar some Android keyboards
  /// keep up beside a hardware one (up to ~100 dp) — neither covers what the
  /// pill sits on. A soft keyboard is 250 pt and up.
  static const double _softKeyboardMinInset = 150;

  bool _readKeyboardUp() {
    if (!Env.isTouchPrimary) return false;
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio >
        _softKeyboardMinInset;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardUp = _readKeyboardUp();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final up = _readKeyboardUp();
    if (up != _keyboardUp) setState(() => _keyboardUp = up);
  }

  @override
  Widget build(BuildContext context) {
    // Offstage, not removed: the streams below keep their subscriptions.
    return Offstage(offstage: _keyboardUp, child: _buildPill(context));
  }

  Widget _buildPill(BuildContext context) {
    final services = context.read<Services>();
    // Listen to the session so the pill REBUILDS + re-subscribes when the
    // active company changes. `Provider<Services>.value` never notifies and
    // this widget is mounted as a `const` instance, so without this the pill
    // kept the FIRST company's `watchRunning` stream for the whole app session
    // (showing another company's timer, a dead stop button, and hiding the
    // current company's running timer).
    return ValueListenableBuilder(
      valueListenable: services.auth.session,
      builder: (context, session, _) {
        if (session == null) return const SizedBox.shrink();
        // Permission gate — non-admin users without `view_task` shouldn't see
        // the pill (they can't open the task it points to anyway).
        final company = session.currentCompany;
        if (company == null || !company.can('view_task')) {
          return const SizedBox.shrink();
        }
        _openStreams(services, session.currentCompanyId);
        return StreamBuilder<Task?>(
          stream: _running,
          builder: (context, snapshot) {
            // A `StreamBuilder` keeps its last data across a stream swap, so
            // the frames before the new stream answers can still hold the task
            // whose editor just opened.
            final data = snapshot.data;
            final task = data?.id == widget.hiddenTaskId ? null : data;
            if (task == null || !task.isRunning || task.timeLog.isEmpty) {
              // Nothing running — but a booked job whose window is open right
              // now is the other thing worth a permanent, thumb-height
              // control. This pill is the only task affordance reachable from
              // every screen, and for someone standing outside a customer's
              // house it beats finding the Tasks list, picking a view and
              // scrolling (invoiceninja/flutter#149).
              return _DueNowPill(
                key: ValueKey(_resumes),
                services: services,
                companyId: session.currentCompanyId,
                hiddenTaskId: widget.hiddenTaskId,
              );
            }
            return StreamBuilder<int>(
              stream: _count,
              builder: (context, countSnap) => _Pill(
                task: task,
                services: services,
                runningCount: countSnap.data ?? 1,
                hiddenTaskId: widget.hiddenTaskId,
              ),
            );
          },
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.task,
    required this.services,
    required this.runningCount,
    this.hiddenTaskId,
  });

  final Task task;
  final Services services;

  /// Left out of "Stop all" as well as the count: its form holds the draft.
  final String? hiddenTaskId;

  /// Total running timers for the company. When > 1 the pill surfaces a
  /// "Stop all (N)" affordance — `watchRunning` only shows the newest one,
  /// so without this concurrent timers would accrue invisibly.
  final int runningCount;

  Future<void> _stop(BuildContext context) => _stopTimer(services, task);

  Future<void> _stopAll(BuildContext context) =>
      _stopAllTimers(services, exceptTaskId: hiddenTaskId);

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    // The newest running timer may be a teammate's: no Stop for a task this
    // user may not edit (`TaskActions.canTimeTask`).
    final canStop = TaskActions.canEditTask(services.auth.session.value, task);
    final label = _runningLabel(context, task);
    return _FloatingBarShell(
      onTap: () => context.go('/tasks/${task.id}/edit'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RunningDurationLabel(
            start: task.timeLog.last.start!,
            dotSize: 6,
            style: _durationStyle(tokens, fontSize: 13),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: tokens.onInverseMuted),
            ),
          ),
          if (canStop) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: context.tr('stop'),
              icon: const Icon(Icons.stop_circle_outlined, size: 20),
              color: tokens.onInverse,
              onPressed: () => _stop(context),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          ],
          // Concurrent timers stay visible + clearable: this pill only
          // renders the newest running task, so surface a count + a
          // one-tap "stop them all".
          if (runningCount > 1) ...[
            const SizedBox(width: 2),
            TextButton(
              onPressed: () => _stopAll(context),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
                foregroundColor: tokens.onInverse,
              ),
              child: Text(
                '${context.tr('stop_all')} ($runningCount)',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Due now" — the shell pill's second mode, shown only when no timer is
/// running and a booked block's window contains the current moment.
///
/// Deliberately the same slot, chrome and geometry as the running pill: one
/// place on screen means one thing ("the job you are on"), and the two states
/// can never collide, since claiming a booking is what makes it running.
class _DueNowPill extends StatefulWidget {
  const _DueNowPill({
    super.key,
    required this.services,
    required this.companyId,
    this.hiddenTaskId,
  });

  final Services services;
  final String companyId;
  final String? hiddenTaskId;

  @override
  State<_DueNowPill> createState() => _DueNowPillState();
}

class _DueNowPillState extends State<_DueNowPill> {
  late Stream<Task?> _stream = _open();

  /// Held in `State`, not rebuilt in `build`. `watchDueNow` selects up to 50
  /// rows and decodes each one's payload, and the parent rebuilds on every
  /// emission of the running-task stream — so an inline stream re-subscribed
  /// on any task write, with a null frame in between that blinks the pill.
  ///
  /// The freshness this used to get for free from that churn now comes from
  /// [_RunningTimerPillState.didChangeAppLifecycleState], which re-creates this
  /// element on resume — the frame that matters between jobs.
  Stream<Task?> _open() => widget.services.tasks.watchDueNow(
    companyId: widget.companyId,
    exceptTaskId: widget.hiddenTaskId,
  );

  @override
  void didUpdateWidget(_DueNowPill old) {
    super.didUpdateWidget(old);
    if (old.companyId != widget.companyId ||
        old.hiddenTaskId != widget.hiddenTaskId) {
      _stream = _open();
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final companyId = widget.companyId;
    final tokens = context.inTheme;
    return StreamBuilder<Task?>(
      stream: _stream,
      builder: (context, snap) {
        final task = snap.data;
        // Stale across a stream swap, as in the running pill.
        if (task == null || task.id == widget.hiddenTaskId) {
          return const SizedBox.shrink();
        }
        final label = taskPrimaryLabel(task);
        return _FloatingBarShell(
          onTap: () => context.go('/tasks/${task.id}/edit'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DueNowLabel(fontSize: 13, dotSize: 6),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: tokens.onInverseMuted),
                ),
              ),
              // The whole point: start the job without leaving the screen
              // you are on. Routed through `TaskActions.toggleTimer` so it
              // claims the booking, moves the status and offers Undo
              // exactly as the list row does. Not for a booking this user
              // may not edit (`TaskActions.canTimeTask`).
              if (TaskActions.canEditTask(
                services.auth.session.value,
                task,
              )) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: context.tr('start'),
                  icon: const Icon(Icons.play_circle_outlined, size: 20),
                  // Same box as `_Pill`'s stop button — without the zeroed
                  // padding an `IconButton`'s default `EdgeInsets.all(8)`
                  // makes this pill taller than the one it alternates
                  // with, in the same slot.
                  padding: EdgeInsets.zero,
                  color: tokens.warningOnInverse,
                  onPressed: () => TaskActions.toggleTimer(
                    context,
                    services,
                    companyId,
                    task,
                  ),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The running timer's chrome, shared by the floating pill and the docked bar:
/// an *inverted* surface — the theme's ink as the fill, its card colour as
/// the text — so the one live thing on a screen of white cards reads at a
/// glance, in either brightness (docs/tasks-views.md § The running timer is
/// an inverted bar).
///
/// The duration is in the mono face: the digits keep one width, so the label
/// does not shimmy as the seconds tick.
TextStyle _durationStyle(InTheme tokens, {required double fontSize}) =>
    TextStyle(
      fontFamily: kMonoFontFamily,
      fontFamilyFallback: const [kSansFontFamily],
      fontFeatures: const [FontFeature.tabularFigures()],
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      color: tokens.onInverse,
    );

/// The ripple and hover wash on [InTheme.inverseSurface]: the theme's own
/// overlay is ink-on-surface, which on an ink fill paints nothing visible.
WidgetStateProperty<Color?> _inverseOverlay(InTheme tokens) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.focused)) {
        return tokens.onInverse.withValues(alpha: 0.14);
      }
      if (states.contains(WidgetState.hovered)) {
        return tokens.onInverse.withValues(alpha: 0.08);
      }
      return null;
    });

/// "Due now", led by a still dot — both in [InTheme.warningOnInverse], so a
/// booked block never reads as a running timer, whose dot is the accent and
/// pulses. The dot holds still on purpose: nothing is ticking yet.
class _DueNowLabel extends StatelessWidget {
  const _DueNowLabel({required this.fontSize, required this.dotSize});

  final double fontSize;
  final double dotSize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.warningOnInverse,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          context.tr('due_now'),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: tokens.warningOnInverse,
          ),
        ),
      ],
    );
  }
}

/// The floating pill's shell: the inverted fill on a local `Material` (the
/// `Ink` idiom, CLAUDE.md — the ripple paints above the fill), [InRadii.r3]
/// corners, never a stadium (CLAUDE.md § Design system (v2)), and `shadow2`,
/// since it floats over the content.
class _FloatingBarShell extends StatelessWidget {
  const _FloatingBarShell({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final radius = BorderRadius.circular(InRadii.r3);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: tokens.shadow2,
      ),
      child: Material(
        color: tokens.inverseSurface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          overlayColor: _inverseOverlay(tokens),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: InSpacing.md(context),
              end: InSpacing.xs,
              top: InSpacing.xs,
              bottom: InSpacing.xs,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The running task's one-line name, shared by the pill and the dock.
String _runningLabel(BuildContext context, Task task) =>
    task.description.isEmpty
    ? (task.number.isEmpty ? context.tr('running') : '#${task.number}')
    : task.description;

/// Stop [task]'s running entry. Centralized in the repo so the
/// read-modify-write logic + outbox enqueue lives in one place (see
/// `TaskRepository.stopRunningTimer`).
Future<void> _stopTimer(Services services, Task task) async {
  final session = services.auth.session.value;
  if (session == null) return;
  await services.tasks.stopRunningTimer(
    companyId: session.currentCompanyId,
    taskId: task.id,
  );
}

/// Stop every running timer this user may edit. Every running timer in the
/// company is in Drift, a teammate's too — the server refuses the rest (401).
/// [exceptTaskId] is the task whose edit screen is open: the pill does not
/// count it, so "Stop all" does not stop it under its form's draft.
Future<void> _stopAllTimers(Services services, {String? exceptTaskId}) async {
  final session = services.auth.session.value;
  if (session == null) return;
  await services.tasks.stopAllRunning(
    companyId: session.currentCompanyId,
    only: (t) => t.id != exceptTaskId && TaskActions.canEditTask(session, t),
  );
}

/// The height of the docked timer bar, before the bottom safe inset it pays
/// beneath itself. A floor (`minHeight`), never a fixed height: at a large
/// text scale the row grows rather than slicing its descenders.
const double kRunningTimerDockHeight = 48;

/// The phone form of [RunningTimerPill]: the same two modes (a running timer;
/// a booked block that is due now), docked as a full-width bar **under** the
/// content instead of floating over it.
///
/// The floating pill hid a field or a row on most phone screens (it sat 112 px
/// up, above the FAB's clearance, so no list or form paid for it). Docked, the
/// bar is layout rather than overlay, so every screen above it is simply
/// shorter — scrollables, FABs, the billing editors' sticky totals bar and the
/// list selection bar all end above it with no per-screen code.
///
/// Wraps the content ([child]) because it has to change what the content sees:
///
/// * **It owns the bottom safe inset.** It is the last thing on the screen, so
///   it paints into the gesture strip and pads its own row above it, and hands
///   [child] a `MediaQuery` with the bottom padding removed — otherwise every
///   `SafeArea`, `BoxScrollView` and FAB above it would pay the inset a second
///   time. `CLAUDE.md` § Design system: one owner, and it is the last thing.
/// * **It hides while the keyboard is up.** The screen's own `Scaffold`
///   subtracts `viewInsets.bottom` from its box; with the bar still below it
///   that box is already 48 px + inset short, so the field the keyboard is
///   meant to reveal would land that far too high, and the bar would sit
///   behind the keyboard anyway.
/// * **It lifts the bottom toast above itself** through [ToastBottomInset]
///   (the toast host already adds the safe inset, so only the bar's own row
///   is reported).
///
/// [child] keeps its place in the tree in every state — the bar is a trailing
/// sibling, and the `MediaQuery` around [child] is always mounted — so a timer
/// starting or stopping never remounts the navigator under it.
///
/// Wide layouts keep the floating pill; the shell mounts this only in its
/// narrow branch.
class RunningTimerDock extends StatefulWidget {
  const RunningTimerDock({required this.child, this.hiddenTaskId, super.key});

  final Widget child;

  /// The task whose edit screen is open — left out, as by
  /// [RunningTimerPill.hiddenTaskId].
  final String? hiddenTaskId;

  @override
  State<RunningTimerDock> createState() => _RunningTimerDockState();
}

class _RunningTimerDockState extends State<RunningTimerDock>
    with WidgetsBindingObserver {
  late final Services _services = context.read<Services>();

  /// The company whose streams are open; null when there is no session or the
  /// user may not view tasks (the pill's permission gate).
  String? _companyId;

  /// The [RunningTimerDock.hiddenTaskId] those streams leave out.
  String? _hiddenTaskId;
  StreamSubscription<Task?>? _runningSub;
  StreamSubscription<int>? _countSub;
  StreamSubscription<Task?>? _dueSub;
  Task? _running;
  int _runningCount = 1;
  Task? _due;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _services.auth.session.addListener(_onSession);
    _resubscribe();
  }

  @override
  void didUpdateWidget(RunningTimerDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A build follows `didUpdateWidget` anyway, so no `setState` here.
    if (oldWidget.hiddenTaskId != widget.hiddenTaskId) _resubscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _services.auth.session.removeListener(_onSession);
    _cancelAll();
    super.dispose();
  }

  /// "Due now" is decided against `DateTime.now()` when the booked rows emit,
  /// and Drift only emits on a write — so re-open that one stream on resume,
  /// the frame that matters to someone between jobs (as the pill does).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    _dueSub?.cancel();
    _dueSub = null;
    _syncDue();
  }

  void _cancelAll() {
    _runningSub?.cancel();
    _countSub?.cancel();
    _dueSub?.cancel();
    _runningSub = null;
    _countSub = null;
    _dueSub = null;
  }

  void _onSession() {
    if (_resubscribe() && mounted) setState(() {});
  }

  /// Re-opens the streams for the current company and hidden task; false when
  /// neither changed.
  bool _resubscribe() {
    final session = _services.auth.session.value;
    final company = session?.currentCompany;
    final id = session != null && company != null && company.can('view_task')
        ? session.currentCompanyId
        : null;
    final hidden = widget.hiddenTaskId;
    if (id == _companyId && hidden == _hiddenTaskId) return false;
    final sameCompany = id == _companyId;
    _cancelAll();
    _companyId = id;
    _hiddenTaskId = hidden;
    // Only the hidden task changed (a task editor opened or closed): keep
    // what the bar shows until the new streams answer, unless it is the task
    // now hidden. Clearing it dropped the 48 px bar for a frame and moved the
    // whole screen under it on every route into or out of an editor.
    if (!sameCompany || _running?.id == hidden) {
      _running = null;
      _runningCount = 1;
    }
    if (!sameCompany || _due?.id == hidden) _due = null;
    if (id != null) {
      _runningSub = _services.tasks
          .watchRunning(companyId: id, exceptTaskId: hidden)
          .listen(_onRunning);
      _syncDue();
    }
    return true;
  }

  void _onRunning(Task? task) {
    final id = _companyId;
    if (id == null) return;
    final running = task != null && task.isRunning && task.timeLog.isNotEmpty
        ? task
        : null;
    _running = running;
    if (running != null) {
      _countSub ??= _services.tasks
          .watchRunningCount(companyId: id, exceptTaskId: _hiddenTaskId)
          .listen((n) => setState(() => _runningCount = n));
    } else {
      _countSub?.cancel();
      _countSub = null;
      _runningCount = 1;
    }
    _syncDue();
    setState(() {});
  }

  /// Due-now is only ever shown while nothing runs (claiming a booking is
  /// what makes it running), so its stream — up to 50 decoded rows per
  /// emission — is open only then.
  void _syncDue() {
    final id = _companyId;
    if (id != null && _running == null) {
      _dueSub ??= _services.tasks
          .watchDueNow(companyId: id, exceptTaskId: _hiddenTaskId)
          .listen((t) => setState(() => _due = t));
    } else {
      _dueSub?.cancel();
      _dueSub = null;
      _due = null;
    }
  }

  RunningTimerDockSurface? _surface(BuildContext context) {
    final session = _services.auth.session.value;
    final running = _running;
    if (running != null) {
      final canStop = TaskActions.canEditTask(session, running);
      return RunningTimerDockSurface.running(
        label: _runningLabel(context, running),
        start: running.timeLog.last.start!,
        runningCount: _runningCount,
        onOpen: () => context.go('/tasks/${running.id}/edit'),
        onStop: canStop ? () => _stopTimer(_services, running) : null,
        onStopAll: () => _stopAllTimers(_services, exceptTaskId: _hiddenTaskId),
      );
    }
    final due = _due;
    final companyId = _companyId;
    if (due == null || companyId == null) return null;
    return RunningTimerDockSurface.dueNow(
      label: taskPrimaryLabel(due),
      onOpen: () => context.go('/tasks/${due.id}/edit'),
      onStart: TaskActions.canEditTask(session, due)
          ? () => TaskActions.toggleTimer(context, _services, companyId, due)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) => RunningTimerDockLayout(
    surface: _surface(context),
    toasts: _services.toasts,
    child: widget.child,
  );
}

/// What the dock shows — resolved by [RunningTimerDock] from the task streams,
/// and plain data so [RunningTimerDockLayout] can be pumped without
/// `Services`.
@immutable
class RunningTimerDockSurface {
  const RunningTimerDockSurface.running({
    required this.label,
    required DateTime this.start,
    required this.onOpen,
    this.runningCount = 1,
    this.onStop,
    this.onStopAll,
  }) : dueNow = false,
       onStart = null;

  const RunningTimerDockSurface.dueNow({
    required this.label,
    required this.onOpen,
    this.onStart,
  }) : dueNow = true,
       start = null,
       runningCount = 0,
       onStop = null,
       onStopAll = null;

  /// A booked block whose window is open, nothing running.
  final bool dueNow;
  final String label;

  /// The running entry's start; null for [dueNow].
  final DateTime? start;

  /// Running timers in the company; > 1 adds "Stop all (N)".
  final int runningCount;
  final VoidCallback onOpen;

  /// Null when this user may not edit the task — no Stop / Start then.
  final VoidCallback? onStop;
  final VoidCallback? onStopAll;
  final VoidCallback? onStart;
}

/// The dock's layout: [child] above, the bar below it owning the bottom safe
/// inset. See [RunningTimerDock] for the three rules it keeps.
class RunningTimerDockLayout extends StatelessWidget {
  const RunningTimerDockLayout({
    required this.surface,
    required this.child,
    this.toasts,
    super.key,
  });

  /// Null renders no bar, and [child] keeps the whole box and the inset.
  final RunningTimerDockSurface? surface;
  final ToastController? toasts;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final s = surface;
    final docked = s != null && !keyboardUp;
    return Column(
      children: [
        Expanded(
          // Always mounted, so docking never changes [child]'s position in
          // the tree; only whether the inset is handed down.
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: docked,
            child: child,
          ),
        ),
        if (docked) _DockBar(surface: s, toasts: toasts),
      ],
    );
  }
}

class _DockBar extends StatelessWidget {
  const _DockBar({required this.surface, required this.toasts});

  final RunningTimerDockSurface surface;
  final ToastController? toasts;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final s = surface;
    final gutter = InSpacing.lg(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // `Ink` idiom (CLAUDE.md): the inverted fill rides on the `Material`
    // itself, so the `InkWell` ripple shows over it. It paints into the
    // gesture strip too — the bar is the last thing on screen, like a bottom
    // navigation bar. No top rule: the fill is the edge.
    return Material(
      color: tokens.inverseSurface,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ToastBottomInset(
          controller: toasts,
          child: InkWell(
            onTap: s.onOpen,
            overlayColor: _inverseOverlay(tokens),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kRunningTimerDockHeight,
              ),
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: gutter,
                  end: InSpacing.xs,
                ),
                // Tight (a 320 px phone at 2x text, three timers, one past a
                // day) the fixed children outgrew the row and pushed Stop off
                // the screen. Stop stays the last child and never shrinks;
                // "Stop all (N)" collapses to an icon with the count, and the
                // duration scales down before anything overflows.
                child: LayoutBuilder(
                  builder: (context, box) {
                    final stopAll = s.runningCount > 1 && s.onStopAll != null
                        ? '${context.tr('stop_all')} (${s.runningCount})'
                        : null;
                    final compactStopAll =
                        stopAll != null &&
                        _dockStopAllIsTight(
                          context,
                          s,
                          stopAll,
                          box.maxWidth,
                          tokens,
                        );
                    return Row(
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: s.dueNow
                                ? const _DueNowLabel(fontSize: 14, dotSize: 8)
                                : RunningDurationLabel(
                                    start: s.start!,
                                    dotSize: 8,
                                    style: _durationStyle(tokens, fontSize: 14),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: tokens.onInverseMuted,
                            ),
                          ),
                        ),
                        if (stopAll != null && compactStopAll)
                          _DockIconButton(
                            tooltip: context.tr('stop_all'),
                            icon: Icons.stop_circle,
                            color: tokens.onInverse,
                            badge: s.runningCount,
                            onPressed: s.onStopAll!,
                          )
                        else if (stopAll != null)
                          TextButton(
                            onPressed: s.onStopAll,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: InSpacing.sm,
                              ),
                              foregroundColor: tokens.onInverse,
                            ),
                            child: Text(stopAll, style: _dockStopAllStyle),
                          ),
                        if (s.onStop != null)
                          _DockIconButton(
                            tooltip: context.tr('stop'),
                            icon: Icons.stop_circle_outlined,
                            color: tokens.onInverse,
                            onPressed: s.onStop!,
                          ),
                        if (s.onStart != null)
                          _DockIconButton(
                            tooltip: context.tr('start'),
                            icon: Icons.play_circle_outlined,
                            color: tokens.warningOnInverse,
                            onPressed: s.onStart!,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _dockStopAllStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

/// The narrowest the dock lets the task's name get before "Stop all (N)"
/// gives up its text.
const double _dockMinLabelWidth = 64;

/// Whether "Stop all (N)" as text leaves the name less than
/// [_dockMinLabelWidth], measured with the real font and text scale: the
/// duration as it reads now, the gap, the button and Stop.
bool _dockStopAllIsTight(
  BuildContext context,
  RunningTimerDockSurface s,
  String stopAll,
  double maxWidth,
  InTheme tokens,
) {
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  double width(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  final start = s.start;
  final duration = start == null
      ? 0.0
      : 8 +
            6 +
            width(
              formatDuration(
                DateTime.now().difference(start),
                compactDays: true,
                showSeconds: true,
              ),
              _durationStyle(tokens, fontSize: 14),
            );
  final button =
      width(
        stopAll,
        (Theme.of(context).textTheme.labelLarge ?? const TextStyle()).merge(
          _dockStopAllStyle,
        ),
      ) +
      2 * InSpacing.sm;
  final stop = s.onStop != null ? InSizes.touchTarget : 0.0;
  return duration + 12 + button + stop + _dockMinLabelWidth > maxWidth;
}

/// A 44 px target with no compact density — `VisualDensity.compact` would
/// take 8 px off it (`docs/touch-targets.md`, trap 2) — and `shrinkWrap` so a
/// touch platform's padded tap size does not grow its layout past the bar.
class _DockIconButton extends StatelessWidget {
  const _DockIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.badge,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  /// A count drawn over the icon's top-end corner ("Stop all" collapsed).
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final count = badge;
    final tokens = context.inTheme;
    return IconButton(
      tooltip: tooltip,
      icon: count == null
          ? Icon(icon, size: 24)
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 24),
                PositionedDirectional(
                  top: -6,
                  end: -8,
                  // Clamped: a count past 1.3x would cover the icon it labels.
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        borderRadius: BorderRadius.circular(InRadii.r1),
                      ),
                      child: LtrText(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: tokens.onAccent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      color: color,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: InSizes.touchTarget,
        height: InSizes.touchTarget,
      ),
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );
  }
}
