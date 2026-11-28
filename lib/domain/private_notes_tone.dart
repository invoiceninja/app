/// The highlight a record's private notes are drawn in
/// (`PrivateNotesCallout`). One of the status tones every palette already
/// carries in both brightnesses, never a free colour: each is a soft fill
/// with the theme's own ink on it, checked in every light and dark palette as
/// the status pills are (`docs/detail-screen-layout.md` § Private notes are a
/// callout above the comments).
///
/// A leaf: no Flutter. Stored by [name] in `DevicePrefKeys.privateNotesTone`
/// and synced in the `flutter_appearance` record.
enum PrivateNotesTone {
  /// `warning` — the default, the callout's tone since it shipped.
  amber,

  /// `partial` — the blue v1's private notes were drawn in. (`sent` is
  /// amber in these palettes.)
  blue,

  /// `paid`.
  green,

  /// `overdue`.
  red;

  static const PrivateNotesTone fallback = PrivateNotesTone.amber;

  /// The tone stored as [name], or null for one this build doesn't know.
  static PrivateNotesTone? fromName(String? name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return null;
  }
}
