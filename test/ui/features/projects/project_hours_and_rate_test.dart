import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/company_settings_api_model.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/group_setting.dart';
import 'package:admin/domain/tasks/task_rate.dart';
import 'package:admin/ui/features/clients/view_models/client_edit_view_model.dart'
    show emptyClient;
import 'package:admin/ui/features/projects/view_models/project_edit_view_model.dart'
    show emptyProject;
import 'package:admin/ui/features/projects/widgets/detail/analytics/analytics_kit.dart';
import 'package:admin/ui/features/projects/widgets/detail/project_detail_details_card.dart';
import 'package:admin/ui/features/projects/widgets/detail/project_detail_standing.dart';
import 'package:admin/ui/features/projects/widgets/detail/project_hours_format.dart';
import 'package:admin/ui/features/tasks/widgets/detail/task_rate_context.dart';

import '../shell/_shell_test_helpers.dart';

/// The project screen's hours follow the device's hours-format preference,
/// and its Details card says what a project with no task rate inherits.
void main() {
  group('projectHoursText', () {
    test('decimal reads as it always did', () {
      expect(projectHoursText(3.5), '3.5 h');
      expect(projectHoursText(10), '10 h');
      expect(projectHoursText(0), '0 h');
    });

    test('H:MM is the timesheet and reports spelling, with no unit', () {
      expect(projectHoursText(3.5, hoursMinutes: true), '3:30');
      expect(projectHoursText(10, hoursMinutes: true), '10:00');
      expect(projectHoursText(0, hoursMinutes: true), '0:00');
      // Hours are not wrapped at a day.
      expect(projectHoursText(41.25, hoursMinutes: true), '41:15');
    });

    test('the Analytics figures follow the same preference', () {
      expect(analyticsHours(null, 1.5), '1.5 h');
      expect(analyticsHours(null, 1.5, hoursMinutes: true), '1:30');
    });
  });

  group('projectInheritedTaskRate', () {
    final epoch = DateTime.utc(2026);
    GroupSetting group(String rate) => GroupSetting(
      id: 'g1',
      name: 'Wholesale',
      customValue1: '',
      customValue2: '',
      customValue3: '',
      customValue4: '',
      updatedAt: epoch,
      createdAt: epoch,
      archivedAt: null,
      isDeleted: false,
      settings: {'default_task_rate': rate},
    );
    final company = Company(
      id: 'co',
      settings: const CompanySettingsApi(defaultTaskRate: 50),
    );

    test('the first level that sets a rate, named', () {
      final client = emptyClient().copyWith(
        settings: {'default_task_rate': 75},
      );
      final fromClient = projectInheritedTaskRate(
        TaskRateContext(client: client, group: group('60'), company: company),
      );
      expect(fromClient?.rate, Decimal.fromInt(75));
      expect(fromClient?.source, TaskRateSource.client);

      final fromGroup = projectInheritedTaskRate(
        TaskRateContext(
          client: emptyClient(),
          group: group('60'),
          company: company,
        ),
      );
      expect(fromGroup?.rate, Decimal.fromInt(60));
      expect(fromGroup?.source, TaskRateSource.group);
      expect(fromGroup?.groupName, 'Wholesale');

      final fromCompany = projectInheritedTaskRate(
        TaskRateContext(
          client: emptyClient(),
          group: group('0'),
          company: company,
        ),
      );
      expect(fromCompany?.rate, Decimal.fromInt(50));
      expect(fromCompany?.source, TaskRateSource.company);
    });

    test('nothing in the cascade, nothing to show', () {
      expect(projectInheritedTaskRate(const TaskRateContext()), isNull);
      expect(
        projectInheritedTaskRate(
          TaskRateContext(
            client: emptyClient(),
            company: Company(
              id: 'co',
              settings: const CompanySettingsApi(defaultTaskRate: 0),
            ),
          ),
        ),
        isNull,
      );
    });
  });

  group('on screen', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      final fixture = await buildFixture(
        companies: [const FakeCompany(id: 'co1', name: 'Co')],
      );
      addTearDown(fixture.dispose);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );
      // The bundle loads off the fake clock.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('the Logged figure reads H:MM under that preference', (
      tester,
    ) async {
      final project = emptyProject().copyWith(id: 'p1', currentHours: 3.5);
      Widget standing() => ProjectDetailStanding(
        project: project,
        tasks: null,
        companyId: 'co1',
        formatter: null,
        tabIds: const {},
        onOpenTab: (_) {},
      );
      await pump(
        tester,
        ProjectHoursFormat(hoursMinutes: true, child: standing()),
      );
      expect(find.text('3:30'), findsOneWidget);
      expect(find.text('3.5 h'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('a project with no rate says what it inherits, and from '
        'where', (tester) async {
      final project = emptyProject().copyWith(id: 'p1', name: 'Site');
      final client = emptyClient().copyWith(
        settings: {'default_task_rate': 75},
      );
      await pump(
        tester,
        ProjectDetailDetailsCard(
          project: project,
          rates: TaskRateContext(project: project, client: client),
        ),
      );
      expect(find.text('Task Rate'), findsOneWidget);
      expect(find.textContaining('75', findRichText: true), findsWidgets);
      expect(find.text(' · From client'), findsOneWidget);

      // Without the cascade (a project with a rate of its own never watches
      // it), no inherited row.
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester, ProjectDetailDetailsCard(project: project));
      expect(find.text('Task Rate'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
