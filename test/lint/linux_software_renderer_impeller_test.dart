import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CI lint: the Linux runner turns Impeller off whenever the software renderer
/// is in use, before the engine starts.
///
/// Flutter 3.50's Linux engine reads `FLUTTER_LINUX_RENDERER=software` but
/// still passes `--enable-impeller`, and Impeller has no software backend: the
/// first frame aborts with "Impeller DlText cannot be drawn to a Skia canvas".
/// Users set that variable by hand to get round a GPU problem, so they have to
/// land on Skia.
///
/// Nothing else notices if the call goes: the C++ is not built on the machines
/// that run these tests, and the app runs on every GPU-rendered machine. See
/// `docs/upstream-workarounds.md` entry 30 for the revert condition.
void main() {
  test('the Linux runner pairs the software renderer with Impeller off', () {
    final source = File('linux/runner/my_application.cc').readAsStringSync();

    final helper = source.indexOf(
      'static void match_impeller_to_renderer(FlDartProject* project) {',
    );
    expect(helper, isNot(-1), reason: 'match_impeller_to_renderer is gone');
    final body = source.substring(helper, source.indexOf('\n}\n', helper));
    expect(
      body,
      allOf(
        contains('g_getenv("FLUTTER_LINUX_RENDERER")'),
        contains('"software"'),
        contains('fl_dart_project_set_enable_impeller(project, FALSE)'),
      ),
    );

    // Before the engine reads the project in fl_view_new.
    final call = source.indexOf('match_impeller_to_renderer(project);');
    final view = source.indexOf('fl_view_new(project)');
    expect(call, isNot(-1));
    expect(view, greaterThan(call));
  });
}
