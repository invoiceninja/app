import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/back_dismissible_menu_anchor.dart';
import 'package:admin/ui/core/widgets/entity_picker_field.dart';
import 'package:admin/ui/features/tasks/view_models/task_filters_mixin.dart';
import 'package:admin/utils/search_fold.dart';

/// The height of the compact filter row's controls: the touch floor under a
/// finger, a toolbar control's 36 with a pointer. The search field and the
/// three dropdowns share it, so the row reads as one band.
double taskFilterControlHeight() => Env.isTouchPrimary ? 44 : 36;

/// One task filter dimension — Project, Client or Assigned User — described
/// once and drawn two ways: [picker] (the labelled searchable field the filter
/// sheet stacks) and [dropdown] (the compact `Project · Any` control the wide
/// filter row lines up). Two renderings of one description, so the wiring
/// `taskFilterDimensions` sets up — the whole-table option streams, the by-id
/// resolution, the nameless-record fallback — cannot drift between them.
class TaskFilterDimension<T extends Object> {
  const TaskFilterDimension({
    required this.label,
    required this.anyLabel,
    required this.cacheKey,
    required this.selectedId,
    required this.itemsStream,
    required this.watchById,
    required this.displayString,
    required this.idOf,
    required this.onChanged,
    this.emptyHintKey,
    this.idleResults,
  });

  final String label;

  /// What the compact control reads with nothing picked ("Any", "Anyone").
  final String anyLabel;

  final Object cacheKey;
  final String selectedId;
  final Stream<List<T>> Function() itemsStream;
  final Stream<T?> Function(String id) watchById;
  final String Function(T) displayString;
  final String Function(T) idOf;
  final ValueChanged<T?> onChanged;
  final String? emptyHintKey;
  final int? idleResults;

  /// The labelled searchable field — `EntityPickerField`, which resolves the
  /// selection by id rather than by scanning the visible list.
  Widget picker() => EntityPickerField<T>(
    label: label,
    cacheKey: cacheKey,
    selectedId: selectedId,
    itemsStream: itemsStream,
    watchById: watchById,
    displayString: displayString,
    idOf: idOf,
    emptyHintKey: emptyHintKey,
    idleResults: idleResults,
    onChanged: onChanged,
  );

  /// The compact `label · value ▾` control.
  Widget dropdown() => TaskFilterDropdown<T>(dimension: this);
}

/// A compact labelled dropdown — `Project · Any ▾` — for the wide task filter
/// row: the dimension's name and its value on one 36 px line (44 under a
/// finger) where a labelled field spends ~70 px on two.
///
/// It opens a menu with a search field over the options, because the lists
/// are a company's whole client, project and user sets (CLAUDE.md § Searchable
/// pickers). The selection follows [EntityPickerField]'s two rules, for the
/// reason it states: it is resolved **by id** through
/// [TaskFilterDimension.watchById], not by scanning the active-only option
/// list (archiving the picked record would blank the control while the board
/// stayed filtered by it), and that resolution is **sticky** — a null emission
/// never blanks a value already shown.
class TaskFilterDropdown<T extends Object> extends StatefulWidget {
  const TaskFilterDropdown({super.key, required this.dimension});

  final TaskFilterDimension<T> dimension;

  @override
  State<TaskFilterDropdown<T>> createState() => _TaskFilterDropdownState<T>();
}

