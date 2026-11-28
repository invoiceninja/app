import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/api/company_settings_api_model.dart';
import 'package:admin/data/models/api/group_setting_api_model.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/group_setting.dart';
import 'package:admin/domain/tasks/task_rounding.dart';

/// The round-up interval the server applies to a task's entries
/// (`TaskRepository::roundTimeLog`), resolved client → group → company like
/// `getSetting` (invoiceninja/app#220).
void main() {
  Company company({double? nearest, bool? up}) => Company(
    id: 'co',
    settings: CompanySettingsApi(taskRoundToNearest: nearest, taskRoundUp: up),
  );
  Client client(Map<String, dynamic>? settings) =>
      Client.fromApi(ClientApi(id: 'c', settings: settings));
  GroupSetting group(Map<String, dynamic> settings) =>
      GroupSetting.fromApi(GroupSettingApi(id: 'g', settings: settings));

  test('nothing loaded, or the server default of 1: no rounding', () {
    expect(taskRoundUpSeconds(), 1);
    expect(taskRoundUpSeconds(company: company(nearest: 1)), 1);
    expect(taskRoundUpSeconds(company: company(nearest: 0)), 1);
  });

  test('the company interval, with round-up on or unset', () {
    expect(taskRoundUpSeconds(company: company(nearest: 900)), 900);
    expect(taskRoundUpSeconds(company: company(nearest: 900, up: true)), 900);
  });

  test('rounding down never moves an end past now: 1', () {
    expect(taskRoundUpSeconds(company: company(nearest: 900, up: false)), 1);
  });

  test('a client beats its group, which beats the company', () {
    final c = company(nearest: 900);
    expect(
      taskRoundUpSeconds(
        client: client({'task_round_to_nearest': '1800'}),
        group: group({'task_round_to_nearest': 3600}),
        company: c,
      ),
      1800,
    );
    expect(
      taskRoundUpSeconds(
        client: client({'task_round_to_nearest': ''}),
        group: group({'task_round_to_nearest': 3600}),
        company: c,
      ),
      3600,
      reason: 'blank inherits',
    );
    expect(
      taskRoundUpSeconds(client: client({'task_round_up': false}), company: c),
      1,
    );
    expect(taskRoundUpSeconds(client: client(null), company: c), 900);
  });
}
