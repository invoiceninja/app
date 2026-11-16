import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CI lint: nothing in `lib/` calls go_router's `GoRouterState.of`.
///
/// On go_router 18 that call never returns for a widget under a route whose
/// page the router has dropped, when the route sits in a nested navigator, as
/// every record screen here does: the UI thread spins and the app is frozen
/// for good (docs/upstream-workarounds.md entry 25). No test can catch a new
/// call by running it, because the failure is a hang, not an exception. So the
/// call itself is banned, and `routerStateOf`
/// (`lib/ui/core/utils/router_state.dart`) is the one place that makes it,
/// only where it is certain to answer.
void main() {
  const wrapper = 'lib/ui/core/utils/router_state.dart';

  test('lib/ asks for the router state only through routerStateOf', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path == wrapper) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('GoRouterState.of(')) {
          offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'GoRouterState.of can freeze the app (it never returns under a '
          'route that is on its way out). Use routerStateOf(context) from '
          '$wrapper instead. Found:\n  ${offenders.join('\n  ')}',
    );
  });

  test('the wrapper still guards the one call it makes', () {
    final source = File(wrapper).readAsStringSync();
    expect(source, contains('route.isActive'));
    expect(source, contains('route.settings is Page<Object?>'));
    expect('GoRouterState.of('.allMatches(_code(source)).length, 1);
  });
}

/// [source] without its comment lines.
String _code(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');
