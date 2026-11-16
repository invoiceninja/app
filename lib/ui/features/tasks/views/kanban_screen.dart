import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/ui/core/widgets/formatter_scope.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/features/shell/widgets/app_drawer.dart';
import 'package:admin/ui/features/tasks/view_models/kanban_view_model.dart';
import 'package:admin/ui/features/tasks/views/task_list_screen.dart';
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_board.dart';
import 'package:admin/ui/features/tasks/widgets/task_filter_bar.dart';
import 'package:admin/ui/features/tasks/widgets/task_filters_sheet.dart';
import 'package:admin/ui/features/tasks/widgets/tasks_view_toggle.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/domain/tasks/kanban_prefs.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/back_dismissible_menu_anchor.dart';

/// Top-level kanban screen. Mounts its own [KanbanViewModel] (separate from
/// the list VM) and renders the board. AppBar carries the same toggle the
/// list screen has so the user can flip back.
class KanbanScreen extends StatefulWidget {
  const KanbanScreen({super.key});

  @override
  State<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends State<KanbanScreen> {
  late final Services _services;
  late String _companyId;
  late KanbanViewModel _vm;

  @override
  void initState() {
    super.initState();
    _services = context.read<Services>();
    _companyId = _services.auth.session.value!.currentCompanyId;
    _vm = KanbanViewModel(
      repo: _services.tasks,
      statusRepo: _services.taskStatuses,
      companyId: _companyId,
      projectRepo: _services.projects,
    );
    _services.auth.session.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    final s = _services.auth.session.value;
    if (s == null || s.currentCompanyId == _companyId) return;
    final old = _vm;
    setState(() {
      _companyId = s.currentCompanyId;
      _vm = KanbanViewModel(
        repo: _services.tasks,
        statusRepo: _services.taskStatuses,
        companyId: _companyId,
        projectRepo: _services.projects,
      );
    });
    old.dispose();
  }

  @override
  void dispose() {
    _services.auth.session.removeListener(_onSessionChanged);
    _vm.dispose();
    super.dispose();
  }

  /// The single call site per screen: the AppBar's filter action and the chip
  /// strip's chips both route here, so the sheet's arguments cannot drift
  /// between them.
  void _openFilters() =>
      openTaskFilters(context, filters: _vm, companyId: _vm.companyId);

  @override
  Widget build(BuildContext context) {
    final prefs = _services.kanbanPrefs;
    return ValueListenableBuilder<KanbanPrefs>(
      valueListenable: prefs,
      builder: (context, value, _) => _build(context, value, prefs.set),
    );
  }

  Widget _build(
    BuildContext context,
    KanbanPrefs prefs,
    ValueChanged<KanbanPrefs> setPrefs,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // One gate, all of this screen's consumers of it — the AppBar's
        // flavour, its filter action, the bar's own layout and, on the three
        // time-oriented views, the view header. `Scaffold.appBar` is built
        // outside the body so the bar can never inform it, and two gates
        // disagree in the 600-832 px band; see `taskFiltersInline`. Same shape
        // as `EntityListScreenScaffold`, which reads `wide` here too.
        final wide = Breakpoints.isWide(constraints);
        final inline = taskFiltersInline(
          paneWidth: constraints.maxWidth,
          isPhone: Breakpoints.isPhone(context),
        );
        return Scaffold(
          appBar: buildTasksViewAppBar(
            context,
            TasksViewMode.kanban,
            wide: wide,
            // Both null while the pickers render inline — a second entry point
            // there would be redundant chrome over the row itself.
            filters: inline ? null : _vm,
            onEditFilters: _openFilters,
            viewAction: _DisplayMenu(prefs: prefs, onChanged: setPrefs),
          ),
          // The drawer itself — the AppBar's hamburger needs something to
          // open. Mirrors `EntityListScreenScaffold`, which attaches it the
          // same way for the list view.
          drawer: Breakpoints.isGlobalNavVisible(context)
              ? null
              : const AppDrawer(),
          // Deliberately no `floatingActionButton` — the one Tasks view that can
          // drop it, because a FAB may only go where the substitute is the SAME
          // verb. Every column ends in its own `+ New Task`, which is a plain
          // new-task create and a better one (it seeds the column's status, so the
          // task lands where the user clicked; this FAB seeded nothing, and on a
          // phone `endFloat` put it over the footer of whichever column was
          // scrolled to the right edge). Daily and weekly are NOT a precedent: they
          // do have a second create, but it is `TaskDailyActions.logTime` behind a
          // `Log time` button — a different verb that pre-fills a time entry — so
          // dropping their FAB would make a plain new task unreachable there;
          // calendar's only other create is convert-this-event. React's kanban has
          // no page-level create control either (invoiceninja/flutter#135).
          // `test/lint/tasks_view_wiring_test.dart` fails the build if one returns.
          // The board doesn't go through `EntityListScreenScaffold`, which is
          // what provides this everywhere else — so without it a card's booked
          // time rendered 12-hour while the same task's list row rendered the
          // company's clock.
          body: FormatterScope(
            // Nullable on purpose, and mounted unconditionally — see
            // `FormatterScope`: branching on readiness changes the tree shape
            // and remounts the whole board when the formatter lands.
            formatter: context.read<Services>().formatterIfReady(_vm.companyId),
            child: ChangeNotifierProvider<KanbanViewModel>.value(
              value: _vm,
              child: Column(
                children: [
                  TaskFilterBar(
                    filters: _vm,
                    companyId: _vm.companyId,
                    inline: inline,
                    onEditFilters: _openFilters,
                  ),
                  // The opening sync (`KanbanViewModel.isSyncing`): the board
                  // is already showing what the device holds, so this is a
                  // hairline, never a spinner over it.
                  ListenableBuilder(
                    listenable: _vm,
                    builder: (context, _) => SizedBox(
                      height: 2,
                      child: _vm.isSyncing
                          ? const LinearProgressIndicator(minHeight: 2)
                          : null,
                    ),
                  ),
                  Expanded(
                    child: KanbanBoard(prefs: prefs, onPrefsChanged: setPrefs),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The board's own AppBar control: what the lanes group by, and which lines a
/// card shows. Everything in it is a `KanbanPrefs` field, saved as it is
/// picked; the menu stays open across picks so several can be made at once.
class _DisplayMenu extends StatelessWidget {
  const _DisplayMenu({required this.prefs, required this.onChanged});

  final KanbanPrefs prefs;
  final ValueChanged<KanbanPrefs> onChanged;

  static String _groupLabel(BuildContext context, KanbanGroupBy g) =>
      context.tr(switch (g) {
        KanbanGroupBy.none => 'none',
        KanbanGroupBy.client => 'client',
        KanbanGroupBy.project => 'project',
        KanbanGroupBy.assignee => 'assigned_to',
      });

  static String _fieldLabel(BuildContext context, KanbanCardField f) =>
      context.tr(switch (f) {
        KanbanCardField.client => 'client',
        KanbanCardField.project => 'project',
        KanbanCardField.assignee => 'assigned_to',
        KanbanCardField.time => 'duration',
        KanbanCardField.number => 'task_number',
      });

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    Widget heading(String key) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
      child: Text(
        context.tr(key),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: tokens.ink3,
        ),
      ),
    );
    return BackDismissibleMenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        heading('group_by'),
        for (final g in KanbanGroupBy.values)
          RadioMenuButton<KanbanGroupBy>(
            value: g,
            groupValue: prefs.groupBy,
            closeOnActivate: false,
            onChanged: (next) => onChanged(prefs.copyWith(groupBy: next)),
            child: Text(_groupLabel(context, g)),
          ),
        const Divider(height: 8),
        heading('card_fields'),
        for (final f in KanbanCardField.values)
          CheckboxMenuButton(
            value: prefs.shows(f),
            closeOnActivate: false,
            onChanged: (_) => onChanged(prefs.toggleField(f)),
            child: Text(_fieldLabel(context, f)),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.tune),
        tooltip: context.tr('board_display'),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
