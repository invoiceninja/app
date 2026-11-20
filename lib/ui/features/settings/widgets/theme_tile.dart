import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme_controller.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/in_segmented.dart';
import 'package:admin/ui/features/settings/widgets/setting_row.dart';

/// The brightness the app is actually rendering: explicit Light/Dark, or the
/// OS brightness under Auto. Drives which side the Palette row + the
/// Customize section edit ("edit what you see").
Brightness activeBrightness(BuildContext context, ThemeMode mode) =>
    switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };

String lightVariantKey(LightVariant v) => switch (v) {
  LightVariant.sand => 'variant_sand',
  LightVariant.mist => 'variant_mist',
  LightVariant.paper => 'variant_paper',
};

String darkVariantKey(DarkVariant v) => switch (v) {
  DarkVariant.espresso => 'variant_espresso',
  DarkVariant.midnight => 'variant_midnight',
  DarkVariant.carbon => 'variant_carbon',
};

/// Two rows: the theme mode (Auto / Light / Dark) and the palette preset for
/// the brightness currently in effect, with a divider between them. Colour
/// customization is the "Custom colors" row after them.
class ThemeTile extends StatelessWidget {
  const ThemeTile({super.key, required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModeRow(controller: controller),
            const SettingRowDivider(),
            _PaletteRow(controller: controller),
          ],
        );
      },
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.controller});
  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    final mode = controller.themeMode;
    return SettingRow(
      icon: const Icon(Icons.contrast),
      title: context.tr('theme'),
      subtitle: _label(context, mode),
      details: const SyncedWithAccountNote(),
      control: InSegmented<ThemeMode>(
        segments: [
          InSegment(value: ThemeMode.system, label: context.tr('auto')),
          InSegment(value: ThemeMode.light, label: context.tr('light')),
          InSegment(value: ThemeMode.dark, label: context.tr('dark')),
        ],
        selected: mode,
        onChanged: controller.setThemeMode,
      ),
    );
  }

  static String _label(BuildContext context, ThemeMode mode) => switch (mode) {
    ThemeMode.system => context.tr('match_system'),
    ThemeMode.light => context.tr('light'),
    ThemeMode.dark => context.tr('dark'),
  };
}

/// The palette preset for the brightness in effect: Sand / Mist / Paper in
/// light, Espresso / Midnight / Carbon in dark. Each segment's dot is that
/// preset's own background token, so the dots are always the palettes of the
/// brightness on screen. The subtitle says what a palette is and holds in
/// either brightness — never "for light mode".
class _PaletteRow extends StatelessWidget {
  const _PaletteRow({required this.controller});
  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    final dark =
        activeBrightness(context, controller.themeMode) == Brightness.dark;
    final Widget picker = dark
        ? InSegmented<DarkVariant>(
            segments: [
              for (final v in DarkVariant.values)
                InSegment(
                  value: v,
                  label: context.tr(darkVariantKey(v)),
                  swatch: v.tokens.bg,
                ),
            ],
            selected: controller.darkVariant,
            onChanged: controller.setDarkVariant,
          )
        : InSegmented<LightVariant>(
            segments: [
              for (final v in LightVariant.values)
                InSegment(
                  value: v,
                  label: context.tr(lightVariantKey(v)),
                  swatch: v.tokens.bg,
                ),
            ],
            selected: controller.lightVariant,
            onChanged: controller.setLightVariant,
          );
    return SettingRow(
      icon: const Icon(Icons.palette_outlined),
      title: context.tr('palette'),
      subtitle: context.tr('palette_help'),
      details: const SyncedWithAccountNote(),
      control: picker,
    );
  }
}

/// "Synced with your account", under each Device Settings row whose value
/// follows the user to their other devices — the theme, the palette and the
/// custom colours (`AppearanceSyncController`, invoiceninja/app#199). The rest
/// of the page stays on the device, so the rows say which ones don't.
class SyncedWithAccountNote extends StatelessWidget {
  const SyncedWithAccountNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.sync, size: 14, color: context.inTheme.ink3),
        const SizedBox(width: InSpacing.xs),
        Flexible(child: Text(context.tr('synced_with_your_account'))),
      ],
    );
  }
}
