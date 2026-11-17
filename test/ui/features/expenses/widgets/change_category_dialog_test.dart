// The expense list's Change Category prep dialog: a searchable category
// picker, Save disabled until a category is picked, and the picked id is
// what comes back (the bulk action fans it out as `bulk_categorize` rows).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/api/expense_category_api_model.dart';
import 'package:admin/data/models/domain/expense_category.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/repositories/expense_category_repository.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';
import 'package:admin/ui/features/expenses/widgets/change_category_dialog.dart';

import '../../../../_localization_helper.dart';

/// `Stream.multi`: the picker re-subscribes to `watchById` on every
/// selection change, and a single-subscription stream throws the second time.
Stream<T> _oneShot<T>(T value) => Stream<T>.multi((c) {
  c.add(value);
  c.close();
});

ExpenseCategory _cat(String id, String name) =>
    ExpenseCategory.fromApi(ExpenseCategoryApi(id: id, name: name));

class _FakeCategories implements ExpenseCategoryRepository {
  _FakeCategories(this.all);
  final List<ExpenseCategory> all;

  @override
  Stream<List<ExpenseCategory>> watchActive({required String companyId}) =>
      _oneShot(all);

  @override
  Stream<ExpenseCategory?> watch({
    required String companyId,
    required String id,
  }) => _oneShot(all.where((c) => c.id == id).firstOrNull);

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError(i.memberName.toString());
}

class _FakeAuth implements AuthRepository {
  @override
  ValueListenable<AuthSession?> get session =>
      ValueNotifier<AuthSession?>(null);

  @override
  String? get currentCompanyId => 'co';

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError(i.memberName.toString());
}

class _FakeServices implements Services {
  _FakeServices(this.expenseCategories);

  @override
  final ExpenseCategoryRepository expenseCategories;

  @override
  final AuthRepository auth = _FakeAuth();

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError(i.memberName.toString());
}

void main() {
  late Future<String?> result;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      Provider<Services>.value(
        value: _FakeServices(
          _FakeCategories([_cat('c1', 'Travel'), _cat('c2', 'Meals')]),
        ),
        child: MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => result = showChangeCategoryDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  PrimaryDialogAction save(WidgetTester tester) =>
      tester.widget<PrimaryDialogAction>(find.byType(PrimaryDialogAction));

  testWidgets('Save stays disabled until a category is picked, then returns '
      'its id', (tester) async {
    await open(tester);

    expect(find.text('Change Category'), findsOneWidget);
    expect(save(tester).enabled, isFalse);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meals').last);
    await tester.pumpAndSettle();

    expect(save(tester).enabled, isTrue);
    await tester.tap(find.byType(PrimaryDialogAction));
    await tester.pumpAndSettle();

    expect(await result, 'c2');
  });

  testWidgets('the picker searches by typing', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), 'trav');
    await tester.pumpAndSettle();

    expect(find.text('Travel'), findsWidgets);
    expect(find.text('Meals'), findsNothing);
  });

  testWidgets('Cancel returns null', (tester) async {
    await open(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });
}
