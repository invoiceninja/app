import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/domain/terminal/terminal_eligibility.dart';

/// Apple's Tap to Pay on iPhone symbol, SF Symbols' `wave.3.right.circle`
/// (App Review 5.5): on iOS the only icon the feature may carry. Drawn once
/// by iOS at boot ([load]) and cached; until then, and anywhere else, there
/// is none (docs/in-person-payments.md).
abstract final class TapToPaySymbol {
  static const name = 'wave.3.right.circle';

  /// The PNG iOS drew, black on transparent; null until [load] finishes.
  static final ValueNotifier<Uint8List?> image = ValueNotifier(null);

  static Future<void>? _loading;

  /// Asks iOS to draw it, once per launch. Never throws.
  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    if (!isIPhonePlatform()) return;
    try {
      // Large enough to stay sharp at every size the app draws it.
      final bytes = await StripeTerminal.symbolImage(name, size: 64);
      if (bytes != null && bytes.isNotEmpty) image.value = bytes;
    } catch (_) {}
  }
}

/// [TapToPaySymbol] at [size], tinted [color] (the ambient icon colour by
/// default) — in place of `Icons.contactless_outlined` on iOS. Decorative:
/// the label beside it names the feature, so screen readers skip it. Holds
/// its square empty until iOS has drawn the symbol.
class TapToPayIcon extends StatelessWidget {
  const TapToPayIcon({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ValueListenableBuilder<Uint8List?>(
      valueListenable: TapToPaySymbol.image,
      builder: (context, bytes, _) => bytes == null
          ? SizedBox.square(dimension: size)
          : Image.memory(
              bytes,
              width: size,
              height: size,
              color: color ?? IconTheme.of(context).color,
              colorBlendMode: BlendMode.srcIn,
              excludeFromSemantics: true,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
    ),
  );
}
