import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// Records each screen change as a crash-report breadcrumb, so an error event
/// says which screen it came from.
///
/// It records the route *pattern* (`/quotes/:id/edit`), never the location: a
/// location carries record ids and a query, and the pattern says enough to
/// find the screen. A change that keeps the pattern (another quote, another
/// filter) records nothing.
///
/// Sentry FLUTTER-ADMIN-1F arrived with no screen at all: 61 hit-test errors
/// from a Windows user, and nothing to say whether they came from the quote
/// editor the user described. See docs/lazy-list-keep-alives.md.
class RouteBreadcrumbs {
  RouteBreadcrumbs({
    required Listenable changes,
    required String Function() currentPattern,
    required void Function({required String from, required String to}) record,
  }) : _changes = changes,
       _currentPattern = currentPattern,
       _record = record {
    _last = _safePattern();
    _record(from: '', to: _last);
    _changes.addListener(_onChange);
  }

  /// Bound to a [GoRouter]'s delegate; [record] is the crash reporter's
  /// `addNavigationBreadcrumb`.
  factory RouteBreadcrumbs.fromRouter({
    required GoRouter router,
    required void Function({required String from, required String to}) record,
  }) => RouteBreadcrumbs(
    changes: router.routerDelegate,
    currentPattern: () =>
        routePattern(router.routerDelegate.currentConfiguration.fullPath),
    record: record,
  );

  final Listenable _changes;
  final String Function() _currentPattern;
  final void Function({required String from, required String to}) _record;
  late String _last;

  void _onChange() {
    final now = _safePattern();
    if (now == _last) return;
    final from = _last;
    _last = now;
    _record(from: from, to: now);
  }

  /// A breadcrumb is diagnostics: it must never be the thing that throws.
  String _safePattern() {
    try {
      return _currentPattern();
    } catch (_) {
      return '?';
    }
  }

  void dispose() => _changes.removeListener(_onChange);
}

/// The pattern as a breadcrumb shows it: `/` before the first route matches.
@visibleForTesting
String routePattern(String fullPath) => fullPath.isEmpty ? '/' : fullPath;
