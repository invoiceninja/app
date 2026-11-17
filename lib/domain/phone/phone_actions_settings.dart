import 'package:flutter/foundation.dart';

/// Device-local preferences for the tap-to-call / tap-to-message affordances
/// on phone numbers (invoiceninja/flutter#109).
///
/// Persisted as one JSON blob (`DevicePrefKeys.phoneActions`) — six related
/// fields, same reasoning as `contacts_sync_json`: none of it is ever queried
/// by SQL, and one column is one migration instead of six. That is also what
/// made [offerToLogCalls] free to add after the schema shipped
/// (invoiceninja/flutter#120).
///
/// Owned by `PhoneActionsController`; the quiet-hours predicate lives here so
/// it can be unit-tested without Drift, `Services`, or a widget tree.
@immutable
class PhoneActionsSettings {
  const PhoneActionsSettings({
    required this.tapToCall,
    this.confirmBeforeCall = false,
    this.warnOutsideBusinessHours = true,
    this.offerToLogCalls = true,
    this.startMinutes = defaultStartMinutes,
    this.endMinutes = defaultEndMinutes,
  });

  /// 08:00 — deliberately generous. The window exists to catch a 2 a.m.
  /// mis-tap, not to police a working day.
  static const int defaultStartMinutes = 8 * 60;
  static const int defaultEndMinutes = 20 * 60;

  /// [tapToCall] when nothing is stored — see [deviceDefaults].
  static const bool kTapToCallDefault = false;

  /// The defaults, used when nothing is stored.
  ///
  /// [tapToCall] is **off on every platform** (it was `Env.isTouchPrimary`
  /// until Nov 2026). A number that dials on a tap stops selecting as text and
  /// puts a call one mis-tap away, and the list rows' call buttons crowded a
  /// phone row; someone who wants it switches it on once. The record screen's
  /// Call action is not behind this preference: it is an explicit verb, so it
  /// works whatever this says (`callPhoneNumber(explicitAction: true)`).
  ///
  /// A stored blob is still taken literally — a user who switched it on keeps
  /// it on. A blob is written whole on any change to the Phone numbers card,
  /// so a phone that changed another field there under the old default
  /// carries an explicit `true` and keeps it; there is no telling that apart
  /// from a choice.
  factory PhoneActionsSettings.deviceDefaults() =>
      const PhoneActionsSettings(tapToCall: kTapToCallDefault);

  /// Tapping a phone number opens the dialer, and contact rows grow Call /
  /// Message buttons. Off restores the plain copyable text the app had before.
  final bool tapToCall;

  /// Show an in-app "Call …?" prompt before handing over to the dialer.
  ///
  /// **Off by default**, unlike the sibling `confirm_actions` preference: both
  /// iOS (a system `Call …?` alert) and Android (`ACTION_VIEW tel:` opens the
  /// dialer *pre-filled*, the user still presses the call button) already
  /// confirm before a call connects, so switching this on adds a second
  /// prompt in front of one the OS is going to show anyway — the shape
  /// CLAUDE.md warns against under § Action confirmations. It exists because
  /// the issue asked for it, for people who want the belt as well as braces.
  final bool confirmBeforeCall;

  /// Warn when the callee's local time falls outside [startMinutes] ..
  /// [endMinutes]. On by default — this is the half of the guard the OS cannot
  /// provide, and the only one that knows what time it is *where the phone
  /// will ring*.
  final bool warnOutsideBusinessHours;

  /// After the dialer has been opened from the app, offer — once, in a
  /// dismissible toast, when the user comes back — to record what was said on
  /// the record's activity feed (invoiceninja/flutter#120).
  ///
  /// On by default, but the *offer itself* is additionally gated on
  /// `Env.isMobile` at the call site: it hangs off an app-lifecycle round
  /// trip, and only a phone reliably backgrounds the app for a call. A desktop
  /// `tel:` handler may never background it at all, and on mobile **web**
  /// `AppLifecycleState` follows page visibility, so every tab switch would
  /// look like a finished call. Logging a call by hand stays available
  /// everywhere, from the record's actions menu and its Activity tab.
  final bool offerToLogCalls;

