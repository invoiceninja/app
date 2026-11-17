// The server's step catalog (`GET /subscriptions/steps`) carries no labels —
// only each step's `id` and `dependencies` — so a new payment link's two
// default steps rendered as blank rows and both pickers as empty menus. The
// name is the translation of the id, as React shows it.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/domain/payment_link.dart';
import 'package:admin/data/repositories/payment_link_repository.dart';
import 'package:admin/data/services/subscriptions_api.dart';
import 'package:admin/ui/features/payment_links/view_models/payment_link_edit_view_model.dart';
import 'package:admin/ui/features/payment_links/widgets/edit/payment_link_steps_tab.dart';

import '../../../_localization_helper.dart';

void main() {
  testWidgets('steps with no server label are named by their id', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final vm = PaymentLinkEditViewModel(
      repo: PaymentLinkRepository(db: db, api: _FakeSubscriptionsApi()),
      companyId: 'co',
      existing: emptyPaymentLink().copyWith(
        id: 'real_1',
        steps: 'cart,auth.login-or-register',
      ),
    );
    // The wire shape: no label at all.
    vm.seedStepsForTest(const [
      PaymentLinkStep(id: 'auth.login', label: '', dependencies: []),
      PaymentLinkStep(
        id: 'auth.login-or-register',
        label: '',
        dependencies: [],
      ),
      PaymentLinkStep(id: 'auth.register', label: '', dependencies: []),
      PaymentLinkStep(id: 'cart', label: '', dependencies: []),
    ]);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [InTheme.light]),
        localizationsDelegates: kTestLocalizationsDelegates,
        home: Scaffold(body: PaymentLinkStepsTab(vm: vm)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Cart'), findsOneWidget);
    expect(find.text('Login or Register'), findsOneWidget);
  });
}

class _FakeSubscriptionsApi implements SubscriptionsApi {
  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
