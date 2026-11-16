import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/ui/core/widgets/party_contact_row.dart';

import '../../../_responsive_helper.dart';

/// A contact's facts share a line where the card has room for them and stack
/// where it has not — one widget for a card that is the whole of a pane on a
/// billing document and a third of the window on a client.

Widget _row(String name) => PartyContactRow(
  name: name,
  email: '${name.split(' ').first.toLowerCase()}@acme.example.com',
  phone: '',
  actions: [PartyContactAction(icon: Icons.copy, label: 'Copy', onTap: () {})],
);

void main() {
  testWidgets('with room, the address sits on the name\'s line, and the '
      'addresses of a list start on one edge', (tester) async {
    await pumpAt(
      tester,
      700,
      Column(children: [_row('Jane Doe'), _row('Sam Lee')]),
    );
    final name = tester.getCenter(find.text('Jane Doe'));
    final email = tester.getCenter(find.text('jane@acme.example.com'));
    expect((name.dy - email.dy).abs(), lessThan(2));
    expect(
      tester.getTopLeft(find.text('jane@acme.example.com')).dx,
      tester.getTopLeft(find.text('sam@acme.example.com')).dx,
    );
    expectNoOverflow(tester);
  });

  testWidgets('without it, the address goes under the name', (tester) async {
    await pumpAt(tester, 300, _row('Jane Doe'));
    final name = tester.getRect(find.text('Jane Doe'));
    final email = tester.getRect(find.text('jane@acme.example.com'));
    expect(email.top, greaterThanOrEqualTo(name.bottom));
    expect(email.left, name.left);
    expectNoOverflow(tester);
  });
}
