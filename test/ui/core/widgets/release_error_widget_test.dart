import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/version.dart';
import 'package:admin/ui/core/widgets/release_error_widget.dart';

FlutterErrorDetails _details([Object? exception]) => FlutterErrorDetails(
  exception: exception ?? StateError('boom at the root'),
  stack: StackTrace.fromString('#0 main (file.dart:1:1)\n#1 run (x.dart:2:2)'),
);

class _Throws extends StatelessWidget {
  const _Throws();
  @override
  Widget build(BuildContext context) => throw StateError('build failed');
}

void main() {
  late ErrorWidgetBuilder priorBuilder;
  setUp(() => priorBuilder = ErrorWidget.builder);

  testWidgets('at the root, with no app above it, names the error', (
    tester,
  ) async {
    // No MaterialApp, Theme, Localization, Directionality or MediaQuery:
    // what a failure above the app sees (invoiceninja/app#211).
    await tester.pumpWidget(ReleaseErrorWidget(details: _details()));

    expect(find.text('An error occurred'), findsOneWidget);
    expect(find.textContaining('boom at the root'), findsOneWidget);
    expect(find.text('Copy Error'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Copy Error puts the version, error and stack on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(ReleaseErrorWidget(details: _details()));
    await tester.tap(find.text('Copy Error'));
    await tester.pump();

    expect(copied, contains('Invoice Ninja ${AppVersion.kClientVersion}'));
    expect(copied, contains('boom at the root'));
    expect(copied, contains('#0 main'));
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byIcon(Icons.copy), findsOneWidget);
  });

  testWidgets('a box smaller than the panel shows nothing but its fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 200,
          height: 40,
          child: ReleaseErrorWidget(details: _details()),
        ),
      ),
    );

    expect(find.text('An error occurred').hitTestable(), findsNothing);
    expect(find.text('Copy Error').hitTestable(), findsNothing);
    // Nor can focus reach the button nobody can see.
    await tester.pump();
    expect(_copyFocusExcluded(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shown panel lets focus reach Copy Error', (tester) async {
    await tester.pumpWidget(ReleaseErrorWidget(details: _details()));
    await tester.pump();
    expect(_copyFocusExcluded(tester), isFalse);
  });

  testWidgets('in a scrollable, the panel is on screen, not 50000 px down', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [ReleaseErrorWidget(details: _details())]),
        ),
      ),
    );

    expect(tester.getSize(find.byType(ReleaseErrorWidget)).height, 360);
    expect(find.text('Copy Error').hitTestable(), findsOneWidget);
  });

  testWidgets('is safe in a scrollable and under an IntrinsicHeight', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ReleaseErrorWidget(details: _details()),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(child: ReleaseErrorWidget(details: _details())),
                    const Text('beside'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('installed as the builder, a widget that throws shows it', (
    tester,
  ) async {
    ErrorWidget.builder = releaseErrorWidgetBuilder;
    try {
      await tester.pumpWidget(const MaterialApp(home: _Throws()));

      expect(tester.takeException(), isA<StateError>());
      expect(find.text('An error occurred').hitTestable(), findsOneWidget);
      expect(find.textContaining('build failed'), findsOneWidget);
    } finally {
      // flutter_test fails a test that leaves the builder changed.
      ErrorWidget.builder = priorBuilder;
    }
  });
}

bool _copyFocusExcluded(WidgetTester tester) => tester
    .widget<ExcludeFocus>(
      find.ancestor(
        of: find.text('Copy Error'),
        matching: find.byType(ExcludeFocus),
      ),
    )
    .excluding;
