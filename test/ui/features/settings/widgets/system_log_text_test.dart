import 'package:flutter_test/flutter_test.dart';

import 'package:admin/ui/features/settings/widgets/system_log_row.dart';

void main() {
  test('a quoted JSON string is shown as the text it holds', () {
    expect(
      systemLogText(r'"Payment failed:\n \"card declined\""'),
      'Payment failed:\n "card declined"',
    );
  });

  test('objects, arrays and plain text are left for the viewer', () {
    expect(systemLogText('{"a":1}'), '{"a":1}');
    expect(systemLogText('[1,2]'), '[1,2]');
    expect(systemLogText('plain words'), 'plain words');
    expect(systemLogText('"unterminated'), '"unterminated');
    expect(systemLogText('"a" and "b"'), '"a" and "b"');
    expect(systemLogText(''), '');
  });
}
