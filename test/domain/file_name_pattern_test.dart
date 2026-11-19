import 'package:flutter_test/flutter_test.dart';

import 'package:admin/domain/file_name_pattern.dart';

/// The example the File Names tab shows mirrors the server's FileNamePattern
/// (`app/Utils/FileNamePattern.php`); the expectations below are the server
/// test's (`tests/Feature/FileNamePatternTest.php`) where they overlap.
void main() {
  const values = {
    r'$number': '0042',
    r'$entity': 'Invoice',
    r'$date': '2026-11-19',
    r'$due_date': '2026-12-19',
    r'$po_number': 'PO-9',
    r'$client.name': 'Acme Ltd',
    r'$client.number': 'C-7',
    r'$company.name': 'Widgets Inc',
  };

  group('fileNameExample', () {
    test('variables and spaces are kept', () {
      expect(
        fileNameExample(r'$company.name - $entity - $number', values),
        'Widgets Inc - Invoice - 0042.pdf',
      );
    });

    test('every variable', () {
      expect(
        fileNameExample(
          r'$number $entity $date $due_date $po_number $client.name $client.number',
          values,
        ),
        '0042 Invoice 2026-11-19 2026-12-19 PO-9 Acme Ltd C-7.pdf',
      );
    });

    test('braces and an underscore after a variable', () {
      expect(
        fileNameExample(r'$date_$client.name_{$number}', values),
        '2026-11-19_Acme Ltd_0042.pdf',
      );
    });

    test('characters are stripped like the default name', () {
      expect(
        fileNameExample(r'$client.name / $number', {
          ...values,
          r'$client.name': 'O\'Brien & "Sons" 50% <x>|y',
        }),
        'OBrien Sons 50 xy 0042.pdf',
      );
    });

    test('simplified file names', () {
      expect(
        fileNameExample(
          r'$company.name - $entity - $number',
          values,
          slug: true,
        ),
        'widgets-inc-invoice-0042.pdf',
      );
    });

    test('a long value is shortened so the number stays', () {
      expect(
        fileNameExample(r'$client.name - $number', {
          ...values,
          r'$client.name': 'Acme ' * 40,
        }),
        '${'Acme ' * 8}- 0042.pdf',
      );
    });

    test('a pattern without the number gives no name', () {
      expect(fileNameExample(r'$client.name', values), isNull);
    });

    test('the e-invoice takes the same name', () {
      expect(fileNameExample(r'$number', values, extension: 'xml'), '0042.xml');
    });
  });

  test(r'a pattern must contain $number, and blank is fine', () {
    expect(fileNamePatternMissingNumber(r'$client.name - $entity'), isTrue);
    expect(fileNamePatternMissingNumber(r'Acme {$number}'), isFalse);
    expect(fileNamePatternMissingNumber(''), isFalse);
    expect(fileNamePatternMissingNumber(null), isFalse);
  });

  test(
    'a purchase order takes the vendor variables and drops the PO number',
    () {
      expect(
        fileNamePatternForPurchaseOrder(r'$client.name - $po_number $number'),
        r'$vendor.name - $number',
      );
    },
  );

  test('supported once the company settings carry the keys', () {
    expect(fileNamePatternsSupported(const {}), isFalse);
    expect(
      fileNamePatternsSupported(const {'invoice_filename_pattern': ''}),
      isTrue,
    );
  });
}