class _TaskFilterDropdownState<T extends Object>
    extends State<TaskFilterDropdown<T>> {
  StreamSubscription<List<T>>? _itemsSub;
  StreamSubscription<T?>? _selectedSub;

  /// Null until the first emission — "loading", not "none".
  List<T>? _items;
  T? _resolved;

  TaskFilterDimension<T> get _d => widget.dimension;

  @override
  void initState() {
    super.initState();
    _watchItems();
    _watchSelected();
  }

  @override
  void didUpdateWidget(TaskFilterDropdown<T> old) {
    super.didUpdateWidget(old);
    // The host rebuilds the dimension on every filter change, so compare what
    // it describes, never the object.
    final companyChanged = old.dimension.cacheKey != _d.cacheKey;
    if (companyChanged) _watchItems();
    if (companyChanged || old.dimension.selectedId != _d.selectedId) {
      _watchSelected();
    }
  }

  @override
  void dispose() {
    _itemsSub?.cancel();
    _selectedSub?.cancel();
    super.dispose();
  }

  void _watchItems() {
    _itemsSub?.cancel();
    _items = null;
    _itemsSub = _d.itemsStream().listen((next) {
      if (mounted) setState(() => _items = next);
    }, onError: (Object _) {});
  }

  void _watchSelected() {
    _selectedSub?.cancel();
    _selectedSub = null;
    final id = _d.selectedId;
    final resolved = _resolved;
    if (id.isEmpty || (resolved != null && _d.idOf(resolved) != id)) {
      _resolved = null;
    }
    if (id.isEmpty) return;
    _selectedSub = _d.watchById(id).listen((entity) {
      if (!mounted || entity == null) return;
      setState(() => _resolved = entity);
    }, onError: (Object _) {});
  }

  /// The picked record's name: the resolved row first (it outlives an archive),
  /// then the option list, then — only while neither has answered — nothing.
  String? get _selectedName {
    final id = _d.selectedId;
    if (id.isEmpty) return null;
    final resolved = _resolved;
    if (resolved != null) return _d.displayString(resolved);
    for (final it in _items ?? <T>[]) {
      if (_d.idOf(it) == id) return _d.displayString(it);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final selected = _selectedName;
    final value = selected ?? _d.anyLabel;
    final labelStyle = TextStyle(fontSize: 13, color: tokens.ink3);
    final valueStyle = TextStyle(
      fontSize: 13,
      color: selected == null ? tokens.ink2 : tokens.ink,
      fontWeight: selected == null ? FontWeight.w400 : FontWeight.w600,
    );
    return BackDismissibleMenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        _DropdownMenuBody<T>(
          dimension: _d,
          items: _items,
          // Spliced in so a picked record the active-only list no longer holds
          // still reads as picked.
          resolved: _resolved,
        ),
      ],
      builder: (context, controller, _) => OutlinedButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        style: OutlinedButton.styleFrom(
          // A field's look — the fill and the outline every input wears —
          // because this is a value, not an action.
          backgroundColor: tokens.surfaceAlt,
          foregroundColor: tokens.ink,
          side: BorderSide(color: tokens.borderStrong),
          minimumSize: Size(0, taskFilterControlHeight()),
          padding: const EdgeInsetsDirectional.only(start: 12, end: 6),
          alignment: AlignmentDirectional.centerStart,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        // One label for a screen reader, `Project: Any`, merged into the
        // button's own node.
        child: Semantics(
          label: '${_d.label}: $value',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_d.label, style: labelStyle, maxLines: 1),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  value,
                  style: valueStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 20, color: tokens.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// The open menu: a search field over the options, `Any` first.
///
/// Its own `State` so the query starts empty on every open — the menu builds
/// its children only while it is showing.
class _DropdownMenuBody<T extends Object> extends StatefulWidget {
  const _DropdownMenuBody({
    required this.dimension,
    required this.items,
    required this.resolved,
  });

  final TaskFilterDimension<T> dimension;
  final List<T>? items;
  final T? resolved;

  @override
  State<_DropdownMenuBody<T>> createState() => _DropdownMenuBodyState<T>();
}

class _DropdownMenuBodyState<T extends Object>
    extends State<_DropdownMenuBody<T>> {
  final _query = TextEditingController();

  /// Its own: the menu panel is a scroll view too, and two on the
  /// `PrimaryScrollController` break the desktop scrollbar.
  final _scroll = ScrollController();

  /// Rows offered before anything is typed — the filter bar's own cap (a
  /// filter's list is the user's whole working set).
  static const int _kDefaultIdle = 50;

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  TaskFilterDimension<T> get _d => widget.dimension;

  List<T> _options() {
    final items = [...?widget.items];
    final resolved = widget.resolved;
    if (resolved != null &&
        !items.any((it) => _d.idOf(it) == _d.idOf(resolved))) {
      items.insert(0, resolved);
    }
    final words = foldedSearchWords(_query.text);
    if (words.isEmpty) {
      return items.take(_d.idleResults ?? _kDefaultIdle).toList();
    }
    return [
      for (final it in items)
        if (containsEveryWord(foldSearchText(_d.displayString(it)), words)) it,
    ];
  }

  /// Enter in the search field: the field's own path, so it closes the menu
  /// itself. A row's tap does not — `MenuItemButton` closes the menu first and
  /// calls back a frame later, when this body is already unmounted.
  void _submit(T item) {
    final onChanged = _d.onChanged;
    MenuController.maybeOf(context)?.close();
    onChanged(item);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final options = _options();
    final rowHeight = MediaQuery.textScalerOf(
      context,
    ).scale(Env.isTouchPrimary ? 44 : 36);
    final loading = widget.items == null;
    Widget row(
      String text, {
      required bool picked,
      required VoidCallback onTap,
    }) => MenuItemButton(
      onPressed: onTap,
      leadingIcon: Icon(
        Icons.check,
        size: 16,
        color: picked ? tokens.accent : Colors.transparent,
      ),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    final onChanged = _d.onChanged;
    final rows = <Widget>[
      if (_query.text.trim().isEmpty)
        row(
          _d.anyLabel,
          picked: _d.selectedId.isEmpty,
          onTap: () => onChanged(null),
        ),
      for (final it in options)
        row(
          _d.displayString(it),
          picked: _d.idOf(it) == _d.selectedId,
          onTap: () => onChanged(it),
        ),
    ];
    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Shortcuts(
              // The menu maps ← / → to moving focus between items; inside the
              // field they must move the caret instead.
              shortcuts: const {
                SingleActivator(
                  LogicalKeyboardKey.arrowLeft,
                ): ExtendSelectionByCharacterIntent(
                  forward: false,
                  collapseSelection: true,
                ),
                SingleActivator(
                  LogicalKeyboardKey.arrowRight,
                ): ExtendSelectionByCharacterIntent(
                  forward: true,
                  collapseSelection: true,
                ),
              },
              child: TextField(
                controller: _query,
                // Typing is what a pointer user opens this to do; under a
                // finger the soft keyboard would cover the list it narrows.
                autofocus: !Env.isTouchPrimary,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                // Enter takes the first match, as a picker's does.
                onSubmitted: (_) {
                  if (options.isNotEmpty) _submit(options.first);
                },
                decoration: InputDecoration(
                  hintText: context.tr('search'),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 0,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          if (rows.isNotEmpty)
            SizedBox(
              // Lazy: a company's whole client list can be thousands of rows.
              height: (rows.length * rowHeight).clamp(0, 320).toDouble(),
              child: ListView.builder(
                controller: _scroll,
                primary: false,
                padding: EdgeInsets.zero,
                itemExtent: rowHeight,
                itemCount: rows.length,
                itemBuilder: (context, i) => rows[i],
              ),
            ),
          if (loading || options.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                context.tr(
                  loading ? 'loading' : (_d.emptyHintKey ?? 'no_records_found'),
                ),
                style: TextStyle(fontSize: 13, color: tokens.ink3),
              ),
            ),
        ],
      ),
    );
  }
}

/// The task search box: every word of it must occur in the task's
/// description, number, client or project (`TaskFiltersMixin.matchesSearch`).
///
/// Bound to [filters] in both directions — typing writes `setSearch`, and a
/// Clear made anywhere else (the row's link, the sheet's button, a chip's ✕)
/// empties the box.
class TaskSearchField extends StatefulWidget {
  const TaskSearchField({super.key, required this.filters});

  final TaskFiltersMixin filters;

  @override
  State<TaskSearchField> createState() => _TaskSearchFieldState();
}

class _TaskSearchFieldState extends State<TaskSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.filters.search,
  );

  @override
  void initState() {
    super.initState();
    widget.filters.addListener(_sync);
  }

  @override
  void didUpdateWidget(TaskSearchField old) {
    super.didUpdateWidget(old);
    if (old.filters != widget.filters) {
      old.filters.removeListener(_sync);
      widget.filters.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.filters.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    final text = widget.filters.search;
    if (_controller.text == text) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final height = taskFilterControlHeight();
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) => TextField(
        controller: _controller,
        onChanged: widget.filters.setSearch,
        autocorrect: false,
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: context.tr('search_tasks'),
          constraints: BoxConstraints(minHeight: height),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: (height - 20) / 2,
          ),
          prefixIcon: Icon(Icons.search, size: 18, color: tokens.ink3),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 0,
          ),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: context.tr('clear'),
                  onPressed: () => widget.filters.setSearch(''),
                  style: IconButton.styleFrom(
                    fixedSize: Size.square(height),
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
        ),
      ),
    );
  }
}
