import 'package:drift/drift.dart';
import 'package:sqlite3/common.dart' show SqliteException;

/// A store whose schema reads fine but whose `recurring_invoices` pages are
/// damaged — the shape the web demo shipped with. The open's `SELECT 1` and
/// `PRAGMA table_info` pass; the first statement that touches the table (a
/// wipe's `DELETE FROM "recurring_invoices"`) throws SQLITE_CORRUPT, and
/// `PRAGMA quick_check` reports the damage.
///
/// [code] swaps the error for another SQLite result code, to show what is not
/// corruption. [quickCheckThrows] makes the check fail with that error rather
/// than report rows.
class CorruptPagesInterceptor extends QueryInterceptor {
  CorruptPagesInterceptor({this.code = 11, this.quickCheckThrows = false});

  final int code;
  final bool quickCheckThrows;

  SqliteException get _error => SqliteException(
    extendedResultCode: code,
    message: code == 11 ? 'database disk image is malformed' : 'failed',
  );

  bool _touchesDamagedTable(String sql) => sql.contains('"recurring_invoices"');

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (statement.trim() == 'PRAGMA quick_check') {
      if (quickCheckThrows) throw _error;
      return [
        {
          'quick_check':
              '*** in database main ***\nPage 7: btreeInitPage() returns '
              'error code 11',
        },
      ];
    }
    if (_touchesDamagedTable(statement)) throw _error;
    return executor.runSelect(statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (_touchesDamagedTable(statement)) throw _error;
    return executor.runDelete(statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (_touchesDamagedTable(statement) &&
        statement.trimLeft().toUpperCase().startsWith('DELETE')) {
      throw _error;
    }
    return executor.runCustom(statement, args);
  }
}
