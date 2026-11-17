import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/dashboard/dashboard_activity.dart';
import 'package:admin/data/static/activity_types_catalog.dart';
import 'package:admin/domain/activity/activity_record_types.dart';

DashboardActivity _row(int type, {Map<String, dynamic> refs = const {}}) =>
    DashboardActivity.fromJson(<String, dynamic>{
      'id': 'a',
      'activity_type_id': type,
      'created_at': 1787472002,
      'notes': '',
      ...refs,
    });

void main() {
  test('the type decides, even when the row names no record', () {
    // A restored quote carries no `quote_id` (BACKEND.md § F3g), only the
    // client.
    expect(
      activityRecordTypeFor(
        _row(
          24,
          refs: {
            'client': {'label': 'Acme', 'hashed_id': 'c1'},
          },
        ),
      ),
      ActivityRecordType.quote,
    );
    expect(activityRecordTypeFor(_row(10)), ActivityRecordType.payment);
    expect(activityRecordTypeFor(_row(130)), ActivityRecordType.purchaseOrder);
  });

  test('a comment is about the record it was written on', () {
    expect(
      activityRecordTypeFor(
        _row(
          141,
          refs: {
            'invoice': {'label': '0001', 'hashed_id': 'i1'},
            'client': {'label': 'Acme', 'hashed_id': 'c1'},
          },
        ),
      ),
      ActivityRecordType.invoice,
    );
    expect(
      activityRecordTypeFor(
        _row(
          141,
          refs: {
            'client': {'label': 'Acme', 'hashed_id': 'c1'},
          },
        ),
      ),
      ActivityRecordType.client,
    );
  });

  test('a row naming nothing is no record type', () {
    expect(activityRecordTypeFor(_row(150)), isNull);
  });

  test('every catalogued type but a comment or a deleted account has one', () {
    final unmapped = [
      for (final id in kActivityTypeLabelKeys.keys)
        if (!kActivityRecordTypes.containsKey(id)) id,
    ];
    expect(unmapped, unorderedEquals([141, 150]));
  });
}
