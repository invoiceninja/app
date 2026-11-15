import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/detail/entity_detail_header.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';

import '../../../_localization_helper.dart';

/// Regression cover for the avatar fallback: a number-only identity (`#0009`,
/// the task/invoice/payment case) yields no initials, so the avatar must show
/// the entity-type icon rather than a bare `?`. Named entities keep initials.

Widget _host(Widget child) => MaterialApp(
  theme: buildInTheme(InTheme.light),
  localizationsDelegates: kTestLocalizationsDelegates,
  supportedLocales: kTestSupportedLocales,
  home: Scaffold(body: Center(child: child)),
);

EntityDetailHeader _header({
  required String displayName,
  IconData? fallbackIcon,
  String? number,
  String? copyName,
  Widget? subtitle,
}) => EntityDetailHeader(
  seedForAvatar: 'seed',
  displayName: displayName,
  copyName: copyName,
  subtitle: subtitle,
  number: number,
  // Epoch-0 timestamps + null formatter render the subtitle as empty, so
  // the header needs no Formatter wiring for these avatar-focused checks.
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  isDeleted: false,
  isArchived: false,
  isDirty: false,
  fallbackIcon: fallbackIcon,
);

void main() {
  testWidgets('number-only identity shows the entity icon, not "?"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_header(displayName: '#0009', fallbackIcon: Icons.task)),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.task), findsOneWidget);
    expect(find.text('?'), findsNothing);
  });

  testWidgets('named identity shows tinted initials, no icon', (tester) async {
    await tester.pumpWidget(
      _host(_header(displayName: 'John Lennon', fallbackIcon: Icons.task)),
    );
    await tester.pumpAndSettle();

    expect(find.text('JL'), findsOneWidget);
    expect(find.byIcon(Icons.task), findsNothing);
  });

  testWidgets('number-only identity with no fallback icon keeps the "?" '
      'placeholder', (tester) async {
    await tester.pumpWidget(_host(_header(displayName: '#0009')));
    await tester.pumpAndSettle();

    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('desktop: copyable #number renders inside the baseline row '
      'with no layout error', (tester) async {
    // The header number gets a CopyableValue (copies the bare number). On
    // desktop that wraps the text in a Row + hover icon inside the header's
    // baseline-aligned Row — guard against a baseline/layout regression.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        _host(_header(displayName: 'John Lennon', number: '0009')),
      );
      await tester.pumpAndSettle();

      expect(find.text('#0009'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('the headline copies the record name', () {
    String? copied;
    setUp(() {
      copied = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('touch: a tap copies copyName, not the decorated headline', (
      tester,
    ) async {
      // A payment is headed `#0009`; what is pasted is `0009`.
      await tester.pumpWidget(
        _host(_header(displayName: '#0009', copyName: '0009')),
      );
      await tester.tap(find.text('#0009'));
      await tester.pumpAndSettle();
      expect(copied, '0009');
    });

    testWidgets('a placeholder headline (no copyName) is not copyable', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_header(displayName: '(no name)')));
      await tester.tap(find.text('(no name)'));
      await tester.pumpAndSettle();
      expect(copied, isNull);
    });

    testWidgets('desktop: hover shows the icon, in a reserved slot under a '
        'subtitle and floating beside an inline number', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        Future<void> hoverName() async {
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await gesture.addPointer(location: Offset.zero);
          addTearDown(gesture.removePointer);
          await gesture.moveTo(tester.getCenter(find.text('Acme Corp')));
          await tester.pumpAndSettle();
        }

        // With a subtitle nothing follows the name: the slot is in the row.
        await tester.pumpWidget(
          _host(
            _header(
              displayName: 'Acme Corp',
              copyName: 'Acme Corp',
              subtitle: const Text('Berlin'),
            ),
          ),
        );
        expect(find.byType(CopyIconButton), findsOneWidget);
        await hoverName();
        await tester.tap(find.byType(CopyIconButton));
        await tester.pumpAndSettle();
        expect(copied, 'Acme Corp');
        expect(tester.takeException(), isNull);

        // Beside an inline `#number` it floats: no gap between the two.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          _host(
            _header(
              displayName: 'Acme Corp',
              copyName: 'Acme Corp',
              number: '0042',
            ),
          ),
        );
        expect(
          tester.getTopLeft(find.text('#0042')).dx -
              tester.getTopRight(find.text('Acme Corp')).dx,
          InSpacing.sm,
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('subtitle, tags and state pills', () {
    EntityDetailHeader header({
      Widget? subtitle,
      Widget? tags,
      bool isDeleted = false,
      bool isDirty = false,
      bool showStatePills = true,
      int nameMaxLines = 1,
      String name = 'Acme Corporation',
    }) => EntityDetailHeader(
      seedForAvatar: 'seed',
      displayName: name,
      number: '0042',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      isDeleted: isDeleted,
      isArchived: false,
      isDirty: isDirty,
      subtitle: subtitle,
      tags: tags,
      showStatePills: showStatePills,
      nameMaxLines: nameMaxLines,
    );

    testWidgets('a subtitle takes the number out of the name row', (
      tester,
    ) async {
      // The host puts the number in the subtitle instead, so a long name gets
      // the whole first line. Without a subtitle nothing changes.
      await tester.pumpWidget(_host(header()));
      expect(find.text('#0042'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          header(subtitle: const DetailSubtitle(segments: [Text('Berlin')])),
        ),
      );
      expect(find.text('#0042'), findsNothing);
      expect(find.text('Berlin'), findsOneWidget);
    });

    testWidgets('subtitle segments are joined, and none means nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const DetailSubtitle(segments: [Text('Berlin'), Text('#0042')])),
      );
      expect(
        tester.getTopLeft(find.text('#0042')).dx,
        greaterThan(tester.getTopRight(find.text('Berlin')).dx),
        reason: 'a separator sits between them',
      );
      await tester.pumpWidget(_host(const DetailSubtitle(segments: [])));
      expect(tester.getSize(find.byType(DetailSubtitle)), Size.zero);
    });

    testWidgets('tags render under the subtitle', (tester) async {
      await tester.pumpWidget(
        _host(
          header(
            subtitle: const DetailSubtitle(segments: [Text('Berlin')]),
            tags: const Text('VIP'),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('VIP')).dy,
        greaterThan(tester.getTopLeft(find.text('Berlin')).dy),
      );
    });

    testWidgets('a long name may wrap when the host allows it', (tester) async {
      const long = 'International Business Machines Corporation of Armonk';
      Future<double> heightAt(int lines) async {
        await tester.binding.setSurfaceSize(const Size(360, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_host(header(name: long, nameMaxLines: lines)));
        return tester.getSize(find.text(long)).height;
      }

      final one = await heightAt(1);
      final two = await heightAt(2);
      expect(two, greaterThan(one));
    });

    testWidgets('a banner can take over the lifecycle pill, not Unsynced', (
      tester,
    ) async {
      await tester.pumpWidget(_host(header(isDeleted: true, isDirty: true)));
      expect(find.text('Deleted'), findsOneWidget);

      await tester.pumpWidget(
        _host(header(isDeleted: true, isDirty: true, showStatePills: false)),
      );
      // The screen says Deleted in a banner; the same word in a pill under it
      // is noise. Unsynced is not a lifecycle state and no banner repeats it.
      expect(find.text('Deleted'), findsNothing);
      expect(find.text('Unsynced'), findsOneWidget);
    });
  });
}
