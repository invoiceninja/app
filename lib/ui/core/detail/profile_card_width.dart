import 'package:material_ui/material_ui.dart';

/// The width a record screen's profile card is laid out at, told to it by the
/// layout that places it.
///
/// A lead card may not measure itself: it sits in a row levelled with
/// `IntrinsicHeight`, and a `LayoutBuilder` has no intrinsic height. The
/// layout above that row already has its constraints from its own
/// `LayoutBuilder`, so it hands each card its share here — and a card that
/// draws something only where it fits (the Contacts card's avatars,
/// `PartyContactRow.showAvatars`) can measure against it.
class ProfileCardWidthScope extends InheritedWidget {
  const ProfileCardWidthScope({
    super.key,
    required this.width,
    required super.child,
  });

  /// The card's outer width, border included.
  final double width;

  /// The width of the card at [context], or null outside a layout that says.
  static double? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ProfileCardWidthScope>()
      ?.width;

  /// Each of [count] equal cards sharing [total] with a [gap] between them.
  static double share(double total, int count, double gap) =>
      count <= 1 ? total : (total - gap * (count - 1)) / count;

  @override
  bool updateShouldNotify(ProfileCardWidthScope oldWidget) =>
      oldWidget.width != width;
}
