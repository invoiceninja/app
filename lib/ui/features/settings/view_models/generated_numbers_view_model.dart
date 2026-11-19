import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/enabled_modules.dart';
import 'package:admin/domain/file_name_pattern.dart';
import 'package:admin/ui/features/settings/view_models/settings_draft_view_model.dart';
import 'package:admin/ui/features/settings/views/advanced/generated_numbers/generated_numbers_validation.dart';
import 'package:admin/ui/features/settings/widgets/settings_field_bindings.dart';

/// Company-scoped state holder for the Generated Numbers settings page.
///
/// Mostly a pure subclass of [SettingsDraftViewModel] — every field binding
/// goes through `settingsBindingOf(apiKey)` (see `settings_field_bindings.dart`),
/// so the VM carries no per-field state. The client-scoped path swaps in
/// [ClientSettingsDraftViewModel] via [CascadeTabbedSettingsShell] under the
/// same [SettingsDraftHost] surface.
///
/// The one piece of behavior it adds is [preSaveError]: a hard save-block when
/// a number pattern would mint duplicate numbers across clients (see
/// [violatesClientCounterRule]). This only runs at company scope — which is all
/// the legacy admin-portal ever validated; it had no per-client number
/// settings. At client/group scope the inline field error still warns.
class GeneratedNumbersViewModel extends SettingsDraftViewModel {
  GeneratedNumbersViewModel({
    required super.repo,
    required super.companyId,
    required this.patternError,
    required this.fileNameError,
  });

  /// Localized "{$client_counter} needs a distinguishing token" message.
  /// Captured in the shell where a `BuildContext` is available — this VM has
  /// none, and [preSaveError] is called off the UI by the save lifecycle.
  final String patternError;

  /// Localized "Add $number so each document gets its own file name." — a
  /// file name pattern without it is one the server ignores.
  final String fileNameError;

  @override
  String? preSaveError(Company draft) {
    final violates = kNumberPatternKeys.any(
      (key) => violatesClientCounterRule(
        settingsBindingOf(key).read(draft.settings),
      ),
    );
    if (violates) return patternError;
    // Only a field the page shows: a hidden one could never be fixed there.
    final missingNumber = kFileNamePatternKeys.any(
      (key) =>
          isModuleEnabled(draft.enabledModules, _kFileNameModules[key]!) &&
          fileNamePatternMissingNumber(
            settingsBindingOf(key).read(draft.settings),
          ),
    );
    return missingNumber ? fileNameError : null;
  }
}

/// The module whose document each file name pattern names.
const _kFileNameModules = {
  'invoice_filename_pattern': EnabledModule.invoices,
  'quote_filename_pattern': EnabledModule.quotes,
  'credit_filename_pattern': EnabledModule.credits,
  'purchase_order_filename_pattern': EnabledModule.purchaseOrders,
};