  /// Minutes past midnight, in the *callee's* zone. Not a `TimeOfDay`: this
  /// type is JSON-serialised and must not depend on `dart:ui`.
  final int startMinutes;
  final int endMinutes;

  /// Whether [localTime] — already converted into the callee's zone — falls
  /// outside the configured window.
  ///
  /// Two shapes are deliberately supported rather than rejected as invalid:
  ///  * `start == end` is an empty window and never warns, so dragging the two
  ///    fields together is a way to silence the warning without hunting for
  ///    the switch;
  ///  * `start > end` wraps midnight (22:00 → 06:00 reads as "warn during the
  ///    day"), which is nonsense for business hours but is what the user
  ///    typed, and inverting it silently would be worse than honouring it.
  ///
  /// Time of day only — there is no weekday axis, so a Sunday afternoon does
  /// not warn. A deliberate omission (it doubles the settings card); if it is
  /// ever asked for, it belongs here beside the window.
  bool isOutsideBusinessHours(DateTime localTime) {
    if (startMinutes == endMinutes) return false;
    final minutes = localTime.hour * 60 + localTime.minute;
    if (startMinutes < endMinutes) {
      return minutes < startMinutes || minutes >= endMinutes;
    }
    return minutes < startMinutes && minutes >= endMinutes;
  }

  PhoneActionsSettings copyWith({
    bool? tapToCall,
    bool? confirmBeforeCall,
    bool? warnOutsideBusinessHours,
    bool? offerToLogCalls,
    int? startMinutes,
    int? endMinutes,
  }) => PhoneActionsSettings(
    tapToCall: tapToCall ?? this.tapToCall,
    confirmBeforeCall: confirmBeforeCall ?? this.confirmBeforeCall,
    warnOutsideBusinessHours:
        warnOutsideBusinessHours ?? this.warnOutsideBusinessHours,
    offerToLogCalls: offerToLogCalls ?? this.offerToLogCalls,
    startMinutes: startMinutes ?? this.startMinutes,
    endMinutes: endMinutes ?? this.endMinutes,
  );

  Map<String, dynamic> toJson() => {
    'tapToCall': tapToCall,
    'confirmBeforeCall': confirmBeforeCall,
    'warnOutsideBusinessHours': warnOutsideBusinessHours,
    'offerToLogCalls': offerToLogCalls,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
  };

  /// Tolerant of a partial / older blob: a key that is present is taken
  /// literally — a *stored* value is the user's choice and must not be
  /// re-decided — while a **missing** key falls back to the same default a
  /// fresh install gets ([deviceDefaults]), so tap-to-call stays off for
  /// anyone who never asked for it.
  factory PhoneActionsSettings.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) {
      final v = json[key];
      return v is bool ? v : fallback;
    }

    int minutes(String key, int fallback) {
      final v = json[key];
      final n = v is int ? v : int.tryParse('$v');
      if (n == null || n < 0 || n > 24 * 60) return fallback;
      return n;
    }

    return PhoneActionsSettings(
      tapToCall: flag('tapToCall', kTapToCallDefault),
      confirmBeforeCall: flag('confirmBeforeCall', false),
      warnOutsideBusinessHours: flag('warnOutsideBusinessHours', true),
      offerToLogCalls: flag('offerToLogCalls', true),
      startMinutes: minutes('startMinutes', defaultStartMinutes),
      endMinutes: minutes('endMinutes', defaultEndMinutes),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PhoneActionsSettings &&
      other.tapToCall == tapToCall &&
      other.confirmBeforeCall == confirmBeforeCall &&
      other.warnOutsideBusinessHours == warnOutsideBusinessHours &&
      other.offerToLogCalls == offerToLogCalls &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes;

  @override
  int get hashCode => Object.hash(
    tapToCall,
    confirmBeforeCall,
    warnOutsideBusinessHours,
    offerToLogCalls,
    startMinutes,
    endMinutes,
  );
}
