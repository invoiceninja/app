import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/widgets/in_segmented.dart';

/// `docs/settings-screens.md` § The segmented picker.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool fill = false,
    ValueChanged<int>? onChanged,
    int selected = 1,
  }) async {
    Widget picker = InSegmented<int>(
      segments: const [
        InSegment(value: 0, label: 'One'),
        InSegment(value: 1, label: 'Two'),
        InSegment(value: 2, label: 'Three'),
      ],
      selected: selected,
      onChanged: onChanged,
    );
    if (fill) {
      picker = SizedBox(width: 360, child: InSegmentedFill(child: picker));
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: picker),
        ),
      ),
    );
  }

  double faceWidth(WidgetTester tester, String label) => tester
      .getSize(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      )
      .width;

  testWidgets('equal segments of kInSegmentWidth on a wide row', (
    tester,
  ) async {
    await pump(tester, onChanged: (_) {});
    final widths = {
      for (final l in ['One', 'Two', 'Three']) faceWidth(tester, l),
    };
    expect(widths, hasLength(1));
    // The track: three segments and its 3 px inset a side.
    expect(
      tester.getSize(find.byType(InSegmented<int>)).width,
      kInSegmentWidth * 3 + 6,
    );
  });

  testWidgets('under InSegmentedFill the segments share the line', (
    tester,
  ) async {
    await pump(tester, fill: true, onChanged: (_) {});
    expect(tester.getSize(find.byType(InSegmented<int>)).width, 360);
    final widths = {
      for (final l in ['One', 'Two', 'Three']) faceWidth(tester, l),
    };
    expect(widths, hasLength(1));
  });

  testWidgets('44 px tall on touch, denser with a pointer', (tester) async {
    await pump(tester, onChanged: (_) {});
    expect(
      tester.getSize(find.byType(InSegmented<int>)).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('shorter than the touch floor where the pointer is a mouse', (
    tester,
  ) async {
    await pump(tester, onChanged: (_) {});
    expect(tester.getSize(find.byType(InSegmented<int>)).height, lessThan(44));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a tap picks; a null onChanged disables every segment', (
    tester,
  ) async {
    int? picked;
    await pump(tester, onChanged: (v) => picked = v);
    await tester.tap(find.text('Three'));
    expect(picked, 2);

    await pump(tester);
    final button = tester.widget<SegmentedButton<int>>(
      find.byType(SegmentedButton<int>),
    );
    expect(button.onSelectionChanged, isNull);
  });

  testWidgets('the selected segment is announced as selected', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, onChanged: (_) {});
    expect(
      tester.getSemantics(find.text('Two')),
      isSemantics(label: 'Two', isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('One')),
      isSemantics(label: 'One', isSelected: false),
    );
    handle.dispose();
  });

  testWidgets('never a pill: an r2 track around r1 faces', (tester) async {
    await pump(tester, onChanged: (_) {});
    final track = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(InSegmented<int>),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (track.decoration as BoxDecoration).borderRadius,
      BorderRadius.circular(InRadii.r2),
    );
    final face = tester.widget<Container>(
      find
          .ancestor(of: find.text('Two'), matching: find.byType(Container))
          .first,
    );
    expect(
      (face.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(InRadii.r1),
    );
  });
}
