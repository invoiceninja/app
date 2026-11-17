import 'package:admin/domain/contact_email_mode.dart';
import 'package:flutter_test/flutter_test.dart';

/// The client contact's email choice reads its two wire flags the way the
/// server stores them (`ClientContactRepository::save`).
void main() {
  test('CC-only wins over send_email on a non-primary contact', () {
    expect(
      contactEmailModeOf(sendEmail: true, ccOnly: true, isPrimary: false),
      ContactEmailMode.cc,
    );
  });

  test('the primary contact is never CC', () {
    expect(
      contactEmailModeOf(sendEmail: false, ccOnly: true, isPrimary: true),
      ContactEmailMode.none,
    );
    expect(
      contactEmailModeOf(sendEmail: true, ccOnly: true, isPrimary: true),
      ContactEmailMode.to,
    );
  });

  test('send_email alone is To, neither is None', () {
    expect(
      contactEmailModeOf(sendEmail: true, ccOnly: false, isPrimary: false),
      ContactEmailMode.to,
    );
    expect(
      contactEmailModeOf(sendEmail: false, ccOnly: false, isPrimary: false),
      ContactEmailMode.none,
    );
  });

  test('every mode round-trips through its flags', () {
    for (final mode in ContactEmailMode.values) {
      final flags = contactEmailFlagsOf(mode);
      expect(
        contactEmailModeOf(
          sendEmail: flags.sendEmail,
          ccOnly: flags.ccOnly,
          isPrimary: false,
        ),
        mode,
      );
      // The server's rule: a CC-only contact never has its own email.
      expect(flags.ccOnly && flags.sendEmail, isFalse);
    }
  });
}
