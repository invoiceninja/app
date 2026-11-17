import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CI lint: an entity's Add comment / Log call action items are built only
/// through `addCommentActionItem` / `logCallActionItem`
/// (`standard_entity_action_items.dart`), never an inline `EntityActionItem`.
///
/// The factories set `needsSavedRecord`, which is what makes
/// `filterForEditScreen` drop the pair from every create screen. An inline
/// item has no flag, so it draws Add comment and Log call on a record that
/// does not exist yet — the Enter Payment bar did exactly that, on every
/// entity, until the factories took over.
///
/// The scan looks for the two label keys in `lib/ui/features/**/*_actions.dart`,
/// the files that hold each entity's `itemsFor`.
void main() {
  test('note actions come from the shared factories', () {
    final pattern = RegExp(r"context\.tr\('(add_comment|log_call)'\)");
    final offenders = <String>[];
    for (final entity in Directory(
      'lib/ui/features',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('_actions.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Build Add comment / Log call with addCommentActionItem / '
          'logCallActionItem so the create screen drops them:\n'
          '${offenders.join('\n')}',
    );
  });
}
