import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CI lint: only `lib/main.dart` turns on store purchase delivery, and only
/// for a store-billing build.
///
/// `Services.build(storePurchases:)` defaults to `false` because every test,
/// the integration harnesses and the screenshot runner build the same graph,
/// and `InAppPurchase.instance.purchaseStream` throws on web, Windows and
/// Linux. `main()` passes `isStoreBillingBuild`, never a literal `true`, which
/// would reach the store SDK on every platform.
void main() {
  test('only lib/main.dart passes storePurchases:, as isStoreBillingBuild', () {
    final pattern = RegExp(r'\bstorePurchases:\s*([^,)\s]+)');
    final offenders = <String>[];
    String? mainPasses;

    for (final root in const ['lib', 'test', 'integration_test']) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        // This file names the pattern in its own source.
        if (path.endsWith('test/lint/store_purchases_opt_in_test.dart')) {
          continue;
        }
        final match = pattern.firstMatch(entity.readAsStringSync());
        if (match == null) continue;
        if (path == 'lib/main.dart') {
          mainPasses = match.group(1);
        } else {
          offenders.add(path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Only the app entry point may turn on store purchase delivery; '
          'tests and harnesses must leave `storePurchases` at its default '
          '(false). Found: ${offenders.join(', ')}',
    );
    expect(
      mainPasses,
      'isStoreBillingBuild',
      reason:
          'lib/main.dart must deliver store purchases on a store-billing '
          'build and nowhere else: without it a paid purchase is never '
          'applied, and Play refunds it after three days.',
    );
  });
}
