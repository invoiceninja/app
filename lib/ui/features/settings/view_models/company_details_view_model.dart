import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/ui/features/settings/view_models/plan_gated_settings_check.dart';
import 'package:admin/ui/features/settings/view_models/settings_draft_view_model.dart';

/// State holder shared across all 6 tabs of the Company Details page.
///
/// A subclass of [SettingsDraftViewModel] — the lifecycle (load, watch,
/// dirty, reset, save), the override path, and the field-error plumbing
/// all live on the base. Adding a new settings page follows the same
/// one-line pattern with a different class name.
///
/// The Documents tab's `documents_public_by_default` is not in a free hosted
/// plan's `$free_plan_casts` on any tagged server (invoiceninja#13462 adds
/// it), so a save that changes it checks the server kept it
/// ([PlanGatedSettingsCheck]) before it says "Saved".
class CompanyDetailsViewModel extends SettingsDraftViewModel
    with PlanGatedSettingsCheck {
  CompanyDetailsViewModel({
    required super.repo,
    required super.companyId,
    this.sendNow,
  });

  @override
  final Future<void> Function()? sendNow;

  /// Unset reads as public, the server's default.
  @override
  String planGatedFingerprint(CompanySettings settings) =>
      '${settings.documentsPublicByDefault ?? true}';
}
