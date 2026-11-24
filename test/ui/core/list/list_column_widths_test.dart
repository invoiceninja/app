import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/list_column_widths_controller.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/user_settings_repository.dart';
import 'package:admin/domain/columns/column_definition.dart';
import 'package:admin/domain/entity_state.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/ui/core/list/cell_slot.dart';
import 'package:admin/ui/core/list/entity_list_column_headers.dart';
import 'package:admin/ui/core/list/entity_list_constants.dart';
import 'package:admin/ui/core/list/generic_list_view_model.dart';
import 'package:admin/ui/core/list/list_column_widths.dart';

import '../../../_localization_helper.dart';

/// Resizable list columns and the spare-width stretch (docs/entity-lists.md
/// § A dragged column width is a device preference).
class _Row {
  const _Row();
}

ColumnDefinition<_Row> _col(
  String id,
  double? width, {
  ColumnAlign align = ColumnAlign.start,
}) => ColumnDefinition<_Row>(
  id: id,
  labelKey: id,
  width: width,
  align: align,
  cellBuilder: (_, _) => Text(id),
);

final _status = _col('status', 110);
final _client = _col('client', 200);
final _notes = _col('notes', 240);
final _amount = _col('amount', 200, align: ColumnAlign.end);
final _date = _col('date', 120);

