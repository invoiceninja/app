import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/list_density_controller.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/ui/core/list/list_density_scope.dart';
import 'package:admin/ui/core/widgets/field_label.dart';

/// A Comfortable `LabeledField` draws an unbroken top border, and a Compact
/// one still notches it for its floating label (`docs/form-fields.md` § A
/// label above the box cuts no notch in its border).
///
/// The hidden label of a two-word name ("PO Number") lays out at `FLT_MIN`
/// wide, not 0, and a bare `OutlineInputBorder` cut an 8 px notch for it near
/// the start of the top edge. These tests read the painted pixels of that
/// edge, since the border's geometry is private to `InputDecorator`.
void main() {
  final platforms = TargetPlatformVariant(const {
    TargetPlatform.android,
    TargetPlatform.macOS,
  });

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

  const boundaryKey = Key('boundary');
  const label = 'PO Number';

  Future<void> pump(
    WidgetTester tester, {
    required bool dark,
    String text = '',
    String? error,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(dark ? InTheme.dark : InTheme.light),
        builder: (context, inner) =>
            ListDensityScope(controller: density, child: inner!),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundaryKey,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: 240,
                  child: LabeledField(
                    label: label,
                    child: TextField(
                      enabled: enabled,
                      controller: TextEditingController(text: text),
                      decoration: InputDecoration(
                        labelText: label,
                        errorText: error,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> focus(WidgetTester tester) async {
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
  }

  /// How many pixels along the top edge of the field's box, between its
  /// corners, are not the colour its left edge is painted in — the notch.
  Future<int> topEdgeGap(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final origin = tester.getTopLeft(find.byKey(boundaryKey));
    final box = tester.getRect(find.byType(InputDecorator)).shift(-origin);
    final (bytes, width) = (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData();
      final width = image.width;
      image.dispose();
      return (data!, width);
    }))!;
    Color at(int x, int y) {
      final i = (y * width + x) * 4;
      return Color.fromARGB(
        bytes.getUint8(i + 3),
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
    }

    double distance(Color a, Color b) =>
        (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

    // The decorator's own height includes the error line under the box; the
    // box is the top 40-odd px. Its mid-height row is well inside it.
    final top = box.top.floor();
    final midY = top + 20;
    // The fill, read in the content padding above the value's line.
    final fill = at(box.left.round() + 30, top + 4);
    // The left edge's stroke is the border's colour in this state.
    final left = box.left.floor();
    final edge = [
      at(left, midY),
      at(left + 1, midY),
    ].reduce((a, b) => distance(a, fill) >= distance(b, fill) ? a : b);
    expect(
      distance(edge, fill),
      greaterThan(0.02),
      reason: 'the border should be visible against the fill',
    );

    const radius = InRadii.r2;
    var gap = 0;
    for (
      var x = (box.left + radius + 2).ceil();
      x < (box.right - radius - 2).floor();
      x++
    ) {
      final painted = [top, top + 1].any((y) {
        final p = at(x, y);
        return distance(p, edge) < distance(p, fill);
      });
      if (!painted) gap++;
    }
    return gap;
  }

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    group('Comfortable ($theme): the top edge is whole', () {
      testWidgets('empty', (tester) async {
        await pump(tester, dark: dark);
        // What the fix leans on: the hidden label is under a pixel wide
        // (it measures FLT_MIN here, as on device), never a real width.
        expect(
          tester.getSize(find.text(label)).width,
          lessThan(kMinFieldLabelGap),
        );
        expect(await topEdgeGap(tester), 0);
      }, variant: platforms);

      testWidgets('with a value', (tester) async {
        await pump(tester, dark: dark, text: '0025');
        expect(await topEdgeGap(tester), 0);
      }, variant: platforms);

      testWidgets('focused', (tester) async {
        await pump(tester, dark: dark, text: '0025');
        await focus(tester);
        expect(await topEdgeGap(tester), 0);
      }, variant: platforms);

      testWidgets('with an error', (tester) async {
        await pump(tester, dark: dark, error: 'Required');
        expect(await topEdgeGap(tester), 0);
      }, variant: platforms);

      testWidgets('disabled', (tester) async {
        await pump(tester, dark: dark, text: 'x', enabled: false);
        expect(await topEdgeGap(tester), 0);
      }, variant: platforms);
    });

    group('Compact ($theme): the floating label keeps its notch', () {
      testWidgets('with a value', (tester) async {
        await density.setCompact(true);
        await pump(tester, dark: dark, text: '0025');
        // More than the 8 px of gap padding alone: a label-wide notch. (A
        // focused label is painted in the accent, the border's own colour,
        // so only its padding and the gaps between glyphs count there.)
        expect(await topEdgeGap(tester), greaterThan(8));
      }, variant: platforms);

      testWidgets('focused and empty', (tester) async {
        await density.setCompact(true);
        await pump(tester, dark: dark);
        await focus(tester);
        expect(await topEdgeGap(tester), greaterThan(8));
      }, variant: platforms);
    });
  }

  group('InFieldOutlineBorder', () {
    Future<int> paintedGap(double extent) async {
      const border = InFieldOutlineBorder(
        borderSide: BorderSide(color: Color(0xFF000000)),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawColor(const Color(0xFFFFFFFF), BlendMode.src);
      border.paint(
        canvas,
        const Rect.fromLTWH(0, 0, 100, 40),
        gapStart: 12,
        gapExtent: extent,
        gapPercentage: 1,
        textDirection: TextDirection.ltr,
      );
      final image = await recorder.endRecording().toImage(100, 40);
      final ByteData data = (await image.toByteData())!;
      image.dispose();
      var gap = 0;
      for (var x = 8; x < 92; x++) {
        if (data.getUint8(x * 4) > 128) gap++;
      }
      return gap;
    }

    test('draws the whole edge for a sub-pixel label', () async {
      expect(await paintedGap(1.1754943508222875e-38), 0);
      expect(await paintedGap(0.5), 0);
    });

    test('cuts the notch for a real label', () async {
      expect(await paintedGap(30), inInclusiveRange(36, 40));
    });

    test('stays itself through copyWith, scale and lerp', () {
      const a = InFieldOutlineBorder();
      final b = InFieldOutlineBorder(
        borderSide: const BorderSide(width: 1.5),
        borderRadius: BorderRadius.circular(6),
      );
      expect(a.copyWith(gapPadding: 2), isA<InFieldOutlineBorder>());
      expect(a.scale(2), isA<InFieldOutlineBorder>());
      expect(ShapeBorder.lerp(a, b, 0.5), isA<InFieldOutlineBorder>());
      expect(
        ShapeBorder.lerp(const OutlineInputBorder(), b, 0.5),
        isA<InFieldOutlineBorder>(),
      );
    });
  });
}
