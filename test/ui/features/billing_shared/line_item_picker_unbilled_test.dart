import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/ui/features/billing_shared/line_item_picker/line_item_picker_body.dart';

import '../shell/_shell_test_helpers.dart';

/// What the Add-items picker's Tasks and Expenses tabs list: what is left to
/// bill. User feedback: "why can't expenses be added to a quote? all it shows
/// are my real expenses" — the tab listed company overhead (a client-less,
/// non-billable expense) on every client's document.
void main() {
  Future<ShellFixture> pumpPicker(
    WidgetTester tester, {
    Future<void> Function(ShellFixture fixture)? seed,
    List<Uri>? asked,
    String clientId = '',
  }) async {
    final fixture = await buildFixture(
      companies: [
        FakeCompany(id: 'co1', name: 'Co', isAdmin: true, isOwner: true),
      ],
      online: true,
      httpClient: _server(asked ?? []),
    );
    addTearDown(fixture.dispose);
    if (seed != null) await seed(fixture);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        Scaffold(
          body: LineItemPickerBody(
            companyId: 'co1',
            clientId: clientId,
            showTasksAndExpenses: true,
            invoiceInclusive: false,
            excludedTaskIds: const {},
            excludedExpenseIds: const {},
            formatter: null,
          ),
        ),
      ),
    );
    await _settle(tester);
    return fixture;
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.textContaining(label).first);
    await _settle(tester);
  }

  testWidgets('Expenses lists the billable ones, never overhead', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      seed: (f) async {
        await _expense(f, 'e1', 'Office rent', billable: false);
        await _expense(f, 'e2', 'Site travel', billable: true);
        await _expense(f, 'e3', 'Billed taxi', billable: true, invoiceId: 'i1');
      },
    );
    await openTab(tester, 'Expenses');

    expect(find.text('Site travel'), findsOneWidget);
    expect(find.text('Office rent'), findsNothing);
    expect(find.text('Billed taxi'), findsNothing);
    await _disposeTree(tester);
  });

  testWidgets('an older unbilled task behind 250 newer billed ones is listed', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      seed: (f) async {
        await f.db.taskDao.upsertAll([
          for (var i = 0; i < 250; i++)
            _taskRow('b$i', 'Billed $i', updatedAt: 1000 + i, invoiceId: 'i1'),
          _taskRow('old', 'Old unbilled work', updatedAt: 1),
        ]);
      },
    );
    await openTab(tester, 'Tasks');

    expect(find.text('Old unbilled work'), findsOneWidget);
    expect(find.textContaining('Billed '), findsNothing);
    await _disposeTree(tester);
  });

  testWidgets("this client's older unbilled task outlives 250 of another's", (
    tester,
  ) async {
    await pumpPicker(
      tester,
      clientId: 'c1',
      seed: (f) async {
        await f.db.taskDao.upsertAll([
          for (var i = 0; i < 250; i++)
            _taskRow(
              'o$i',
              'Other client $i',
              updatedAt: 1000 + i,
              clientId: 'c2',
            ),
          _taskRow('mine', 'This client work', updatedAt: 1, clientId: 'c1'),
          _taskRow('free', 'No client work', updatedAt: 2),
        ]);
      },
    );
    await openTab(tester, 'Tasks');

    expect(find.text('This client work'), findsOneWidget);
    expect(find.text('No client work'), findsOneWidget);
    expect(find.textContaining('Other client '), findsNothing);
    await _disposeTree(tester);
  });

  testWidgets('the server is asked for pending expenses, uninvoiced tasks', (
    tester,
  ) async {
    final asked = <Uri>[];
    await pumpPicker(tester, asked: asked);

    String statusOf(String path) => asked
        .firstWhere((u) => u.path == '/api/v1/$path')
        .queryParameters['client_status']!;
    expect(statusOf('expenses'), 'pending');
    expect(statusOf('tasks'), 'uninvoiced');
    await _disposeTree(tester);
  });
}

/// Answers the picker's `client_status` pages with nothing new — the rows
/// under test are the ones already in Drift — recording each one in [asked].
/// Everything else fails as if offline.
http.Client _server(List<Uri> asked) => MockClient((request) async {
  final url = request.url;
  if (request.method == 'GET' &&
      url.queryParameters.containsKey('client_status')) {
    asked.add(url);
    return http.Response(
      jsonEncode({
        'data': <Object>[],
        'meta': {
          'pagination': {
            'total': 0,
            'count': 0,
            'per_page': 50,
            'current_page': 1,
            'total_pages': 1,
          },
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  throw http.ClientException('offline (test fixture)');
});

Future<void> _expense(
  ShellFixture f,
  String id,
  String notes, {
  required bool billable,
  String invoiceId = '',
}) => f.db.expenseDao.upsert(
  ExpensesCompanion.insert(
    id: id,
    companyId: 'co1',
    updatedAt: 1,
    invoiceId: Value(invoiceId),
    shouldBeInvoiced: Value(billable),
    payload: jsonEncode({
      'id': id,
      'public_notes': notes,
      'should_be_invoiced': billable,
      'invoice_id': invoiceId,
      'amount': 10,
      'updated_at': 1,
    }),
  ),
);

TasksCompanion _taskRow(
  String id,
  String description, {
  required int updatedAt,
  String invoiceId = '',
  String clientId = '',
}) => TasksCompanion.insert(
  id: id,
  companyId: 'co1',
  updatedAt: updatedAt,
  description: Value(description),
  invoiceId: Value(invoiceId),
  clientId: Value(clientId),
  payload: jsonEncode({
    'id': id,
    'description': description,
    'invoice_id': invoiceId,
    'client_id': clientId,
    'updated_at': updatedAt,
    'time_log': jsonEncode([
      [1700000000, 1700003600, '', true],
    ]),
  }),
);

/// `pumpAndSettle` never settles over a live Drift watch stream — step the
/// clock instead, letting the real async work run between frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Tear the subtree down inside the test body so the Drift watches' close
/// timers fire before the binding's end-of-test `!timersPending` check.
Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}
