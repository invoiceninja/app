import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/list_density_controller.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/ui/core/detail/profile_card_width.dart';
import 'package:admin/ui/core/list/list_density_scope.dart';
import 'package:admin/ui/core/widgets/initials_avatar.dart';
import 'package:admin/ui/core/widgets/party_contact_row.dart';

import '../../../_responsive_helper.dart';

/// A contact is two lines: the name line, then the details — the address and
/// the number in a `Wrap` that drops the number to its own line where the two
/// do not fit. The address is never cut to an ellipsis.

const _longEmail =
    'accounts.payable.department@very-long-company-name.example.com';

Widget _row(
  String name, {
  String? email,
  String phone = '',
  bool isPrimary = false,
  String? avatarSeed,
  int actions = 3,
}) => PartyContactRow(
  name: name,
  email: email ?? '${name.split(' ').first.toLowerCase()}@acme.example.com',
  phone: phone,
  isPrimary: isPrimary,
  avatarSeed: avatarSeed,
  actions: [
    for (var i = 0; i < actions; i++)
      PartyContactAction(icon: Icons.copy, label: 'Action $i', onTap: () {}),
  ],
);

/// Whether the [Text] showing [text] was laid out whole: not cut to an
/// ellipsis, not clipped to a line count.
void expectWhole(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse, reason: '$text was cut');
  expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
  expect(paragraph.maxLines, isNull);
}

