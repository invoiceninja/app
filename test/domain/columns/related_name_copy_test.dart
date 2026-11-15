import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A related record's column holds a hashed id and shows a name. Its
/// `valueBuilder` is the id — and until `copiesCellName` that is what the
/// cell's copy icon put on the clipboard (`Wpmbk5ezJn` beside "Acme Corp").
///
/// A source scan, because nothing else can see it: the column builds, the
/// icon shows, and the wrong string is copied.
void main() {
  test('no column whose cell is a name label copies the id behind it', () {
    final idColumn = RegExp(
      r'valueBuilder: \(\w+\) =>\s+cellNonZeroString\(\s*\w+\.'
      r'(clientId|vendorId|projectId|designId|assignedUserId|invoiceId|'
      r'categoryId|companyGatewayId|bankAccountId)\s*\),'
      r'(\s*copiesCellName: true,)?',
    );
    final offenders = <String>[];
    var checked = 0;
    for (final file
        in Directory('lib/domain/columns').listSync().whereType<File>().where(
          (f) => f.path.endsWith('_columns.dart'),
        )) {
      final src = file.readAsStringSync();
      for (final m in idColumn.allMatches(src)) {
        checked++;
        if (m.group(2) != null) continue;
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        offenders.add('${file.path}:$line  ${m.group(1)}');
      }
    }
    expect(checked, greaterThan(40), reason: 'the scan finds the columns');
    expect(
      offenders,
      isEmpty,
      reason:
          'Set `copiesCellName: true` so the copy icon copies the name the '
          'cell shows (docs/selecting-and-copying-text.md). Offenders:\n'
          '${offenders.join('\n')}',
    );
  });

  test('the shared user-name column factory copies the name too', () {
    final src = File(
      'lib/domain/columns/column_factories.dart',
    ).readAsStringSync();
    final factory = src.substring(
      src.indexOf('ColumnDefinition<T> colUserName'),
    );
    final end = factory.indexOf('\n);');
    expect(factory.substring(0, end), contains('copiesCellName: true'));
  });
}
