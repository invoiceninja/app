import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/domain/contact_email_mode.dart';
import 'package:admin/ui/core/widgets/contact_edit_rows.dart';
import 'package:admin/ui/core/widgets/toast_controller.dart';

import '../../../_localization_helper.dart';

ContactRowData _row(
  String id,
  String first, {
  bool primary = false,
  String email = '',
  String phone = '',
}) => ContactRowData(
  id: id,
  firstName: first,
  lastName: '',
  email: email,
  phone: phone,
  isPrimary: primary,
  isBlank: false,
);

Future<ToastController> _pump(
  WidgetTester tester,
  List<ContactRowData> contacts, {
  VoidCallback? Function(int)? onDelete,
}) async {
  final toasts = ToastController();
  addTearDown(toasts.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: ChangeNotifierProvider<ToastController>.value(
        value: toasts,
        child: Scaffold(
          body: SizedBox(
            width: 360,
            child: ContactEditRows(
              contacts: contacts,
              fieldsBuilder: (_, _) => const [],
              onMakePrimary: (_) {},
              onDelete: onDelete ?? (_) => null,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return toasts;
}

void main() {
  testWidgets('the primary is labelled in words, with no star, and the '
      'collapsed row keeps its phone', (tester) async {
    await _pump(tester, [
      _row('a', 'Alice', primary: true, email: 'a@x.test'),
      _row('b', 'Bob', email: 'b@x.test', phone: '555 0100'),
    ]);
    expect(find.text('Primary'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.textContaining('555 0100'), findsOneWidget);
  });

  testWidgets('a lone contact is neither labelled Primary nor removable', (
    tester,
  ) async {
    await _pump(tester, [_row('a', 'Alice', primary: true)]);
    expect(find.text('Primary'), findsNothing);
    expect(find.text('Remove contact'), findsNothing);
  });

  testWidgets('Remove asks nothing and offers Undo naming the contact', (
    tester,
  ) async {
    var removed = -1;
    var undone = false;
    final toasts = await _pump(
      tester,
      [_row('a', 'Alice', primary: true), _row('b', 'Bob')],
      onDelete: (i) {
        removed = i;
        return () => undone = true;
      },
    );
    // The primary is open; Remove is on it.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(removed, 0);
    expect(find.byType(AlertDialog), findsNothing);
    final toast = toasts.toasts.single;
    expect(toast.message, contains('Alice'));
    expect(toast.action?.label, 'Undo');
    toast.action!.onPressed();
    expect(undone, isTrue);
  });

  group('ContactEmailModeField', () {
    Future<void> pumpField(
      WidgetTester tester, {
      required ContactEmailMode value,
      required bool isPrimary,
      required ValueChanged<ContactEmailMode> onChanged,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: ContactEmailModeField(
              value: value,
              isPrimary: isPrimary,
              onChanged: onChanged,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('picks To / CC / None', (tester) async {
      ContactEmailMode? picked;
      await pumpField(
        tester,
        value: ContactEmailMode.to,
        isPrimary: false,
        onChanged: (m) => picked = m,
      );
      await tester.tap(find.text('CC'));
      expect(picked, ContactEmailMode.cc);
      await tester.tap(find.text('None'));
      expect(picked, ContactEmailMode.none);
    });

    testWidgets('CC is disabled on the primary contact', (tester) async {
      ContactEmailMode? picked;
      await pumpField(
        tester,
        value: ContactEmailMode.to,
        isPrimary: true,
        onChanged: (m) => picked = m,
      );
      await tester.tap(find.text('CC'));
      expect(picked, isNull);
      final radios = tester.widgetList<Radio<ContactEmailMode>>(
        find.byType(Radio<ContactEmailMode>),
      );
      expect(
        radios.firstWhere((r) => r.value == ContactEmailMode.cc).enabled,
        isFalse,
      );
    });
  });
}
