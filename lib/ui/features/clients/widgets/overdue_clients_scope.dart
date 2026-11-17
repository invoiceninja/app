import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';

/// The clients whose balance the Clients list draws in the `overdue` red:
/// those with at least one active, past-due invoice — the Overdue status
/// tab's own predicate (`ClientDao.watchOverdueClientIds`), so a red row and
/// that tab can never disagree (docs/entity-lists.md § A client's balance is
/// red only when it is late). Every other balance keeps the normal ink: a
/// balance is not late by itself.
///
/// Read by the wide table's Balance cell (`clientBalanceCell`) and the phone
/// row's amount; provided by [OverdueClientsHost]. Absent — a test, another
/// list — means nobody is late.
class OverdueClientsScope extends InheritedWidget {
  const OverdueClientsScope({
    required this.clientIds,
    required super.child,
    super.key,
  });

  final Set<String> clientIds;

  /// Whether [clientId] has an overdue invoice. Registers a dependency, so a
  /// cell repaints when the set changes.
  static bool isOverdue(BuildContext context, String clientId) =>
      context
          .dependOnInheritedWidgetOfExactType<OverdueClientsScope>()
          ?.clientIds
          .contains(clientId) ??
      false;

  @override
  bool updateShouldNotify(OverdueClientsScope oldWidget) =>
      !identical(clientIds, oldWidget.clientIds);
}

/// Watches the active company's overdue client ids and provides them to
/// [child] as an [OverdueClientsScope]. The watch is held, not built in
/// `build`, and rebound when the company changes.
class OverdueClientsHost extends StatefulWidget {
  const OverdueClientsHost({required this.child, super.key});

  final Widget child;

  @override
  State<OverdueClientsHost> createState() => _OverdueClientsHostState();
}

class _OverdueClientsHostState extends State<OverdueClientsHost> {
  late final Services _services = context.read<Services>();
  String? _companyId;
  Stream<Set<String>>? _stream;

  @override
  void initState() {
    super.initState();
    _services.auth.session.addListener(_onSession);
    _stream = _bind();
  }

  @override
  void dispose() {
    _services.auth.session.removeListener(_onSession);
    super.dispose();
  }

  /// The watch for the session's company, or the one already held when the
  /// company has not changed.
  Stream<Set<String>>? _bind() {
    final companyId = _services.auth.session.value?.currentCompanyId;
    if (companyId == _companyId) return _stream;
    _companyId = companyId;
    return companyId == null || companyId.isEmpty
        ? null
        : _services.clients.watchOverdueClientIds(companyId: companyId);
  }

  void _onSession() {
    final stream = _bind();
    if (!identical(stream, _stream)) setState(() => _stream = stream);
  }

  @override
  Widget build(BuildContext context) {
    // Always the one StreamBuilder, a null stream included: swapping it for a
    // bare child would remount the whole list under it.
    return StreamBuilder<Set<String>>(
      stream: _stream,
      builder: (context, snap) => OverdueClientsScope(
        clientIds: snap.data ?? const <String>{},
        child: widget.child,
      ),
    );
  }
}
