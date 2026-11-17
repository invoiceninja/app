import 'package:flutter_test/flutter_test.dart';

import 'package:admin/utils/phone_display.dart';

/// A phone number is reformatted for display only — national when it is in
/// the party's country, international otherwise, and the stored text
/// verbatim whenever there is any doubt (docs/tap-to-call.md § A phone number
/// is reformatted for display only).
void main() {
  group('formatPhoneForDisplay', () {
    test('a US number with a US client is written nationally', () {
      expect(
        formatPhoneForDisplay('412.612.9667', regionIso: 'US'),
        '(412) 612-9667',
      );
      expect(
        formatPhoneForDisplay('+1 484 263 8142', regionIso: 'US'),
        '(484) 263-8142',
      );
    });

    test('a UK number with a US client is written internationally', () {
      expect(
        formatPhoneForDisplay('+44 20 7946 0958', regionIso: 'US'),
        '+44 20 7946 0958',
      );
      // Dialled from the US with its exit code: still the UK number.
      expect(
        formatPhoneForDisplay('011 44 20 7946 0958', regionIso: 'US'),
        '+44 20 7946 0958',
      );
    });

    test('national keeps the prefix the country writes', () {
      expect(
        formatPhoneForDisplay('+442079460958', regionIso: 'gb'),
        '020 7946 0958',
      );
      expect(
        formatPhoneForDisplay('+61 2 9876 5432', regionIso: 'AU'),
        '(02) 9876 5432',
      );
      expect(
        formatPhoneForDisplay('0655570576', regionIso: 'FR'),
        '06 55 57 05 76',
      );
    });

    test('garbage and short strings stay verbatim', () {
      for (final s in ['call the office', '123', 'n/a', '555-CALL-NOW']) {
        expect(formatPhoneForDisplay(s, regionIso: 'US'), s);
      }
    });

    test('an extension or a pause keeps the stored text', () {
      for (final s in [
        '+1 412 612 9667 x 22',
        '412-612-9667 ext. 4',
        '+14126129667,22',
        '+14126129667;22',
        '412 612 9667 #3',
      ]) {
        expect(formatPhoneForDisplay(s, regionIso: 'US'), s);
      }
    });

    test('a national number with no country to read it in stays verbatim', () {
      expect(formatPhoneForDisplay('4126129667'), '4126129667');
      expect(
        formatPhoneForDisplay('020 7946 0958', regionIso: ''),
        '020 7946 0958',
      );
      expect(
        formatPhoneForDisplay('020 7946 0958', regionIso: 'ZZ'),
        '020 7946 0958',
      );
    });

    test('an international number needs no region', () {
      expect(formatPhoneForDisplay('+14126129667'), '+1 412-612-9667');
    });

    test('an invalid number stays verbatim', () {
      // Right length, impossible area code.
      expect(
        formatPhoneForDisplay('012-345-6789', regionIso: 'US'),
        '012-345-6789',
      );
    });

    test('empty stays empty', () {
      expect(formatPhoneForDisplay('', regionIso: 'US'), '');
      expect(formatPhoneForDisplay('   ', regionIso: 'US'), '   ');
    });
  });
}
