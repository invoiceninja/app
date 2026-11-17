import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/domain/payment_types.dart';
import 'package:admin/ui/features/settings/view_models/plan_gated_settings_check.dart';
import 'package:admin/ui/features/settings/view_models/settings_draft_view_model.dart';

/// State holder for Settings → Payment Types: the company's
/// `settings.hidden_payment_types` and its payment-type names in
/// `settings.translations` (docs/payment-types.md). Company scope only. All
/// lifecycle plumbing lives on [SettingsDraftViewModel].
///
/// Neither key is in a free hosted plan's `$free_plan_casts` on any tagged
/// server (invoiceninja#13462 adds them), so a save checks the server kept
/// them ([PlanGatedSettingsCheck]) before it says "Saved".
class PaymentTypesSettingsViewModel extends SettingsDraftViewModel
    with PlanGatedSettingsCheck {
  PaymentTypesSettingsViewModel({
    required super.repo,
    required super.companyId,
    this.sendNow,
  });

  @override
  final Future<void> Function()? sendNow;

  /// The hidden ids in order, then each renamed type's key and name, sorted:
  /// a cleared rename and an absent one read the same.
  @override
  String planGatedFingerprint(CompanySettings settings) {
    final hidden = encodeHiddenPaymentTypes(
      parseHiddenPaymentTypes(settings.hiddenPaymentTypes),
    );
    final translations = settings.translations ?? const <String, dynamic>{};
    final renames = <String>[
      for (final key in kPaymentTypeLabelKeys.values)
        if ((translations[key] ?? '').toString().trim() case final name
            when name.isNotEmpty)
          '$key=$name',
    ]..sort();
    return [hidden, ...renames].join('\u0000');
  }
}
