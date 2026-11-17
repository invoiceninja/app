import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/models/domain/group_setting.dart';
import 'package:admin/ui/features/clients/widgets/edit/client_inherited_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a blank client setting shows as its Default: the group's value, else
/// the company's, and never a guess (`Client::getSetting`).
void main() {
  GroupSetting group(String id, String name, Map<String, dynamic>? settings) =>
      GroupSetting(
        id: id,
        name: name,
        customValue1: '',
        customValue2: '',
        customValue3: '',
        customValue4: '',
        updatedAt: DateTime.utc(2026),
        createdAt: DateTime.utc(2026),
        archivedAt: null,
        isDeleted: false,
        settings: settings,
      );

  const company = CompanySettings(currencyId: '3', paymentTerms: '30');

  test('no group: the company value, from company', () {
    final s = inheritedClientSetting(
      'currency_id',
      groupId: '',
      groups: null,
      companySettings: company,
    );
    expect(s?.value, '3');
    expect(s?.source, isA<FromCompany>());
  });

  test('a group that sets it wins, named', () {
    final s = inheritedClientSetting(
      'currency_id',
      groupId: 'g1',
      groups: [
        group('g1', 'Wholesale', {'currency_id': '2'}),
      ],
      companySettings: company,
    );
    expect(s?.value, '2');
    expect((s?.source as FromGroup).name, 'Wholesale');
  });

  test('a group that leaves it out falls through to the company', () {
    final s = inheritedClientSetting(
      'payment_terms',
      groupId: 'g1',
      groups: [
        group('g1', 'Wholesale', {'currency_id': '2'}),
      ],
      companySettings: company,
    );
    expect(s?.value, '30');
    expect(s?.source, isA<FromCompany>());
  });

  test('groups not loaded, or the group missing: unknown, not company', () {
    expect(
      inheritedClientSetting(
        'currency_id',
        groupId: 'g1',
        groups: null,
        companySettings: company,
      ),
      isNull,
    );
    expect(
      inheritedClientSetting(
        'currency_id',
        groupId: 'g9',
        groups: [group('g1', 'Wholesale', null)],
        companySettings: company,
      ),
      isNull,
    );
  });

  test('nothing set anywhere, or a zero task rate: unknown', () {
    expect(
      inheritedClientSetting(
        'language_id',
        groupId: '',
        groups: null,
        companySettings: company,
      ),
      isNull,
    );
    expect(
      inheritedClientSetting(
        'default_task_rate',
        groupId: '',
        groups: null,
        companySettings: const CompanySettings(defaultTaskRate: 0),
      ),
      isNull,
    );
  });

  test('send_reminders resolves to a bool', () {
    final s = inheritedClientSetting(
      'send_reminders',
      groupId: '',
      groups: null,
      companySettings: const CompanySettings(sendReminders: true),
    );
    expect(s?.value, isTrue);
  });
}
