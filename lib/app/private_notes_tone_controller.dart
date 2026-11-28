import 'package:admin/data/prefs/device_pref.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/domain/private_notes_tone.dart';

/// Device Settings → Appearance → Private Notes Color: the tone of a record's
/// private-notes callout (`PrivateNotesCallout`), stored by name in
/// `DevicePrefKeys.privateNotesTone`.
///
/// On this device only, like text size and density. It is not part of the
/// synced `flutter_appearance` record: builds from before the field push
/// that record without it, under newer stamps, and a field the record's one
/// stamp cannot order flipped the tone between companies
/// (`docs/detail-screen-layout.md` § The private-notes tone is one of four
/// status tones, never a free colour).
class PrivateNotesToneController extends DevicePref<String> {
  PrivateNotesToneController({required DevicePrefsStore prefs})
    : super(
        prefs,
        DevicePrefKeys.privateNotesTone,
        fallback: PrivateNotesTone.fallback.name,
      );

  /// The stored tone; one this build doesn't know reads as the default.
  PrivateNotesTone get tone =>
      PrivateNotesTone.fromName(value) ?? PrivateNotesTone.fallback;

  Future<void> setTone(PrivateNotesTone tone) => set(tone.name);
}
