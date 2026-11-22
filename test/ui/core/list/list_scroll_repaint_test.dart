// Scrolling a list repaints its rows, never the screen around them.
//
// Counts the render objects painted on each scroll frame outside the list's
// sliver — the app bar, search field, status strip, table headers, the card —
// with the mouse resting over the rows, as it does during a wheel scroll on
// web and desktop. Two things used to repaint all of that on most frames:
//
// * a row's `setState` between frames (its client-name / currency stream
//   answering after the row first built, an `InkWell` or `CellCopyHover`
//   reacting to the mouse tracker's post-frame update) marked the nearest
//   `LayoutBuilder` — the screen's or the wide table's — for layout, and a
//   relayout repaints up to the nearest repaint boundary: the whole route;
// * a row's hover highlight was painted on the card's `Material`, above the
//   scroll view, so each fade frame repainted the page.
//
// docs/performance-tracking.md § Hover while scrolling repainted the page.
// Paint counts, not milliseconds: they do not move with the machine.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/api/invoice_api_model.dart';
import 'package:admin/ui/features/invoices/views/invoice_list_screen.dart';
import 'package:admin/ui/features/invoices/widgets/invoice_list_tile.dart';

import '../../../../benchmark/workloads.dart';
import '../../../_localization_helper.dart';
import '../../../_support/record_screen_harness.dart' show seedUsd;
import '../../features/shell/_shell_test_helpers.dart';

const _co = 'co1';

/// What a scroll frame may paint outside the rows, on average: the sliver
/// and its padding, the list's own fence and scroll chain. Measured 8–12 at
/// the fix; 100–190 before it.
const _maxChromePaintsPerFrame = 30;

void main() {
  for (final (label, size) in const [
    ('wide', Size(1440, 1000)),
    ('phone', Size(390, 844)),
  ]) {
    testWidgets('a $label scroll frame under a resting mouse repaints only '
        'the rows', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late ShellFixture fixture;
      await tester.runAsync(() async {
        fixture = await buildFixture(
          companies: const [FakeCompany(id: _co, name: 'Acme Ltd')],
          currentCompanyId: _co,
          closeStreamsSynchronously: true,
        );
        await seedUsd(fixture.services, companyId: _co);
        for (var i = 0; i < 40; i++) {
          await fixture.services.clients.applyUpdateResponse(
            companyId: _co,
            serverResponse: ClientApi.fromJson(clientJson(i)),
          );
        }
        for (var i = 0; i < 120; i++) {
          await fixture.services.invoices.applyUpdateResponse(
            companyId: _co,
            serverResponse: InvoiceApi.fromJson(invoiceJson(i)),
          );
        }
      });
      Future<void> settle(int rounds) async {
        for (var i = 0; i < rounds; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        Provider<Services>.value(
          value: fixture.services,
          child: MaterialApp(
            theme: buildInTheme(InTheme.light),
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: kTestSupportedLocales,
            home: const InvoiceListScreen(),
          ),
        ),
      );
      final tiles = find.byType(InvoiceListTile);
      for (var i = 0; i < 200 && tiles.evaluate().isEmpty; i++) {
        await settle(1);
      }
      expect(tiles, findsWidgets, reason: 'the list drew no rows');
      final position = tester
          .state<ScrollableState>(
            find
                .ancestor(of: tiles.first, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      // Off the top first and settled: leaving the top turns the app bar
      // scrolled-under, a deliberate one-off colour change — not under test.
      position.jumpTo(100);
      await settle(20);
      expect(
        position.maxScrollExtent - position.pixels,
        greaterThan(20 * 40 + 700),
        reason: 'too few rows to scroll without reaching load-more',
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(tiles.at(3)));
      await tester.pump(const Duration(milliseconds: 500));

      var chromePaints = 0;
      var rowPaints = 0;
      debugOnProfilePaint = (renderObject) {
        for (RenderObject? p = renderObject.parent; p != null; p = p.parent) {
          if (p is RenderSliverMultiBoxAdaptor) {
            rowPaints++;
            return;
          }
        }
        chromePaints++;
      };
      const frames = 20;
      try {
        for (var i = 0; i < frames; i++) {
          position.jumpTo(position.pixels + 40);
          await tester.pump(const Duration(milliseconds: 16));
        }
      } finally {
        debugOnProfilePaint = null;
      }
      expect(rowPaints, greaterThan(0), reason: 'no scroll frame painted');
      expect(
        chromePaints / frames,
        lessThan(_maxChromePaintsPerFrame),
        reason:
            'a scroll frame repainted the screen around the list '
            '($chromePaints objects in $frames frames) — a row is dirtying '
            'something above the list\'s build-scope fence, or its ink is '
            'painting on a Material outside the row',
      );

      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
      await tester.runAsync(
        () => fixture.dispose().timeout(const Duration(seconds: 30)),
      );
    }, semanticsEnabled: false);
  }
}