void main() {
  testWidgets('the details sit under the name, the number beside the address '
      'where there is room', (tester) async {
    await pumpAt(
      tester,
      700,
      _row('Jane Doe', phone: '+1 415 555 2671'),
      phoneActions: true,
    );
    final name = tester.getRect(find.text('Jane Doe'));
    final email = tester.getRect(find.text('jane@acme.example.com'));
    final phone = tester.getRect(find.text('+1 415-555-2671'));
    expect(email.top, greaterThanOrEqualTo(name.bottom));
    expect(email.left, name.left);
    expect((email.center.dy - phone.center.dy).abs(), lessThan(2));
    expect(phone.left, greaterThan(email.right));
    // No separator to dangle at a wrap.
    expect(find.text('·'), findsNothing);
    expectNoOverflow(tester);
  });

  testWidgets('without room the number drops to its own line', (tester) async {
    await pumpAt(
      tester,
      320,
      _row('Jane Doe', email: _longEmail, phone: '+1 415 555 2671'),
      phoneActions: true,
    );
    final email = tester.getRect(find.text(_longEmail));
    final phone = tester.getRect(find.text('+1 415-555-2671'));
    expect(phone.top, greaterThanOrEqualTo(email.bottom));
    expect(phone.left, email.left);
    expectWhole(tester, _longEmail);
    expectNoOverflow(tester);
  });

  for (final width in [390.0, 440.0]) {
    for (final scale in [1.0, kTextScaleMax]) {
      testWidgets('the address is never ellipsized at $width px, '
          'text scale $scale', (tester) async {
        await pumpAt(
          tester,
          width,
          Column(
            children: [
              _row('Jane Doe', email: _longEmail, phone: '+1 415 555 2671'),
              // No name: the address is the title.
              _row('', email: _longEmail, isPrimary: true),
            ],
          ),
          textScale: scale,
          phoneActions: true,
        );
        final paragraphs = tester.renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.text(_longEmail),
            matching: find.byType(RichText),
          ),
        );
        expect(paragraphs, hasLength(2));
        for (final p in paragraphs) {
          expect(p.didExceedMaxLines, isFalse);
          expect(p.overflow, isNot(TextOverflow.ellipsis));
        }
        expectNoOverflow(tester);
      });
    }
  }

  testWidgets('Primary is an outline in the accent ink, with no fill', (
    tester,
  ) async {
    await pumpAt(tester, 700, _row('Jane Doe', isPrimary: true));
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(PartyContactPrimaryLabel),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = box.decoration as BoxDecoration;
    final tokens = InTheme.light;
    expect(decoration.color, isNull);
    expect((decoration.border! as Border).top.color, tokens.border);
    expect((decoration.border! as Border).top.width, 1);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(InRadii.r1),
      reason: 'a rounded rectangle, never a pill',
    );
    final text = tester.widget<Text>(find.text('Primary'));
    expect(text.style?.color, tokens.accentInk);
  });

  group('Compact density', () {
    late AppDatabase db;
    late ListDensityController density;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final prefs = DevicePrefsStore(db);
      await prefs.load();
      density = ListDensityController(prefs: prefs);
    });
    tearDown(() async {
      density.dispose();
      await db.close();
    });

    testWidgets('the row pads 8 px a side at Normal and 4 at Compact', (
      tester,
    ) async {
      Future<double> heightAt({required bool compact}) async {
        await density.setCompact(compact);
        await pumpAt(
          tester,
          700,
          ListDensityScope(
            controller: density,
            child: _row('Jane Doe', actions: 0),
          ),
        );
        final row = tester.getRect(find.byType(PartyContactRow));
        final name = tester.getRect(find.text('Jane Doe'));
        expect(name.top - row.top, compact ? 4 : InSpacing.sm);
        return row.height;
      }

      final normal = await heightAt(compact: false);
      final compact = await heightAt(compact: true);
      expect(normal - compact, 8);
    });
  });

  group('hover', () {
    Finder wash() => find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter?.runtimeType.toString() == '_WashPainter',
    );

    testWidgets('a pointer gets a faint wash under the row', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpAt(tester, 700, _row('Jane Doe', actions: 0));
      expect(wash(), findsOneWidget);
      CustomPainter painter() => tester.widget<CustomPaint>(wash()).painter!;
      final atRest = painter();
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: const Offset(690, 1300));
      await gesture.moveTo(tester.getCenter(find.text('Jane Doe')));
      await tester.pump();
      final hovered = painter();
      expect(hovered.shouldRepaint(atRest), isTrue, reason: 'washed on enter');
      await gesture.moveTo(const Offset(690, 1300));
      await tester.pump();
      expect(painter().shouldRepaint(hovered), isTrue, reason: 'gone on exit');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a finger gets none', (tester) async {
      await pumpAt(tester, 700, _row('Jane Doe', actions: 0));
      expect(wash(), findsNothing);
    });
  });

  group('avatars', () {
    Widget card(double width, List<String> emails) => ProfileCardWidthScope(
      width: width,
      child: Builder(
        builder: (context) {
          final show = PartyContactRow.showAvatars(context, emails: emails);
          return Column(
            children: [
              for (final e in emails)
                _row('Jane Doe', email: e, avatarSeed: show ? 'ct_$e' : null),
            ],
          );
        },
      ),
    );

    testWidgets('a pointer gets them where every address fits beside one', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpAt(
        tester,
        700,
        // The test font draws every glyph a full em wide, so short ones.
        card(440, ['jo@a.co', 'sam@b.co']),
      );
      final avatars = tester.widgetList<InitialsAvatar>(
        find.byType(InitialsAvatar),
      );
      expect(avatars, hasLength(2));
      for (final a in avatars) {
        expect(a.size, 32);
        expect(a.radius ?? InRadii.r1, InRadii.r1);
      }
      final avatar = tester.getRect(find.byType(InitialsAvatar).first);
      final name = tester.getRect(find.text('Jane Doe').first);
      expect(name.left - avatar.right, 12);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('one address that would not fit takes them off every row', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpAt(tester, 700, card(440, ['jo@a.co', _longEmail]));
      expect(find.byType(InitialsAvatar), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a phone never gets them', (tester) async {
      // `flutter test` reports Android (touch); the view is what makes it a
      // phone — `setSurfaceSize` leaves `MediaQuery` at 800x600.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpAt(tester, 390, card(390, ['jo@a.co']));
      expect(find.byType(InitialsAvatar), findsNothing);
    });

    testWidgets('a card that is not told its width draws none', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpAt(
        tester,
        700,
        Builder(
          builder: (context) => Text(
            '${PartyContactRow.showAvatars(context, emails: ['jo@a.co'])}',
          ),
        ),
      );
      expect(find.text('false'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
