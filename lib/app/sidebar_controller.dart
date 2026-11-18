import 'package:flutter/foundation.dart';

import 'package:admin/data/prefs/device_pref.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';

/// Owns the user's "is the wide-layout sidebar collapsed?" preference
/// (`DevicePrefKeys.sidebarCollapsed`, device-local), so the rail renders at
/// the correct width on the first frame of the next launch.
///
/// [value] is the stored preference. What the rail actually renders is
/// [effectiveValue] / [effective]: the preference, **or** a foldable in book
/// posture, which collapses the rail so the list keeps the half of the screen
/// before the fold (docs/foldables.md). That override is transient — it is
/// never written to the preference — and every renderer reads [effective]:
/// the content inset, the rail's width, the timer pill's offset and
/// `settingsIndexRedirect` must all agree, or the inset and the rail disagree
/// and the settings shell and its redirect split at different widths.
class SidebarController extends DevicePref<bool> {
  SidebarController({required DevicePrefsStore prefs})
    : super(prefs, DevicePrefKeys.sidebarCollapsed, fallback: false) {
    addListener(_effective._changed);
  }

  late final _EffectiveRailCollapsed _effective = _EffectiveRailCollapsed(this);
  bool _foldCollapsed = false;

  /// The user expanded the rail while book posture had collapsed it. Lasts
  /// until the posture ends.
  bool _expandedInFold = false;

  /// That expand cleared a stored "collapsed" — so collapsing again in the
  /// same posture puts it back, or the user's last choice is lost when the
  /// posture ends.
  bool _clearedStoredInFold = false;

  /// Whether the rail renders collapsed — listen to this, not to the
  /// controller itself, from anything that lays out around the rail.
  ValueListenable<bool> get effective => _effective;

  bool get effectiveValue => value || (_foldCollapsed && !_expandedInFold);

  /// Whether book posture currently holds the rail collapsed.
  bool get foldCollapsed => _foldCollapsed;

  /// Set by the shell's `FoldPostureHost` as the device enters or leaves book
  /// posture. Never persisted.
  void setFoldCollapsed(bool collapsed) {
    if (_foldCollapsed == collapsed) return;
    _foldCollapsed = collapsed;
    if (!collapsed) {
      _expandedInFold = false;
      _clearedStoredInFold = false;
    }
    _effective._changed();
  }

  /// The rail's collapse button. Outside book posture it flips the stored
  /// preference, as it always has. In book posture it flips what the user
  /// sees: expanding is remembered only for this posture (and clears a stored
  /// "collapsed", since expanding is then exactly what was asked for);
  /// collapsing again just drops that.
  Future<void> toggle() async {
    if (!_foldCollapsed) return set(!value);
    if (effectiveValue) {
      _expandedInFold = true;
      _effective._changed();
      if (value) {
        _clearedStoredInFold = true;
        await set(false);
      }
    } else {
      _expandedInFold = false;
      _effective._changed();
      if (_clearedStoredInFold) {
        _clearedStoredInFold = false;
        await set(true);
      }
    }
  }

  @override
  void dispose() {
    removeListener(_effective._changed);
    _effective.dispose();
    super.dispose();
  }
}

class _EffectiveRailCollapsed extends ChangeNotifier
    implements ValueListenable<bool> {
  _EffectiveRailCollapsed(this._owner) : _last = _owner.effectiveValue;

  final SidebarController _owner;
  bool _last;

  void _changed() {
    final now = _owner.effectiveValue;
    if (now == _last) return;
    _last = now;
    notifyListeners();
  }

  @override
  bool get value => _owner.effectiveValue;
}
