import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/empty_state.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/widgets/settings_screen_scaffold.dart';

/// Owns the lifecycle of a settings ViewModel that is tied to the active
/// company: builds the VM with the current `auth.session.currentCompanyId`,
/// listens for company switches, and disposes + rebuilds the VM against the
/// new tenant id when the user picks a different company.
///
/// The old draft is intentionally discarded on switch — it belongs to the
/// previous tenant and would be invalid against the new one's id. The
/// company picker is responsible for gating the switch on a confirm-discard
/// dialog (`UnsavedChangesGuard.confirmIfDirty`); by the time this listener
/// fires the user has already opted in to losing the draft.
///
/// `create` should also kick off any one-shot `load()` the VM needs so the
/// helper doesn't have to know about a specific lifecycle method. The
/// callback runs once on init and once per company switch.
///
/// Both [CascadeSettingsScaffold] and `CompanyDetailsShell` use this helper.
/// New custom shells (Email Settings, Online Payments, Tax Settings, …)
/// should reach for this rather than re-rolling the listener inline.
///
/// A host whose VM always edits the company passes [companyOnlyTitleKey]. At
/// group or client scope it then refuses: the page is replaced by a notice
/// (under the scope banner, whose close leaves the scope) and the VM is never
/// built, so nothing reached from a group or a client — a link, a search hit,
/// a stale route — can save company-wide fields under that scope's banner.
class SettingsCompanyScopedHost<V extends ChangeNotifier>
    extends StatefulWidget {
  const SettingsCompanyScopedHost({
    super.key,
    required this.create,
    required this.builder,
    this.companyOnlyTitleKey,
  });

  /// The page title, for a host whose VM edits only the company; null for a
  /// cascade-aware host (its `create` picks the scope's VM). See the class
  /// doc for what a non-null value does at group / client scope.
  final String? companyOnlyTitleKey;

  /// Builds the VM for the supplied company id. Called once on init and
  /// again on every session-driven company switch. Implementations should
  /// also kick off any required `load()` here.
  final V Function(String companyId) create;

  /// Renders the current VM. Re-runs when [create] returns a fresh VM
  /// after a company switch.
  final Widget Function(BuildContext context, V vm) builder;

  @override
  State<SettingsCompanyScopedHost<V>> createState() =>
      _SettingsCompanyScopedHostState<V>();
}

class _SettingsCompanyScopedHostState<V extends ChangeNotifier>
    extends State<SettingsCompanyScopedHost<V>> {
  late final Services _services;

  /// Never built while a company-only host is refusing.
  V? _vm;
  String _currentCompanyId = '';

  @override
  void initState() {
    super.initState();
    _services = context.read<Services>();
    _currentCompanyId = _services.auth.session.value?.currentCompanyId ?? '';
    if (!_refuses(context.read<SettingsLevelController?>())) {
      _vm = widget.create(_currentCompanyId);
    }
    _services.auth.session.addListener(_onSessionChanged);
  }

  /// Whether this host is company-only and [level] is a group or a client.
  bool _refuses(SettingsLevelController? level) =>
      widget.companyOnlyTitleKey != null && level != null && !level.isCompany;

  @override
  void dispose() {
    _services.auth.session.removeListener(_onSessionChanged);
    _vm?.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    final next = _services.auth.session.value?.currentCompanyId ?? '';
    if (next == _currentCompanyId) return;
    setState(() {
      _vm?.dispose();
      _currentCompanyId = next;
      _vm = _refuses(context.read<SettingsLevelController?>())
          ? null
          : widget.create(_currentCompanyId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleKey = widget.companyOnlyTitleKey;
    if (titleKey != null &&
        _refuses(context.watch<SettingsLevelController?>())) {
      return SettingsScreenScaffold(
        titleKey: titleKey,
        body: EmptyState(
          key: const ValueKey('settings-company-only-at-scope'),
          icon: Icons.business_outlined,
          title: context.tr('company_settings_only'),
        ),
      );
    }
    // Left unbuilt by a refusal the scope has since been reset out of.
    final vm = _vm ??= widget.create(_currentCompanyId);
    return widget.builder(context, vm);
  }
}