void main() {
  group('resolveColumnWidths', () {
    final columns = [_status, _client, _notes, _amount, _date];
    final fits = computeTableMinWidth(columns);

    test('a table that only just fits keeps the declared widths', () {
      expect(
        resolveColumnWidths(columns: columns, dragged: {}, available: fits),
        {
          'status': 110,
          'client': 200,
          'notes': 240,
          'amount': 200,
          'date': 120,
        },
      );
    });

    test('spare width goes to the wide start-aligned columns, by width', () {
      final w = resolveColumnWidths(
        columns: columns,
        dragged: {},
        available: fits + 441,
      );
      // 440 spare (one pixel of slack): client 200/440 of it, notes 240/440.
      expect(w['client'], 200 + 200);
      expect(w['notes'], 240 + 240);
      // Too narrow to stretch, or end-aligned: as declared.
      expect(w['status'], 110);
      expect(w['amount'], 200);
      expect(w['date'], 120);
      expect(
        computeTableMinWidth(columns, widths: w),
        lessThanOrEqualTo(fits + 441),
        reason: 'the stretched table never overflows its width',
      );
    });

    test('a dragged width wins, clamped, and is never stretched', () {
      final w = resolveColumnWidths(
        columns: columns,
        dragged: {'client': 10, 'notes': 300},
        available: fits + 1000,
      );
      expect(w['client'], kListColumnMinWidth);
      expect(w['notes'], 300);
      expect(
        w['status'],
        110,
        reason: 'nothing left to stretch, so the spare stays spare',
      );
    });

    test('a flex column takes the spare itself — nothing is stretched', () {
      final flex = [_col('name', null), _client];
      final w = resolveColumnWidths(
        columns: flex,
        dragged: {},
        available: 2000,
      );
      expect(w.containsKey('name'), isFalse, reason: 'renders Expanded');
      expect(w['client'], 200);
    });

    test('a dragged flex column becomes fixed', () {
      final w = resolveColumnWidths(
        columns: [_col('name', null)],
        dragged: {'name': 333},
        available: 2000,
      );
      expect(w['name'], 333);
    });
  });

  group('ListColumnWidthsController', () {
    late AppDatabase db;
    late DevicePrefsStore prefs;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      prefs = DevicePrefsStore(db);
      await prefs.load();
    });
    tearDown(() => db.close());

    test('remembers a width per entity and forgets it on reset', () async {
      final c = ListColumnWidthsController(prefs: prefs);
      addTearDown(c.dispose);
      await c.setWidth('invoice', 'client_id', 312.4);
      await c.setWidth('quote', 'client_id', 280);
      expect(c.widthsFor('invoice'), {'client_id': 312});

      // A second owner over the same store reads it back.
      final again = ListColumnWidthsController(prefs: prefs);
      addTearDown(again.dispose);
      expect(again.widthsFor('quote'), {'client_id': 280});

      await c.clearWidth('invoice', 'client_id');
      expect(c.widthsFor('invoice'), isEmpty);
      expect(c.value.keys, ['quote']);
      await c.clearWidth('quote', 'client_id');
      expect(prefs.read(DevicePrefKeys.listColumnWidths), isNull);
    });

    test('an unreadable value reads as no widths', () async {
      await prefs.write(DevicePrefKeys.listColumnWidths, '{not json');
      final c = ListColumnWidthsController(prefs: prefs);
      addTearDown(c.dispose);
      expect(c.value, isEmpty);

      await prefs.write(
        DevicePrefKeys.listColumnWidths,
        '{"invoice": {"client_id": "wide", "number": -4, "amount": 150}}',
      );
      final again = ListColumnWidthsController(prefs: prefs);
      addTearDown(again.dispose);
      expect(again.widthsFor('invoice'), {'amount': 150});
    });
  });

  group('the header handle', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<({_Vm vm, List<String> log})> pump(
      WidgetTester tester, {
      Map<String, double> widths = const {'client': 200, 'amount': 200},
      bool withResize = true,
    }) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vm = _Vm(
        companyId: 'co',
        navStateDao: db.navStateDao,
        userSettings: UserSettingsRepository(db: db),
      );
      addTearDown(vm.dispose);
      final log = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              child: ListColumnLayout(
                widths: widths,
                resize: withResize
                    ? ColumnResizeCallbacks(
                        onUpdate: (id, w) => log.add('update $id ${w.round()}'),
                        onEnd: (id) => log.add('end $id'),
                        onReset: (id) => log.add('reset $id'),
                      )
                    : null,
                child: Column(
                  children: [
                    ListenableBuilder(
                      listenable: vm,
                      builder: (_, _) => EntityListColumnHeaders<_Row>(vm: vm),
                    ),
                    Row(
                      children: [
                        for (final c in [_client, _amount])
                          CellSlot<_Row>(
                            column: c,
                            entity: const _Row(),
                            child: Text('cell ${c.id}'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (vm: vm, log: log);
    }

    // The client header's trailing edge: the end of its cell, in the gap.
    Offset clientEdge(WidgetTester tester) {
      final header = tester.getRect(find.text('CLIENT'));
      final headerRow = tester.getRect(
        find.byType(EntityListColumnHeaders<_Row>),
      );
      final cellStart =
          headerRow.left +
          16 +
          colWMoreMenu() +
          kColActionsLeadingGap +
          kColLeadingWidth +
          kColCellGap;
      return Offset(cellStart + 200 + kColCellGap / 2, header.center.dy);
    }

    testWidgets('header and row cells take the table\'s widths', (
      tester,
    ) async {
      await pump(tester, widths: const {'client': 333, 'amount': 200});
      final cell = find.ancestor(
        of: find.text('cell client'),
        matching: find.byType(CellSlot<_Row>),
      );
      expect(tester.getSize(cell).width, 333);
    });

    testWidgets('dragging the edge reports the width live, then ends', (
      tester,
    ) async {
      final (vm: _, :log) = await pump(tester);
      final mouse = await tester.startGesture(
        clientEdge(tester),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(40, 0));
      await mouse.moveBy(const Offset(40, 0));
      await mouse.up();
      await tester.pumpAndSettle();

      expect(log.last, 'end client');
      expect(
        log.where((e) => e.startsWith('update')).last,
        'update client 280',
        reason: 'the drag grew the 200 px column by the 80 px it moved',
      );
    });

    testWidgets('a double-click on the edge resets the column', (tester) async {
      final (vm: _, :log) = await pump(tester);
      await tester.tapAt(clientEdge(tester), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(clientEdge(tester), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(log, ['reset client']);
    });

    testWidgets('with nothing to store a width, no edge is draggable', (
      tester,
    ) async {
      final (:vm, :log) = await pump(tester, withResize: false);
      await tester.dragFrom(clientEdge(tester), const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(log, isEmpty);
      expect(vm.sortField, isNot('amount'));
    });
  });
}

class _Vm extends GenericListViewModel<_Row> {
  _Vm({
    required super.companyId,
    required super.navStateDao,
    required super.userSettings,
  });

  @override
  EntityType get entityType => EntityType.invoice;
  @override
  List<ColumnDefinition<_Row>> get allColumns => [_client, _amount];
  @override
  List<String> get defaultColumnIds => const ['client', 'amount'];
  @override
  String get defaultSortField => 'client';
  @override
  bool isValidColumnId(String field) => field == 'client' || field == 'amount';
  @override
  String idOf(_Row item) => 'r';
  @override
  bool isArchived(_Row item) => false;
  @override
  bool isDeleted(_Row item) => false;
  @override
  Stream<List<_Row>> watchPage() => Stream.value(const [_Row()]);
  @override
  Future<bool> fetchPage({
    required int page,
    required String? search,
    required Set<EntityState> states,
    required Map<String, Set<String>> extraFilters,
    required bool ignoreCursor,
  }) async => false;
  @override
  Future<void> refreshAll() async {}
  @override
  Iterable<BulkAction<_Row>> get bulkActions => const [];
}
