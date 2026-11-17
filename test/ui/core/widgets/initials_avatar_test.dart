import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/widgets/avatar_tint.dart';
import 'package:admin/ui/core/widgets/initials_avatar.dart';

/// The shared identity badge behind Client / Vendor list rows and the
/// assigned-user badge on Task rows. `initialsFor` is deliberately
/// Unicode-aware: a Cyrillic or CJK name must yield real initials, not '?'.
void main() {
  group('initialsFor', () {
    test('takes the first and last word', () {
      expect(initialsFor('Ada Lovelace'), 'AL');
      expect(initialsFor('Johann Sebastian Bach'), 'JB');
    });

    test('takes one letter from a single word', () {
      expect(initialsFor('Acme'), 'A');
    });

    test('uppercases', () {
      expect(initialsFor('ada lovelace'), 'AL');
    });

    test('strips punctuation and digits without dropping the word', () {
      expect(initialsFor('  ada   lovelace  '), 'AL');
      expect(initialsFor('(ada) [lovelace]'), 'AL');
      expect(initialsFor('7-Eleven Corp.'), 'EC');
    });

    test('returns null when the name carries no letters — a number-only '
        'identity like #0009 has no initials, and the caller picks its own '
        'fallback (entity icon on the header, "?" on a list row)', () {
      expect(initialsFor('#0009'), isNull);
      expect(initialsFor(''), isNull);
      expect(initialsFor('   '), isNull);
      expect(initialsFor('123 456'), isNull);
    });

    test('a hyphen separates words — first and last, as with spaces', () {
      expect(initialsFor('Brown-Mertz'), 'BM');
      expect(initialsFor('Jean-Luc Picard'), 'JP');
      expect(initialsFor('Mary Smith-Jones'), 'MJ');
      expect(initialsFor('Anne\u2011Marie'), 'AM');
      // A stray hyphen is not a word.
      expect(initialsFor('Acme -'), 'A');
      expect(initialsFor('- Acme'), 'A');
    });

    test('handles non-Latin scripts', () {
      expect(initialsFor('Ада Лавлейс'), 'АЛ');
      expect(initialsFor('田中 太郎'), '田太');
      expect(initialsFor('أحمد الفارسي'), 'أا');
    });
  });

  group('InitialsAvatar', () {
    testWidgets('renders the label on the seed-derived tint', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InitialsAvatar(seed: 'c1', label: 'AL'),
          ),
        ),
      );

      expect(find.text('AL'), findsOneWidget);

      final box = tester.widget<Container>(find.byType(Container));
      final decoration = box.decoration! as BoxDecoration;
      final tint = avatarTintFor(tester.element(find.text('AL')), 'c1');
      expect(decoration.color, tint.background);
      // The ink is the pair's, never white on a soft tint.
      expect(tester.widget<Text>(find.text('AL')).style!.color, tint.ink);
      // Rounded rectangle, never a circle or a pill.
      expect(decoration.shape, BoxShape.rectangle);
      expect(decoration.borderRadius, isNotNull);
    });

    // A wide list row keeps 5.1.30's look (docs/row-actions-and-values.md
    // § A wide row's avatar is solid); every other avatar keeps the tint.
    testWidgets('solid draws 5.1.30\'s swatch with white initials, in the '
        'tint\'s hue', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InitialsAvatar(seed: 'c1', label: 'AL', solid: true),
          ),
        ),
      );
      final decoration =
          tester.widget<Container>(find.byType(Container)).decoration!
              as BoxDecoration;
      final solid = avatarSolidFor('c1');
      expect(decoration.color, solid.background);
      expect(tester.widget<Text>(find.text('AL')).style!.color, Colors.white);
      // Same palette slot as the soft tint, so an entity keeps its hue.
      final index = avatarTintIndexFor('c1', InTheme.avatarSolids.length);
      expect(InTheme.avatarSolids[index], solid);
      expect(InTheme.avatarSolids.length, InTheme.light.avatarTints.length);
    });

    testWidgets('defaults to the 32px list metrics — the width the row leading '
        'slot reserves, at the long-standing 13pt', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InitialsAvatar(seed: 'c1', label: 'AL'),
          ),
        ),
      );

      expect(tester.getSize(find.byType(InitialsAvatar)), const Size(32, 32));
      expect(tester.widget<Text>(find.text('AL')).style!.fontSize, 13);
    });

    testWidgets('scales the text with an explicit size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InitialsAvatar(seed: 'c1', label: 'AL', size: 64),
          ),
        ),
      );

      expect(tester.getSize(find.byType(InitialsAvatar)), const Size(64, 64));
      expect(tester.widget<Text>(find.text('AL')).style!.fontSize, 26);
    });
  });
}
