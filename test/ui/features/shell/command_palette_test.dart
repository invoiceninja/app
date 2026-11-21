import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/entity_modules.dart' show DisabledEntityDispatcher;
import 'package:admin/data/models/domain/search_result.dart';
import 'package:admin/domain/entity_registry.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/ui/core/widgets/key_cap.dart';
import 'package:admin/ui/features/shell/widgets/company_picker.dart';
import 'package:admin/ui/features/settings/settings_search_catalog.dart';
import 'package:admin/ui/features/shell/widgets/command_palette.dart';
import 'package:admin/ui/features/shell/widgets/search_palette_scope_bar.dart';

import '../../../_localization_helper.dart';
import '_shell_test_helpers.dart';

void main() {
  group('entityTypeForSearchGroup', () {
    test('maps every entity search group to its EntityType', () {
      expect(entityTypeForSearchGroup('clients'), EntityType.client);
      expect(entityTypeForSearchGroup('client_contacts'), EntityType.client);
      expect(entityTypeForSearchGroup('invoices'), EntityType.invoice);
      expect(entityTypeForSearchGroup('quotes'), EntityType.quote);
      expect(entityTypeForSearchGroup('credits'), EntityType.credit);
      expect(entityTypeForSearchGroup('payments'), EntityType.payment);
      expect(
        entityTypeForSearchGroup('recurrings'),
        EntityType.recurringInvoice,
      );
      expect(
        entityTypeForSearchGroup('recurring_invoices'),
        EntityType.recurringInvoice,
      );
      expect(entityTypeForSearchGroup('projects'), EntityType.project);
      expect(entityTypeForSearchGroup('tasks'), EntityType.task);
      expect(entityTypeForSearchGroup('products'), EntityType.product);
      expect(entityTypeForSearchGroup('expenses'), EntityType.expense);
      expect(entityTypeForSearchGroup('vendors'), EntityType.vendor);
      expect(entityTypeForSearchGroup('vendor_contacts'), EntityType.vendor);
    });

    test('purchase orders route through the registry, not the raw path', () {
      // Without this the group fell through to `context.go(r.path)`, skipping
      // the module + permission gate every other entity hit goes through.
      expect(
        entityTypeForSearchGroup('purchase_orders'),
        EntityType.purchaseOrder,
      );
    });

    test('settings + unknown groups → null (caller uses server path)', () {
      expect(entityTypeForSearchGroup('settings'), isNull);
      expect(entityTypeForSearchGroup('whatever'), isNull);
      expect(entityTypeForSearchGroup(''), isNull);
    });
  });

  group('deepLinkSearchHit — pasting a shared link', () {
    final registry = EntityRegistry({
      EntityType.client: EntityHandlers(
        type: EntityType.client,
        wireName: 'client',
        apiPath: '/api/v1/clients',
        routePath: '/clients',
        icon: Icons.circle,
        dispatcher: DisabledEntityDispatcher(EntityType.client),
        detailBuilder: (_, _) => const SizedBox.shrink(),
      ),
    });

    test('resolves a pasted record link to one hit', () {
      final hit = deepLinkSearchHit(
        '  invoiceninja://app/clients/abc?company=co1  ',
        registry,
      );
      expect(hit, isNotNull);
      expect(hit!.group, kDeepLinkSearchGroup);
      expect(hit.name, '/clients/abc');
      // The ORIGINAL uri, not the resolved route — activation hands it back to
      // DeepLinkRouter so a cross-company link still switches company.
      expect(hit.path, 'invoiceninja://app/clients/abc?company=co1');
    });

    test('resolves the https form too — the shape Copy Link now emits, and '
        'the only way a colleague on Linux or web follows one at all', () {
      final hit = deepLinkSearchHit(
        'https://invoicing.co/app/clients/abc?company=co1',
        registry,
      );
      expect(hit, isNotNull);
      expect(hit!.name, '/clients/abc');
      expect(hit.path, 'https://invoicing.co/app/clients/abc?company=co1');
    });

    test('ignores ordinary search text', () {
      expect(deepLinkSearchHit('acme corp', registry), isNull);
      expect(deepLinkSearchHit('', registry), isNull);
      expect(deepLinkSearchHit('https://example.test', registry), isNull);
    });

    test('ignores a link this build cannot route', () {
      expect(
        deepLinkSearchHit('invoiceninja://app/widgets/x', registry),
        isNull,
      );
    });
  });

  group('recordIdForSearchHit', () {
    SearchResult hit(
      String group, {
      required String id,
      required String path,
    }) => SearchResult(group: group, name: 'x', id: id, path: path);

    test('contact hits route by the PARENT id from `path`, not their own', () {
      // Elasticsearch branch: `id` is the CONTACT's hashed id, `path` carries
      // the parent. Routing by `id` opened a client that doesn't exist.
      expect(
        recordIdForSearchHit(
          hit('client_contacts', id: 'CONTACT9', path: '/clients/CLIENT1'),
        ),
        'CLIENT1',
      );
      expect(
        recordIdForSearchHit(
          hit('vendor_contacts', id: 'CONTACT9', path: '/vendors/VENDOR1'),
        ),
        'VENDOR1',
      );
    });

    test('non-ES fallback shape resolves identically', () {
      // `clientMap` puts the parent id in BOTH fields, so one code path covers
      // either backend.
      expect(
        recordIdForSearchHit(
          hit('client_contacts', id: 'CLIENT1', path: '/clients/CLIENT1'),
        ),
        'CLIENT1',
      );
    });

    test('degrades to `id` when the path is unusable', () {
      expect(
        recordIdForSearchHit(hit('client_contacts', id: 'FALLBACK', path: '')),
        'FALLBACK',
      );
      expect(
        recordIdForSearchHit(hit('client_contacts', id: 'FALLBACK', path: '/')),
        'FALLBACK',
      );
    });

    test('non-contact groups keep their own id', () {
      expect(
        recordIdForSearchHit(
          hit('clients', id: 'CLIENT1', path: '/clients/CLIENT1'),
        ),
        'CLIENT1',
      );
      // Invoices carry `/invoices/{id}/edit`; the trailing segment is NOT an id.
      expect(
        recordIdForSearchHit(
          hit('invoices', id: 'INV1', path: '/invoices/INV1/edit'),
        ),
        'INV1',
      );
    });
  });

  group('settings hits are served locally', () {
    test('SearchResult.isSettings identifies the group the palette drops', () {
      expect(
        const SearchResult(
          group: 'settings',
          name: 'x',
          id: '',
          path: '/settings/subscriptions',
        ).isSettings,
        isTrue,
      );
      expect(
        const SearchResult(
          group: 'clients',
          name: 'x',
          id: 'a',
          path: '/clients/a',
        ).isSettings,
        isFalse,
      );
    });

    test('every catalog section route is a registered app route', () {
      // The palette now navigates `hit.section.route`, so an unroutable entry
      // would reproduce the very dead-end this replaced — and `errorBuilder`
      // is registered at the ROOT, so it takes the whole shell down with it.
      final routes = File(
        'lib/ui/features/settings/settings_routes.dart',
      ).readAsStringSync();
      final modules = File('lib/app/entity_modules.dart').readAsStringSync();
      final registered =
          RegExp(
              r"path: '([a-z_]+)'",
            ).allMatches(routes).map((m) => m.group(1)!).toSet()
            ..addAll(
              RegExp(
                r"_leaf\(\s*'([a-z_/]+)'",
              ).allMatches(routes).map((m) => m.group(1)!),
            )
            ..addAll(
              RegExp(
                r"routePath: '/settings/([a-z_/]+)'",
              ).allMatches(modules).map((m) => m.group(1)!),
            );

      final sections = {for (final s in kSettingsSections) s.slug: s.route};
      expect(sections, isNotEmpty);
      final unroutable = [
        for (final entry in sections.entries)
          if (!registered.contains(entry.key)) '${entry.key} → ${entry.value}',
      ];
      expect(
        unroutable,
        isEmpty,
        reason:
            'These settings sections are reachable from the command palette '
            'but have no registered route:\n  ${unroutable.join('\n  ')}',
      );
    });
  });

  // Issue #101 was "poor information density" about the sidebar's Search box.
  // The palette it opens had the same defect on the same device: three
  // keyboard-only affordances rendered unconditionally, including the `Ctrl/`
  // chip visible in the reporter's Android screenshot. Scanned rather than
  // pumped — these assert the *shape* of the source, which a pumped test can
  // only observe indirectly.
  group('phone chrome (issue #101)', () {
    // Comments stripped: these scans assert what the widget *does*, and the
    // prose explaining a guard names the very identifiers the guard forbids —
    // the `_onChanged` check below first went red against the comment that
    // documents why the close button must not call it.
    final palette = File('lib/ui/features/shell/widgets/command_palette.dart')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('both hint spread sites are gated on touch', () {
      // The footer is one `_keyboardHints` definition spread twice, so the
      // check is a short marker per site — the earlier version scanned a fixed
      // 900-char window back from each hint literal against an actual distance
      // of 604, i.e. ~300 chars of slack before a couple of added comment
      // lines turned CI red with no behaviour change.
      final spreads = RegExp(
        r'\.\.\._keyboardHints\(',
      ).allMatches(palette).toList();
      expect(
        spreads,
        hasLength(2),
        reason: 'the hints render under both the results and recents lists',
      );
      for (final m in spreads) {
        expect(
          palette.substring(m.start - 20, m.start).contains('if (!touch)'),
          isTrue,
          reason:
              'a keyboard hint row still renders on a touch device, where '
              'none of the arrow / Enter / Esc keys can be pressed — and a '
              'narrow desktop window, which gets the page, must keep it',
        );
      }
      expect(
        RegExp(r"'Esc'").allMatches(palette),
        hasLength(1),
        reason:
            'one definition, two spread sites — a second literal means the '
            'block was copied back and the two states can now diverge',
      );
    });

    test('the card keeps its keycap and its touch-gated close button', () {
      // `_buildField`'s `phone: false` half is the tablet/desktop card. The
      // close button is gated on touch rather than on `!isPhone`: a tablet
      // mounts the sidebar's Search box on `Env.isTouchPrimary` but is not
      // `isPhone`, so it lands on the card and needs a visible way out.
      final suffix = palette.indexOf('suffixIcon:');
      expect(suffix, isNot(-1));
      final slot = palette.substring(suffix, suffix + 2000);

      expect(
        slot.contains('KeyCapRow('),
        isTrue,
        reason:
            'one cap per glyph — `[Ctrl][/]`, never a single `Ctrl/` cap '
            '(invoiceninja/flutter#103)',
      );
      // Scoped to the chip, NOT `slot`: the close button four lines later
      // legitimately dims its icon with the same token.
      final chip = palette.substring(
        suffix,
        palette.indexOf('if (touch)', suffix),
      );
      expect(
        chip.contains('tokens.ink3'),
        isFalse,
        reason:
            'the chip uses the default cap ink like every other KeyCap in '
            'the app; it was the only dimmed one',
      );
      expect(
        slot.contains('if (touch)'),
        isTrue,
        reason:
            'the close button is gated on touch, not isPhone: a tablet can '
            'reach this card and needs a visible way out of it',
      );
      expect(slot.contains('Icons.close'), isTrue);
    });

    test('the card close button closes — it never doubles as a clear', () {
      // Scoped to the FIRST `Icons.close`, which is `_buildField`'s card
      // branch. The phone page's second one is the clear button, which
      // legitimately calls `_controller.clear()` — through `_reset`, never
      // through `_onChanged`.
      final close = palette.indexOf('Icons.close');
      expect(close, isNot(-1));
      final button = palette.substring(close, close + 1200);

      expect(
        button.contains('Navigator.of(context).pop()'),
        isTrue,
        reason: 'tapping it must always leave the palette',
      );
      // Clearing through `_onChanged('')` arms the debounce into `_run('')`,
      // and `SearchApi.search` omits the `search` param for a blank query, so
      // the server answers with an unfiltered page (up to 1000 clients) under
      // an empty field instead of the Recents list.
      expect(
        button.contains('_onChanged'),
        isFalse,
        reason: 'a clear must reset _results/_selected itself, not refetch',
      );
      expect(
        button.contains('_controller.clear()'),
        isFalse,
        reason: 'this button closes; clearing is the phone page\'s job',
      );
    });

    test('clearing bumps the request sequence, not just the debounce', () {
      // Cancelling `_debounce` does nothing to a request already in flight:
      // `_run` only discards a late response via `seq != _reqSeq`. Without the
      // bump, tapping clear mid-flight repopulates the list under an empty
      // field.
      final reset = palette.indexOf('void _reset() {');
      expect(reset, isNot(-1));
      final body = palette.substring(reset, reset + 400);
      expect(body.contains('_debounce?.cancel()'), isTrue);
      expect(body.contains('_reqSeq++'), isTrue);
    });
  });

  // Issue #102: the palette floated over the screen behind it through a
  // 0.18 scrim, and on a phone that screen is an entity list whose own search
  // box is pinned in the app bar — two search fields ~20 px apart. These are
  // pumped, not scanned: what changed is the presentation, and the gate needs
  // a real viewport (`flutter test`'s default 800x600 has shortestSide == 600,
  // so `isPhone` is false out of the box) plus a real target platform.
  group('the phone palette is a page, not a card (issue #102)', () {
    late ShellFixture fixture;

    setUp(() async {
      fixture = await buildFixture(
        companies: const [FakeCompany(id: 'c1', name: 'Acme')],
      );
    });

    tearDown(() async => fixture.dispose());

    const phone = Size(412, 915);
    const desktop = Size(1200, 800);

    /// Opens the palette at [size] on [platform] and runs [body] against it.
    ///
    /// The platform override is set *before* `pumpWidget` (`wrapWithShell`
    /// bakes `ThemeData`'s platform in at build time) and cleared in a
    /// `finally` — `flutter_test` verifies the foundation debug vars at the
    /// end of the test *body*, before any `addTearDown` callback runs, so a
    /// tear-down reset is too late and fails every test that sets one.
    ///
    /// `tester.view.physicalSize`, not `setSurfaceSize`: `WidgetsApp` inserts
    /// its own `MediaQuery.fromView` inside `MaterialApp`, so a surface-size
    /// override never reaches `Breakpoints.isPhone` — the test would silently
    /// exercise the desktop branch and pass.
    Future<void> withPalette(
      WidgetTester tester, {
      required Size size,
      required TargetPlatform platform,
      required Future<void> Function() body,
    }) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          wrapWithShell(
            fixture.services,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showCommandPalette(context),
                child: const Text('trigger'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('fills the viewport, so nothing shows through behind it', (
      tester,
    ) async {
      await withPalette(
        tester,
        size: phone,
        platform: TargetPlatform.android,
        body: () async {
          expect(find.byType(Dialog), findsOneWidget);
          // Measure the Scaffold, NOT the Dialog: `Dialog` renders an
          // `AnimatedPadding` wrapping an `Align`, so its own box is the full
          // screen on *either* branch and asserting on it passes vacuously
          // against the card (verified by forcing the card branch).
          final surface = find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scaffold),
          );
          expect(
            surface,
            findsOneWidget,
            reason: 'the phone presentation is a page: Scaffold + AppBar',
          );
          expect(
            tester.getSize(surface),
            phone,
            reason:
                'a card that shrink-wraps to its field leaves the list — and '
                'the list\'s own pinned search box — legible behind the '
                'scrim (#102)',
          );
        },
      );
    });

    testWidgets('paints under the notch, and the strips are not a barrier', (
      tester,
    ) async {
      // The one assertion that pins `useSafeArea: false`. Left at the default
      // the surface stops below the status bar and that strip stays bare
      // `ModalBarrier` — the page showing through exactly where the list's
      // title sits, and (the barrier being dismissible) a tap beside the
      // gesture bar closing the page. Physical px; devicePixelRatio is 1.0.
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPadding);

      await withPalette(
        tester,
        size: phone,
        platform: TargetPlatform.android,
        body: () async {
          final surface = find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scaffold),
          );
          expect(
            tester.getSize(surface),
            phone,
            reason: 'the page owns the insets, not a SafeArea above it',
          );
          expect(
            tester.getTopLeft(surface),
            Offset.zero,
            reason: 'edge to edge — the AppBar supplies the status-bar pad',
          );
        },
      );
    });

    testWidgets('carries a back arrow that closes it, and no keycap', (
      tester,
    ) async {
      await withPalette(
        tester,
        size: phone,
        platform: TargetPlatform.android,
        body: () async {
          expect(
            find.byType(KeyCap),
            findsNothing,
            reason: 'no keyboard to press ⌘/ on',
          );
          expect(find.byIcon(Icons.arrow_back), findsOneWidget);
          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
        },
      );
    });

    testWidgets('names what it searches, rather than just "Search"', (
      tester,
    ) async {
      await withPalette(
        tester,
        size: phone,
        platform: TargetPlatform.android,
        body: () async {
          // The reporter's users read a lone magnifier as "search *this
          // page*". `search_placeholder` is a real Transifex key, so this
          // keeps its translation.
          expect(find.text('Find invoices, clients, and more'), findsOneWidget);
        },
      );
    });

    testWidgets('clear empties the field without closing the page', (
      tester,
    ) async {
      await withPalette(
        tester,
        size: phone,
        platform: TargetPlatform.android,
        body: () async {
          await tester.enterText(find.byType(TextField), 'acme');
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.close), findsOneWidget);

          await tester.tap(find.byIcon(Icons.close));
          await tester.pumpAndSettle();
          expect(
            find.byIcon(Icons.close),
            findsNothing,
            reason: 'the clear action only exists while the field has text',
          );
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller?.text,
            isEmpty,
          );
          expect(
            find.byType(Dialog),
            findsOneWidget,
            reason: 'clear clears; it must not double as a close',
          );
        },
      );
    });

    // A foldable opening while the palette is up flips `isPhone`, and the
    // swap from the page to the card remounted the palette — the query and its
    // results went with it (docs/foldables.md). One key holds it across both.
    testWidgets('keeps its query when a fold flips page ⇄ card', (
      tester,
    ) async {
      await withPalette(
        tester,
        size: phone,
        platform: TargetPlatform.android,
        body: () async {
          await tester.enterText(find.byType(TextField), 'acme');
          await tester.pump();
          for (final size in const [Size(951, 669), phone]) {
            tester.view.physicalSize = size;
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsOneWidget);
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller?.text,
              'acme',
              reason: 'the palette remounted at $size',
            );
          }
        },
      );
    });

    // #103: the field's `⌘ /` chip was a bordered mono keycap while the row
    // directly under it was flat sans text joined by `·` — two treatments of
    // one idea ~40 px apart. These pin the footer's new shape, and the gate
    // that keeps a louder hint from claiming a key that does nothing.
    testWidgets('the footer only offers keys that currently do something', (
      tester,
    ) async {
      await withPalette(
        tester,
        size: desktop,
        platform: TargetPlatform.macOS,
        body: () async {
          // Inside the debounce window nothing is up yet: `_move` and
          // `_select` have nothing to act on. Plain `pump`, never
          // `pumpAndSettle`: the running LinearProgressIndicator would hang
          // it for the 10-minute timeout.
          await tester.enterText(find.byType(TextField), 'acme');
          await tester.pump();

          expect(
            find.text('No records found'),
            findsNothing,
            reason: 'a search on its way is not an empty one — no flash',
          );
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(
            find.text('Navigate'),
            findsNothing,
            reason: 'there is nothing to move through',
          );
          expect(find.text('Select'), findsNothing);
          expect(
            find.text('Close'),
            findsOneWidget,
            reason: 'Esc still works, so it is still offered',
          );
          // The 2 field-chip caps plus Esc.
          expect(find.byType(KeyCap), findsNWidgets(3));

          // `buildFixture` installs a fail-fast client, so the search
          // rejects: no match, and the lists to search instead — rows that
          // ↑↓ and Enter do act on.
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump();
          expect(find.text('No records found'), findsOneWidget);
          expect(find.textContaining('Search Clients for'), findsOneWidget);
          expect(find.text('Navigate'), findsOneWidget);
          expect(find.text('Select'), findsOneWidget);
        },
      );
    });

    testWidgets('a populated footer is keycaps, with no middot separators', (
      tester,
    ) async {
      await withPalette(
        tester,
        size: desktop,
        platform: TargetPlatform.macOS,
        body: () async {
          // A pasted deep link resolves locally in `_run` — synchronous
          // results with no network and no recents timer to drain.
          await tester.enterText(
            find.byType(TextField),
            'invoiceninja://app/clients/abc',
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump();

          expect(find.text('Navigate'), findsOneWidget);
          expect(find.text('Select'), findsOneWidget);
          expect(find.text('Close'), findsOneWidget);
          // ⌘ / in the field, then ↑ ↓ Enter Esc in the footer.
          expect(find.byType(KeyCap), findsNWidgets(6));
          expect(
            find.textContaining('·'),
            findsNothing,
            reason: 'the separators are gone — a cap is its own visual unit',
          );
        },
      );
    });

    testWidgets('Enter follows a pasted link before the debounce fires', (
      tester,
    ) async {
      // Attach the real router so the link is followed all the way to a
      // navigation. Asserting only that the palette closed would stay green
      // against a `_select` that pops and then drops the link on the floor.
      final navigations = <String>[];
      fixture.services.deepLinks.attach(
        go: navigations.add,
        contextOf: () => null,
      );
      await withPalette(
        tester,
        size: desktop,
        platform: TargetPlatform.macOS,
        body: () async {
          expect(
            find.byType(Dialog),
            findsOneWidget,
            reason: 'guard: a palette that never opened would read as a pass',
          );
          await tester.enterText(
            find.byType(TextField),
            'invoiceninja://app/clients/abc',
          );
          // Deliberately NOT pumping past the 250 ms debounce. Paste-then-Enter
          // is the natural gesture for a shared link, and on web and Linux this
          // palette is the ONLY way to follow one — the OS never delivers the
          // custom scheme there. Enter inside the debounce window used to fall
          // out of `_select` against an empty `_results` and do nothing at all,
          // so the user had to press it twice with no hint why.
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();

          expect(find.byType(Dialog), findsNothing, reason: 'palette closed');
          expect(navigations, [
            '/clients/abc',
          ], reason: 'the link never reached DeepLinkRouter');
        },
      );
    });

    testWidgets('…and over a stale result set, not the previous query', (
      tester,
    ) async {
      // The nastier half. `_onChanged` arms the debounce without clearing
      // `_results`, so inside that window the old query's hits are still up
      // and `_selected` still indexes them. Keying the link fallback on
      // "`_results` is empty" therefore navigated to a hit from the query the
      // user had just replaced — worse than the nothing it was fixing, and the
      // sequence anyone who was already searching will hit.
      final navigations = <String>[];
      fixture.services.deepLinks.attach(
        go: navigations.add,
        contextOf: () => null,
      );
      await withPalette(
        tester,
        size: desktop,
        platform: TargetPlatform.macOS,
        body: () async {
          // Populate `_results` with a FIRST link, so the stale set exists
          // without needing the search backend the shell fixture has no mock
          // for. `_run` resolves a link locally and synchronously, so after
          // the debounce `_results` holds exactly one hit and `_selected` is
          // 0 — the in-range state that made the old guard fall through.
          await tester.enterText(
            find.byType(TextField),
            'invoiceninja://app/invoices/stale',
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump();

          // Paste over it and hit Enter inside the debounce.
          await tester.enterText(
            find.byType(TextField),
            'invoiceninja://app/clients/abc',
          );
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();

          expect(navigations, [
            '/clients/abc',
          ], reason: 'Enter used the stale results instead of the pasted link');
        },
      );
    });

    testWidgets('a desktop window keeps the floating card', (tester) async {
      await withPalette(
        tester,
        size: desktop,
        platform: TargetPlatform.macOS,
        body: () async {
          expect(find.byIcon(Icons.arrow_back), findsNothing);
          // One cap per glyph: `⌘` + `K` on macOS — the palette's own live
          // binding. The card is at rest (no query, no recents), so
          // `sections` is empty and the footer's own caps aren't up yet.
          expect(find.byType(KeyCap), findsNWidgets(2));
          expect(find.text('⌘'), findsOneWidget);
          expect(find.text('K'), findsOneWidget);
          expect(
            tester.getSize(find.byType(ClipRRect)).width,
            lessThanOrEqualTo(680),
            reason: 'the Spotlight card is unchanged on desktop',
          );
        },
      );
    });
  });

  group('settings rows', () {
    late ShellFixture fixture;

    setUp(() async {
      fixture = await buildFixture(
        companies: const [FakeCompany(id: 'c1', name: 'Acme')],
      );
    });

    tearDown(() async => fixture.dispose());

    /// Opens the desktop palette and types [query]. The fixture is offline, so
    /// the server search fails and the palette answers from its own report
    /// and settings catalogs — which is what this group is about.
    Future<void> search(WidgetTester tester, String query) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showCommandPalette(context),
              child: const Text('trigger'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), query);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    testWidgets('a settings row names the page and tab it opens', (
      tester,
    ) async {
      // Six "Email" rows from six pages were indistinguishable.
      await search(tester, 'postal');
      expect(find.text('Postal Code'), findsOneWidget);
      expect(find.text('Company Details › Address'), findsOneWidget);
    });

    // A desktop user with the sidebar collapsed found no way to send
    // feedback (invoiceninja/flutter#191); typing it is the other way in.
    testWidgets('"feedback" finds Contact Us, offline too', (tester) async {
      await search(tester, 'feedback');
      expect(find.text('Contact Us'), findsOneWidget);
      expect(find.text('Support Forums'), findsNothing);
    });

    testWidgets('"help" lists Contact Us, User Guide and the forum', (
      tester,
    ) async {
      await search(tester, 'help');
      expect(find.text('Contact Us'), findsOneWidget);
      expect(find.text('User Guide'), findsOneWidget);
      expect(find.text('Support Forums'), findsOneWidget);
    });

    testWidgets('settings rows stop at eight, four of them up front', (
      tester,
    ) async {
      // "mail" matches well over eight settings labels and no report.
      expect(
        searchSettings('mail', bundledLocalization()).length,
        greaterThan(8),
      );
      await search(tester, 'mail');
      // The list is built lazily inside the card, so count its items, not
      // the rows on screen: one Settings header, the group's first four rows
      // and a "Show all 8". No report name contains "mail", so nothing else
      // shares the list.
      final list = tester.widget<ListView>(find.byType(ListView));
      final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
      expect(delegate.childCount, 1 + 4 + 1);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Show all 8'), findsOneWidget);
    });
  });

  // ⌘K belongs to the palette (docs/keyboard.md), so the keyboard reaches the
  // company switcher through it: "Switch Company", and the other companies by
  // name.
  group('company rows', () {
    late ShellFixture fixture;

    setUp(() async {
      fixture = await buildFixture(
        companies: const [
          FakeCompany(id: 'c1', name: 'Acme', token: 'tok-c1'),
          FakeCompany(id: 'c2', name: 'Globex Corp', token: 'tok-c2'),
        ],
      );
    });

    tearDown(() async => fixture.dispose());

    Future<void> search(WidgetTester tester, String query) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showCommandPalette(context),
              child: const Text('trigger'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), query);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    testWidgets('"company" offers Switch Company', (tester) async {
      await search(tester, 'company');
      expect(find.text('Switch Company'), findsOneWidget);
    });

    testWidgets('another company is found by name', (tester) async {
      await search(tester, 'globex');
      expect(find.text('Globex Corp'), findsOneWidget);
      expect(find.byIcon(Icons.business_outlined), findsOneWidget);
    });

    testWidgets('the current company is never offered', (tester) async {
      await search(tester, 'acme');
      expect(find.byIcon(Icons.business_outlined), findsNothing);
    });

    testWidgets('picking another company switches to it and closes', (
      tester,
    ) async {
      await search(tester, 'globex');
      await tester.tap(find.text('Globex Corp'));
      // The outbox guard and the switch read and write the database — real
      // I/O, which the test's fake clock cannot advance; give it real time,
      // a round per await, pumping in between.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(fixture.services.auth.session.value?.currentCompanyId, 'c2');
      expect(find.byType(TextField), findsNothing, reason: 'palette closed');
      // A switch restarts the refresh timer and arms the recents debounce;
      // flutter_test checks for pending timers before tear-down runs (the
      // same drain as company_picker_test).
      fixture.services.refreshScheduler.stop();
      fixture.services.recentlyViewed.dispose();
      // Closing the palette cancels its company watch, and drift closes a
      // cancelled stream on a zero timer.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  // The fallback server answer — what the demo, and every server without
  // Elasticsearch, sends: the whole company, whatever was typed
  // (docs/search-palette.md). The palette fetches it once and filters it.
  group('search results: filtered, ranked, grouped', () {
    late ShellFixture fixture;
    late int searches;

    final fallbackAnswer = {
      'clients': [
        {'name': 'Macejkovic-Hintz', 'id': 'c1', 'path': '/clients/c1'},
        {'name': 'Crooks-Price', 'id': 'c2', 'path': '/clients/c2'},
        {'name': 'Prosper Ltd', 'id': 'c3', 'path': '/clients/c3'},
        {'name': 'Langworth-Prosacco', 'id': 'c4', 'path': '/clients/c4'},
        for (final (i, n) in const [
          (5, 'One'),
          (6, 'Two'),
          (7, 'Three'),
          (8, 'Four'),
          (9, 'Five'),
        ])
          {'name': 'Zeta $n', 'id': 'c$i', 'path': '/clients/c$i'},
      ],
      'client_contacts': <Object>[],
      'invoices': [
        {'name': 'Prosper Ltd - 0042', 'id': 'i1', 'path': '/invoices/i1/edit'},
      ],
      'projects': [
        {'name': 'Pro onboarding - 0007', 'id': 'p1', 'path': '/projects/p1'},
        // More rows than Elasticsearch ever sends (its 100), which is what
        // marks the answer as the query-blind fallback worth keeping.
        for (var i = 0; i < 100; i++)
          {
            'name': 'Archive $i - ${1000 + i}',
            'id': 'a$i',
            'path': '/projects/a$i',
          },
      ],
      'settings': <Object>[],
    };

    setUp(() async {
      searches = 0;
      fixture = await buildFixture(
        companies: const [FakeCompany(id: 'c1', name: 'Acme')],
        closeStreamsSynchronously: true,
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/api/v1/search')) {
            searches++;
            return http.Response(
              jsonEncode(fallbackAnswer),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          return http.Response('offline', 503);
        }),
      );
    });

    tearDown(() async => fixture.dispose());

    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(1200, 800),
      TargetPlatform platform = TargetPlatform.macOS,
      required Future<void> Function() body,
    }) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          wrapWithShell(
            fixture.services,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showCommandPalette(context),
                child: const Text('trigger'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('trigger'));
        await tester.pumpAndSettle();
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('the query-blind answer is fetched once and filtered here', (
      tester,
    ) async {
      await open(
        tester,
        body: () async {
          // Queries no settings label holds, so the clients are on screen
          // (the card builds its list lazily).
          await type(tester, 'Prosp');
          expect(find.text('Prosper Ltd'), findsWidgets);
          expect(
            find.text('Macejkovic-Hintz'),
            findsNothing,
            reason: 'the server sent every client; only matches may show',
          );
          expect(find.text('Crooks-Price'), findsNothing);

          await type(tester, 'Prosa');
          await type(tester, 'Prosac');
          expect(find.text('Langworth-Prosacco'), findsWidgets);
          expect(find.text('Prosper Ltd'), findsNothing);
          expect(searches, 1, reason: 'later keystrokes filter the cache');
        },
      );
    });

    testWidgets('the category bar: Tab moves through it, Esc steps back', (
      tester,
    ) async {
      await open(
        tester,
        body: () async {
          // Prosper Ltd (a client) and its invoice.
          await type(tester, 'prosper');
          expect(find.text('All'), findsOneWidget);
          expect(find.text('Category'), findsOneWidget, reason: 'Tab hint');
          final groups = find.byType(SearchPaletteScopeBar);
          expect(groups, findsOneWidget);
          final scopes = tester
              .widget<SearchPaletteScopeBar>(groups)
              .scopes
              .map((s) => s.id)
              .toList();
          expect(scopes.first, 'all');
          expect(scopes, ['all', 'clients', 'invoices']);

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final bar = tester.widget<SearchPaletteScopeBar>(groups);
          expect(bar.selectedId, scopes[1]);
          expect(
            find.byIcon(Icons.manage_search),
            findsOneWidget,
            reason: 'a category ends with a search of its full list',
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          expect(
            tester.widget<SearchPaletteScopeBar>(groups).selectedId,
            'all',
          );
          expect(find.byType(Dialog), findsOneWidget, reason: 'still open');

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
        },
      );
    });

    testWidgets('⌘↓ jumps to the next group', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(
        tester,
        body: () async {
          // Top hits (Prosper Ltd), then Invoices (its 0042).
          await type(tester, 'prosper');
          final firstGroupRow = find.bySemanticsLabel(RegExp('^Prosper Ltd'));
          final nextGroupRow = find.bySemanticsLabel(RegExp('^0042'));
          expect(
            tester.getSemantics(firstGroupRow.first),
            isSemantics(isSelected: true),
          );

          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pump();
          expect(
            tester.getSemantics(nextGroupRow.first),
            isSemantics(isSelected: true),
            reason: 'the selection moved to the next group',
          );
          // The announcement timer (assistive tech is on in this test).
          await tester.pump(const Duration(seconds: 1));
        },
      );
      semantics.dispose();
    });

    testWidgets('no match offers the lists to search instead', (tester) async {
      await open(
        tester,
        body: () async {
          await type(tester, 'zzzq');
          expect(find.text('No records found'), findsOneWidget);
          expect(find.text('Search Clients for "zzzq"'), findsOneWidget);
          expect(find.text('Search Invoices for "zzzq"'), findsOneWidget);
        },
      );
    });

    testWidgets('an Enter pressed before a no-match answer opens nothing', (
      tester,
    ) async {
      await open(
        tester,
        body: () async {
          await tester.enterText(find.byType(TextField), 'zzqx');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump();
          expect(find.text('No records found'), findsOneWidget);
          expect(
            find.byType(Dialog),
            findsOneWidget,
            reason: 'not closed onto a list the user never picked',
          );
        },
      );
    });

    testWidgets('Search on text the results already answer ends the wait', (
      tester,
    ) async {
      await open(
        tester,
        size: const Size(412, 915),
        platform: TargetPlatform.android,
        body: () async {
          await type(tester, 'Prosp');
          expect(find.byType(LinearProgressIndicator), findsNothing);
          // A key and its undo inside the debounce, then Search.
          await tester.enterText(find.byType(TextField), 'Prospx');
          await tester.enterText(find.byType(TextField), 'Prosp');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.byType(LinearProgressIndicator),
            findsNothing,
            reason: 'nothing is coming, so nothing may spin',
          );
          expect(find.text('Prosper Ltd'), findsWidgets);
        },
      );
    });

    testWidgets('a pasted link leaves no category taking Tab or Esc', (
      tester,
    ) async {
      await open(
        tester,
        body: () async {
          await type(tester, 'prosper');
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            tester
                .widget<SearchPaletteScopeBar>(
                  find.byType(SearchPaletteScopeBar),
                )
                .selectedId,
            isNot('all'),
            reason: 'guard: a category is open',
          );

          await type(tester, 'invoiceninja://app/clients/abc');
          expect(find.byType(SearchPaletteScopeBar), findsNothing);
          expect(find.text('Category'), findsNothing, reason: 'no Tab hint');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(
            find.byType(Dialog),
            findsNothing,
            reason: 'one Esc closes — no invisible category to leave first',
          );
        },
      );
    });

    testWidgets('a hardware Enter opens the selection on a touch tablet', (
      tester,
    ) async {
      await open(
        tester,
        size: const Size(1024, 1366),
        platform: TargetPlatform.iOS,
        body: () async {
          await type(tester, 'zeta');
          expect(find.byType(ClipRRect), findsWidgets, reason: 'the card');
          // Select "Show all" with the pointer — no arrow key, which used to
          // be the only way Enter would act on touch.
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(find.text('Show all 5')));
          await tester.pump();

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(
            find.byIcon(Icons.manage_search),
            findsOneWidget,
            reason: 'Enter switched to the Clients category',
          );
          expect(find.text('Zeta Five'), findsOneWidget);
        },
      );
    });

    testWidgets(
      'a narrow desktop window gets the page, keyboard hints and all',
      (tester) async {
        await open(
          tester,
          size: const Size(400, 800),
          body: () async {
            expect(find.byIcon(Icons.arrow_back), findsOneWidget);
            await type(tester, 'Pro');
            expect(find.text('Close'), findsOneWidget, reason: 'Esc hint');
          },
        );
      },
    );

    testWidgets('a short window gets the page too', (tester) async {
      await open(
        tester,
        size: const Size(1200, 420),
        body: () async {
          expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        },
      );
    });

    testWidgets('the soft keyboard\'s Search runs the search, opens nothing', (
      tester,
    ) async {
      await open(
        tester,
        size: const Size(412, 915),
        platform: TargetPlatform.android,
        body: () async {
          await tester.enterText(find.byType(TextField), 'Prosp');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pump();
          await tester.pump();
          expect(find.byType(Dialog), findsOneWidget, reason: 'still open');
          expect(find.text('Prosper Ltd'), findsWidgets);
          expect(searches, 1);
        },
      );
    });

    testWidgets('on a touch tablet the first arrow shows the selection', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await open(
        tester,
        size: const Size(1024, 1366),
        platform: TargetPlatform.iOS,
        body: () async {
          await type(tester, 'zeta');
          final one = find.bySemanticsLabel(RegExp('^Zeta One'));
          final two = find.bySemanticsLabel(RegExp('^Zeta Two'));
          expect(
            tester.getSemantics(one),
            isSemantics(isSelected: false),
            reason: 'nothing is painted on touch, so nothing is announced',
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          expect(
            tester.getSemantics(one),
            isSemantics(isSelected: true),
            reason: 'the first ↓ shows the first row rather than skip it',
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          expect(tester.getSemantics(two), isSemantics(isSelected: true));
          await tester.pump(const Duration(seconds: 1));
        },
      );
      semantics.dispose();
    });

    testWidgets('on a touch tablet the first ↑ does not wrap to the end', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await open(
        tester,
        size: const Size(1024, 1366),
        platform: TargetPlatform.iOS,
        body: () async {
          await type(tester, 'zeta');
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pump();
          expect(
            tester.getSemantics(find.bySemanticsLabel(RegExp('^Zeta One'))),
            isSemantics(isSelected: true),
          );
          await tester.pump(const Duration(seconds: 1));
        },
      );
      semantics.dispose();
    });

    testWidgets('Enter inside the debounce opens the new text\'s result', (
      tester,
    ) async {
      await open(
        tester,
        body: () async {
          // Zeta One is selected; its record is what a stale Enter opened.
          await type(tester, 'zeta');
          await tester.enterText(find.byType(TextField), 'switch company');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pumpAndSettle();
          expect(
            find.byType(CompanyPicker),
            findsOneWidget,
            reason: 'Enter waited for "switch company" and opened its row',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(milliseconds: 10));
          await tester.pump(const Duration(milliseconds: 10));
        },
      );
    });

    testWidgets('the category bar fades into what is behind it', (
      tester,
    ) async {
      await open(
        tester,
        size: const Size(412, 915),
        platform: TargetPlatform.android,
        body: () async {
          await type(tester, 'prosper');
          expect(
            tester
                .widget<SearchPaletteScopeBar>(
                  find.byType(SearchPaletteScopeBar),
                )
                .fadeColor,
            InTheme.light.bg,
            reason: 'the page is Dialog.fullscreen on bg, not the card',
          );
        },
      );
    });

    testWidgets('the card\'s category bar fades into surface', (tester) async {
      await open(
        tester,
        body: () async {
          await type(tester, 'prosper');
          expect(
            tester
                .widget<SearchPaletteScopeBar>(
                  find.byType(SearchPaletteScopeBar),
                )
                .fadeColor,
            InTheme.light.surface,
          );
        },
      );
    });
  });

  // A fallback group at its limit (1000 clients) is a floor for the whole
  // open, however its answer landed.
  group('a capped fallback keeps its floor', () {
    late ShellFixture fixture;
    late Completer<void> gate;
    late int searches;

    final answer = {
      'clients': [
        {'name': 'Other Co', 'id': 'o1', 'path': '/clients/o1'},
        for (var i = 0; i < 999; i++)
          {'name': 'Zeta $i', 'id': 'z$i', 'path': '/clients/z$i'},
      ],
      'client_contacts': <Object>[],
      'invoices': [
        {'name': 'Zeta 1 - 0001', 'id': 'i1', 'path': '/invoices/i1/edit'},
      ],
      'projects': <Object>[],
      'settings': <Object>[],
    };

    setUp(() async {
      gate = Completer<void>();
      searches = 0;
      fixture = await buildFixture(
        companies: const [FakeCompany(id: 'c1', name: 'Acme')],
        closeStreamsSynchronously: true,
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/api/v1/search')) {
            searches++;
            await gate.future;
            return http.Response(
              jsonEncode(answer),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          return http.Response('offline', 503);
        }),
      );
    });

    tearDown(() async => fixture.dispose());

    testWidgets('even when the answer lands after a newer keystroke', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showCommandPalette(context),
              child: const Text('trigger'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      await tester.enterText(field, 'Zeta');
      // The debounce fires; the request waits at the gate.
      await tester.pump(const Duration(milliseconds: 200));
      // A newer text supersedes it before it lands.
      await tester.enterText(field, '');
      await tester.enterText(field, 'Zeta 1');
      gate.complete();
      // The answer is decoded off the fake clock; give it real time, a
      // round per await, pumping in between.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(searches, 1, reason: 'guard: one request, superseded');

      final bar = tester.widget<SearchPaletteScopeBar>(
        find.byType(SearchPaletteScopeBar),
      );
      final clients = bar.scopes.firstWhere((s) => s.id == 'clients');
      expect(clients.atLeast, isTrue, reason: 'a group at its limit');
      expect(bar.scopes.first.atLeast, isTrue, reason: 'and so All');
    });
  });

  group('counts read singular at one', () {
    test('the settled announcement', () {
      expect(
        searchResultsAnnouncementKey(1, 1, atLeast: false),
        'search_one_result_announcement',
      );
      expect(
        searchResultsAnnouncementKey(1, 1, atLeast: true),
        'search_at_least_one_result_announcement',
      );
      expect(
        searchResultsAnnouncementKey(5, 1, atLeast: false),
        'search_results_one_category_announcement',
      );
      expect(
        searchResultsAnnouncementKey(95, 1, atLeast: true),
        'search_results_at_least_one_category_announcement',
      );
      expect(
        searchResultsAnnouncementKey(5, 2, atLeast: false),
        'search_results_announcement',
      );
      expect(
        searchResultsAnnouncementKey(95, 3, atLeast: true),
        'search_results_at_least_announcement',
      );
    });

    test('a category\'s count', () {
      expect(
        searchScopeAnnouncementKey(1, atLeast: false),
        'search_scope_one_result_announcement',
      );
      expect(
        searchScopeAnnouncementKey(1, atLeast: true),
        'search_scope_at_least_one_result_announcement',
      );
      expect(
        searchScopeAnnouncementKey(0, atLeast: false),
        'search_scope_announcement',
      );
      expect(
        searchScopeAnnouncementKey(2, atLeast: true),
        'search_scope_at_least_announcement',
      );
    });

    test('every variant has its English, in the singular', () {
      final pending = pendingStrings();
      expect(pending['show_one_result_in_all'], 'Show :count result in All');
      expect(
        pending['search_one_result_announcement'],
        ':count result in :categories category',
      );
      expect(
        pending['search_results_one_category_announcement'],
        ':count results in :categories category',
      );
      expect(
        pending['search_scope_one_result_announcement'],
        ':scope, :count result',
      );
      for (final key in const [
        'search_at_least_one_result_announcement',
        'search_results_at_least_one_category_announcement',
        'search_scope_at_least_one_result_announcement',
      ]) {
        expect(pending[key], isNotNull, reason: key);
      }
    });
  });
}
