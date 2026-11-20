import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:admin/app/theme_controller.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/data/repositories/user_settings_repository.dart';
import 'package:admin/domain/appearance_sync.dart';

final _log = Logger('AppearanceSyncController');

/// Keeps the appearance — theme mode, both palettes, the custom colours —
/// in step with the signed-in user's account (invoiceninja/app#199).
///
/// The decision is [reconcileAppearance]'s; this wires it up:
///
/// * it watches every company's `company_user.settings` for the signed-in
///   user (a login and a full `/refresh` store all of them; a delta, the
///   active one) and [ThemeController] (a change made here, stamped there);
/// * an adopted copy goes through [ThemeController.adoptSynced], the owner of
///   the four device preferences — never a raw store write;
/// * a push goes to the **active** company only, through
///   [UserSettingsRepository.patchSettings], so it lands offline at once and
///   drains with the outbox. Another company catches up when it is next
///   active.
///
/// Passes run one at a time; a trigger during one runs another after it.
class AppearanceSyncController {
  AppearanceSyncController({
    required ValueListenable<AuthSession?> session,
    required UserSettingsRepository userSettings,
    required ThemeController theme,
    required DevicePrefsStore prefs,
    DateTime Function()? now,
  }) : _session = session,
       _userSettings = userSettings,
       _theme = theme,
       _prefs = prefs,
       _now = now ?? DateTime.now {
    _session.addListener(_onSessionChanged);
    _theme.addListener(_schedule);
    _onSessionChanged();
  }

  final ValueListenable<AuthSession?> _session;
  final UserSettingsRepository _userSettings;
  final ThemeController _theme;
  final DevicePrefsStore _prefs;
  final DateTime Function() _now;

  String _userId = '';
  String _companyId = '';
  StreamSubscription<Map<String, Map<String, dynamic>>>? _sub;

  /// Every company's settings for [_userId], as last emitted; null until the
  /// first emission.
  Map<String, Map<String, dynamic>>? _settings;

  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  /// Completes when the pass in flight (and any it queued) is done. Tests
  /// await it; the app never needs to.
  Future<void> get idle => _idle?.future ?? Future<void>.value();
  Completer<void>? _idle;

  void _onSessionChanged() {
    final s = _session.value;
    final userId = s?.userId ?? '';
    final companyId = s?.currentCompanyId ?? '';
    if (userId == _userId && companyId == _companyId) return;
    final userChanged = userId != _userId;
    _userId = userId;
    _companyId = companyId;
    if (userChanged) {
      unawaited(_sub?.cancel());
      _sub = null;
      _settings = null;
      if (userId.isNotEmpty) {
        _sub = _userSettings
            .watchAllSettings(userId: userId)
            .listen(
              (settings) {
                _settings = settings;
                _schedule();
              },
              onError: (Object e, StackTrace st) {
                _log.warning('Settings stream error', e, st);
              },
            );
      }
    }
    // A switch makes another company the active one: push to it what it
    // lacks.
    _schedule();
  }

  void _schedule() {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _idle ??= Completer<void>();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      do {
        _again = false;
        await _pass();
      } while (_again && !_disposed);
    } catch (e, st) {
      _log.warning('Appearance sync failed', e, st);
    } finally {
      _running = false;
      final idle = _idle;
      _idle = null;
      idle?.complete();
    }
  }

  Future<void> _pass() async {
    final settings = _settings;
    final companyId = _companyId;
    if (settings == null || companyId.isEmpty || _userId.isEmpty) return;
    final decision = reconcileAppearance(
      local: _theme.appearance,
      companies: {
        for (final MapEntry(:key, :value) in settings.entries)
          key: AppearanceRecord.fromSettings(value),
      },
      activeCompanyId: companyId,
      seeded: _prefs.read(DevicePrefKeys.appearanceSeeded) ?? false,
      nowMs: _now().millisecondsSinceEpoch,
    );
    if (decision.isNoop) return;
    if (decision.markSeeded) {
      await _prefs.write(DevicePrefKeys.appearanceSeeded, true);
    }
    final adopt = decision.adopt;
    if (adopt != null) await _theme.adoptSynced(adopt);
    final push = decision.push;
    // The session may have moved on while the adoption was written; a push
    // belongs to the company the decision was made for, and only while it is
    // still the active one (the outbox drains only that one's rows).
    if (push != null && companyId == _companyId && !_disposed) {
      await _userSettings.patchSettings(
        companyId: companyId,
        patch: push.toSettingsPatch(),
      );
    }
  }

  void dispose() {
    _disposed = true;
    _session.removeListener(_onSessionChanged);
    _theme.removeListener(_schedule);
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
