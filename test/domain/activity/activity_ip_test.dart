import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/dashboard/dashboard_activity.dart';
import 'package:admin/domain/activity/activity_ip.dart';
import 'package:admin/ui/features/activity/widgets/activity_feed_row.dart';
import 'package:admin/ui/features/dashboard/helpers/activity_formatter.dart';

void main() {
  // The server stamps `request()->ip()` on every activity, and a queued job
  // has no request — so most reminder / recurring / email rows read 127.0.0.1.
  group('displayableActivityIp', () {
    test('drops every loopback spelling', () {
      for (final ip in [
        '127.0.0.1',
        ' 127.0.0.1 ',
        '127.1.2.3',
        '::1',
        '[::1]',
        '0:0:0:0:0:0:0:1',
        '0000:0000:0000:0000:0000:0000:0000:0001',
        '::ffff:127.0.0.1',
        '::FFFF:127.0.0.1',
      ]) {
        expect(displayableActivityIp(ip), '', reason: ip);
      }
    });

    test('keeps a real address, trimmed', () {
      expect(displayableActivityIp(' 203.0.113.9 '), '203.0.113.9');
      expect(displayableActivityIp('2001:db8::1'), '2001:db8::1');
      expect(
        displayableActivityIp('::ffff:198.51.100.4'),
        '::ffff:198.51.100.4',
      );
      // Not loopback despite the shape.
      expect(displayableActivityIp('10.127.0.1'), '10.127.0.1');
      expect(displayableActivityIp('::11'), '::11');
    });

    test('blank and null are blank', () {
      expect(displayableActivityIp(null), '');
      expect(displayableActivityIp('  '), '');
    });
  });

  group('activityAuditMeta', () {
    const render = ActivityRender(
      title: 't',
      meta: '2 minutes ago',
      icon: Icons.circle,
      tone: ActivityTone.sent,
    );
    DashboardActivity act(String ip) => DashboardActivity.fromJson({
      'id': '1',
      'activity_type_id': 5,
      'created_at': 1747569600,
      'ip': ip,
    });

    test('a loopback IP is not shown', () {
      expect(
        activityAuditMeta(act('127.0.0.1'), render: render, formatter: null),
        '2 minutes ago',
      );
    });

    test('a real IP still is', () {
      expect(
        activityAuditMeta(act('1.2.3.4'), render: render, formatter: null),
        '2 minutes ago · 1.2.3.4',
      );
    });
  });
}
