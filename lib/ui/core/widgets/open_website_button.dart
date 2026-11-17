import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/utils/external_url.dart';
import 'package:admin/utils/url_safety.dart';

/// The open-link button at the end of a website field: opens what the user
/// typed in the browser, so they can check the address without leaving the
/// form. Enabled only when the value is a web address that is safe to open
/// ([openableWebsiteUrl] — `https://` assumed when no scheme was typed).
///
/// Sized for the input device, not the viewport
/// (`docs/touch-targets.md`): the 44 px touch floor on a touch-primary
/// device, a compact 32 px box with a pointer, so the field stays the height
/// of its neighbours.
class OpenWebsiteButton extends StatelessWidget {
  const OpenWebsiteButton({super.key, required this.value, this.touch});

  /// The field's current text.
  final String value;

  /// Overrides [Env.isTouchPrimary], for tests.
  final bool? touch;

  @override
  Widget build(BuildContext context) {
    final url = openableWebsiteUrl(value);
    final isTouch = touch ?? Env.isTouchPrimary;
    final side = isTouch ? InSizes.touchTarget : 32.0;
    return IconButton(
      tooltip: context.tr('view_website'),
      onPressed: url == null ? null : () => openExternalUrl(context, url),
      icon: const Icon(Icons.open_in_new, size: 18),
      color: context.inTheme.ink2,
      // Visibly off while there is nothing to open.
      disabledColor: context.inTheme.ink4,
      // Explicit constraints and no density: `compact` would take 8 off them
      // (touch-targets trap 2), and the padded tap-target size would inflate
      // the layout to 48 (trap 3).
      visualDensity: VisualDensity.standard,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      constraints: BoxConstraints.tightFor(width: side, height: side),
      padding: EdgeInsets.zero,
    );
  }
}
