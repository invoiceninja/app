import 'dart:async';

import 'package:logging/logging.dart';

import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/ui/features/settings/view_models/settings_draft_view_model.dart';

final _log = Logger('PlanGatedSettingsCheck');

/// How long a save waits for the server's copy before it settles for
/// "queued" — the answer every save gave before this check.
const Duration kPlanGatedSendTimeout = Duration(seconds: 15);

/// Thrown by a save the server accepted without keeping an edit it carried
/// ([PlanGatedSettingsCheck]). [SettingsDraftHost.submitNeedsPaidPlan] is what
/// the page reads; the message is only the log and the fallback detail.
class SettingsDroppedByPlanException implements Exception {
  const SettingsDroppedByPlanException();

  @override
  String toString() =>
      'The server did not keep a setting this plan cannot save';
}

/// A company save that confirms the server kept the settings a free hosted
/// plan strips (docs/settings-screens.md § A setting a free hosted plan
/// strips is checked against the server's copy).
///
/// `UpdateCompanyRequest::filterSaveableSettings` keeps only
/// `CompanySettings::$free_plan_casts` for a free hosted account, so a save of
/// any other key answers 200 with that key gone from the echo — which
/// `CompanyRepository.applyUpdateResponse` writes over the optimistic copy.
/// Without this the page said "Saved" and the edit vanished a frame later.
///
/// Only when [planGatedFingerprint] of the draft differs from the baseline's
/// (the user changed one of these settings): the save is sent at once
/// ([sendNow], `SyncRepository.drainOnce`), and once the company has no
/// change left in the outbox the stored copy is compared with what was sent.
/// A copy that no longer holds it fails the save with
/// [submitNeedsPaidPlan] and keeps the user's draft, dirty, over the server's
/// copy. Offline, slow, or rejected for another reason, the save stays queued
/// and reads "Saved", as every save does.
mixin PlanGatedSettingsCheck on SettingsDraftViewModel {
  /// Sends the outbox now; null (tests, a page with no sync engine) skips the
  /// check.
  Future<void> Function()? get sendNow;

  /// A comparable form of the plan-gated settings this page edits — equal for
  /// two blobs that mean the same.
  String planGatedFingerprint(CompanySettings settings);

  bool _droppedByPlan = false;

  @override
  bool get submitNeedsPaidPlan => _droppedByPlan;

  @override
  Future<Company> performSave(Company draft) async {
    _droppedByPlan = false;
    final baseline = initialValue?.settings ?? const CompanySettings();
    final sent = planGatedFingerprint(draft.settings);
    final changed = planGatedFingerprint(baseline) != sent;
    final saved = await super.performSave(draft);
    final send = sendNow;
    if (send == null || !changed) return saved;
    try {
      // A drain already under way answers with its own pass, which may not
      // hold this row — hence a second try.
      for (var i = 0; i < 2 && await repo.hasUnacceptedEdit(companyId); i++) {
        await send().timeout(kPlanGatedSendTimeout);
      }
      if (await repo.hasUnacceptedEdit(companyId)) return saved;
      final stored = await repo.get(companyId);
      if (stored == null || planGatedFingerprint(stored.settings) == sent) {
        return saved;
      }
      _log.info('The server dropped a plan-gated setting from $companyId');
      keepDraftOver(baseline: stored, draft: draft);
    } catch (e) {
      _log.fine('Plan-gated settings check skipped: $e');
      return saved;
    }
    _droppedByPlan = true;
    throw const SettingsDroppedByPlanException();
  }
}
