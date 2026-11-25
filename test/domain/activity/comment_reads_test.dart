import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/activity_api_model.dart';
import 'package:admin/data/models/domain/activity.dart';
import 'package:admin/domain/activity/comment_reads.dart';
import 'package:admin/domain/entity_type.dart';

const _me = 'me';
const _teammate = 'them';

Activity _comment({
  String id = 'a1',
  String author = _teammate,
  int at = 1000,
  int typeId = kCommentActivityTypeId,
  Map<String, ActivityRef> refs = const {},
}) => Activity(
  id: id,
  activityTypeId: typeId,
  notes: 'Call them Friday',
  createdAt: DateTime.fromMillisecondsSinceEpoch(at * 1000, isUtc: true),
  ip: '',
  refs: {
    if (author.isNotEmpty) 'user': ActivityRef(label: 'Pat', id: author),
    ...refs,
  },
);

const _invoice = ActivityRef(
  label: '0012',
  type: EntityType.invoice,
  id: 'inv1',
);
const _client = ActivityRef(label: 'Acme', type: EntityType.client, id: 'c1');

void main() {
  group('whose comment', () {
    test("a teammate's comment counts, mine never does", () {
      expect(isTeammateComment(_comment(), currentUserId: _me), isTrue);
      expect(
        isTeammateComment(_comment(author: _me), currentUserId: _me),
        isFalse,
      );
    });

    test('a comment with no author id is never counted', () {
      expect(
        isTeammateComment(_comment(author: ''), currentUserId: _me),
        isFalse,
      );
    });

    test('a system row is not a comment', () {
      expect(
        isTeammateComment(_comment(typeId: 4), currentUserId: _me),
        isFalse,
      );
    });

    test('nobody signed in counts nothing', () {
      expect(isTeammateComment(_comment(), currentUserId: ''), isFalse);
    });
  });

  group('on a record card', () {
    test('new only when newer than the record threshold', () {
      final c = _comment(at: 1000);
      expect(isNewOnRecord(c, currentUserId: _me, threshold: 999), isTrue);
      expect(isNewOnRecord(c, currentUserId: _me, threshold: 1000), isFalse);
      expect(isNewOnRecord(c, currentUserId: _me, threshold: 2000), isFalse);
    });

    test('my own comment is never new, however recent', () {
      expect(
        isNewOnRecord(
          _comment(author: _me, at: 5000),
          currentUserId: _me,
          threshold: 0,
        ),
        isFalse,
      );
    });

    test('the threshold is the later of the baseline and the stamp', () {
      const reads = CompanyCommentReads(
        baseline: 500,
        records: {'invoice:inv1': 800},
      );
      expect(reads.recordThreshold('invoice:inv1'), 800);
      expect(reads.recordThreshold('invoice:other'), 500);
      const early = CompanyCommentReads(
        baseline: 900,
        records: {'invoice:inv1': 800},
      );
      expect(early.recordThreshold('invoice:inv1'), 900);
    });

    test('a stamp never moves back', () {
      const reads = CompanyCommentReads(
        baseline: 0,
        records: {'invoice:inv1': 800},
      );
      expect(
        identical(reads.withRecordSeen('invoice:inv1', 700), reads),
        isTrue,
      );
      expect(
        reads.withRecordSeen('invoice:inv1', 900).records['invoice:inv1'],
        900,
      );
    });

    test('the oldest stamps go once a company holds too many', () {
      var reads = const CompanyCommentReads(baseline: 0);
      for (var i = 1; i <= kCommentReadsMaxRecords + 3; i++) {
        reads = reads.withRecordSeen('client:c$i', i);
      }
      expect(reads.records, hasLength(kCommentReadsMaxRecords));
      expect(reads.records.containsKey('client:c1'), isFalse);
      expect(reads.records.containsKey('client:c3'), isFalse);
      expect(reads.records.containsKey('client:c4'), isTrue);
    });
  });

  group('in the inbox', () {
    final onInvoice = _comment(
      at: 1000,
      refs: {'invoice': _invoice, 'client': _client},
    );

    test('new after the baseline until the inbox is opened', () {
      const reads = CompanyCommentReads(baseline: 900);
      expect(isNewInInbox(onInvoice, currentUserId: _me, reads: reads), isTrue);
      expect(
        isNewInInbox(
          onInvoice,
          currentUserId: _me,
          reads: reads.withFeedSeen(1000),
        ),
        isFalse,
      );
    });

    test('older than the baseline is never new', () {
      const reads = CompanyCommentReads(baseline: 1500);
      expect(
        isNewInInbox(onInvoice, currentUserId: _me, reads: reads),
        isFalse,
      );
    });

    test('seen on its own card, or on its client card, it is not new', () {
      const reads = CompanyCommentReads(baseline: 0);
      expect(
        isNewInInbox(
          onInvoice,
          currentUserId: _me,
          reads: reads.withRecordSeen('invoice:inv1', 1000),
        ),
        isFalse,
      );
      expect(
        isNewInInbox(
          onInvoice,
          currentUserId: _me,
          reads: reads.withRecordSeen('client:c1', 1000),
        ),
        isFalse,
      );
      expect(
        isNewInInbox(
          onInvoice,
          currentUserId: _me,
          reads: reads.withRecordSeen('invoice:other', 5000),
        ),
        isTrue,
      );
    });

    test('my own comment is never new', () {
      expect(
        isNewInInbox(
          _comment(author: _me, at: 1000),
          currentUserId: _me,
          reads: const CompanyCommentReads(baseline: 0),
        ),
        isFalse,
      );
    });
  });

  group('the record a comment was written on', () {
    test('a document before its client', () {
      final source = commentSourceRecord(
        _comment(refs: {'client': _client, 'invoice': _invoice}),
      );
      expect(source?.token, 'invoice');
      expect(source?.ref.id, 'inv1');
    });

    test('a client note resolves to the client', () {
      expect(
        commentSourceRecord(_comment(refs: {'client': _client}))?.token,
        'client',
      );
    });

    test(
      "a purchase order's expense alias is skipped, for naming and reading",
      () {
        final a = _comment(
          refs: {
            'expense': const ActivityRef(
              label: 'E-5',
              type: EntityType.expense,
              id: 'po5',
            ),
            'purchase_order': const ActivityRef(
              label: 'PO-5',
              type: EntityType.purchaseOrder,
              id: 'po5',
            ),
          },
        );
        expect(commentSourceRecord(a)?.token, 'purchase_order');
        expect(commentRecordKeys(a), ['purchase_order:po5']);
      },
    );

    test('a row naming nothing openable has no source', () {
      expect(commentSourceRecord(_comment()), isNull);
    });
  });

  group('stored per user', () {
    test('round-trips', () {
      final reads = const CommentReads(userId: _me).withCompany(
        'co',
        const CompanyCommentReads(
          baseline: 10,
          feedSeen: 20,
          records: {'invoice:inv1': 30},
        ),
      );
      final back = CommentReads.decode(reads.encode(), userId: _me);
      final co = back.companies['co']!;
      expect(co.baseline, 10);
      expect(co.feedSeen, 20);
      expect(co.records, {'invoice:inv1': 30});
    });

    test("another user's blob reads as empty", () {
      final raw = const CommentReads(
        userId: _teammate,
      ).withCompany('co', const CompanyCommentReads(baseline: 10)).encode();
      expect(CommentReads.decode(raw, userId: _me).companies, isEmpty);
    });

    test('garbage reads as empty', () {
      expect(CommentReads.decode('{nope', userId: _me).companies, isEmpty);
      expect(CommentReads.decode(null, userId: _me).companies, isEmpty);
    });
  });
}
