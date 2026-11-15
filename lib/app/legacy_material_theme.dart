// The app is on `package:material_ui`, a separate copy of Material whose
// `Theme`, `ThemeData` and `MaterialLocalizations` are different types from
// the framework's. Several dependencies still draw with the framework's own
// Material (super_editor, printing's `PdfPreview`, fl_chart, re_editor,
// flutter_widget_from_html_core), and they look up *its* `Theme` and
// `MaterialLocalizations`, which `material_ui`'s `MaterialApp` never provides.
// This file is the one place that imports the framework library, so every
// legacy lookup resolves to the app's own theme. Delete it once those
// dependencies have moved (docs/upgrading-to-flutter-3-50.md § Material moves
// to material_ui).
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy;
import 'package:flutter/widgets.dart';
// ignore: deprecated_member_use
import 'package:flutter_localizations/flutter_localizations.dart'
    as legacy_l10n;
import 'package:material_ui/material_ui.dart' as modern;

/// The framework Material / Cupertino localizations, for dependencies that
/// call the framework's `MaterialLocalizations.of` (a tooltip, a dropdown).
/// `main.dart` lists them beside `material_ui`'s own delegates.
const List<LocalizationsDelegate<dynamic>>
kLegacyMaterialLocalizationsDelegates = [
  // ignore: deprecated_member_use
  legacy_l10n.GlobalMaterialLocalizations.delegate,
  // ignore: deprecated_member_use
  legacy_l10n.GlobalCupertinoLocalizations.delegate,
];

/// Re-provides the nearest `material_ui` theme as a framework `Theme`.
///
/// `main.dart` mounts one over every route. A widget that needs a legacy
/// value the mapping does not carry (super_editor's caret reads
/// `primaryColor`) mounts its own with [primaryColor].
///
/// Like `MaterialUiCompatibilityBridge`, which `material_ui` ships deprecated,
/// it maps the colour scheme, text theme, density and platform; unlike it, it
/// also carries the text-selection colours and `primaryColor` that the
/// dependencies above read, and it leaves localizations to
/// [kLegacyMaterialLocalizationsDelegates]. Component themes and
/// `ThemeExtension`s (`InTheme`) are not carried: no legacy widget reads ours.
class LegacyMaterialTheme extends StatelessWidget {
  const LegacyMaterialTheme({
    super.key,
    required this.child,
    this.primaryColor,
  });

  final Widget child;

  /// Overrides the mapped `primaryColor`.
  final Color? primaryColor;

  @override
  Widget build(BuildContext context) {
    return legacy.Theme(
      data: legacyThemeDataFrom(
        modern.Theme.of(context),
        primaryColor: primaryColor,
      ),
      child: child,
    );
  }
}

/// The framework `ThemeData` that mirrors [theme]; see [LegacyMaterialTheme].
legacy.ThemeData legacyThemeDataFrom(
  modern.ThemeData theme, {
  Color? primaryColor,
}) {
  final scheme = theme.colorScheme;
  final text = theme.textTheme;
  final selection = theme.textSelectionTheme;
  return legacy.ThemeData(
    brightness: scheme.brightness,
    platform: theme.platform,
    visualDensity: legacy.VisualDensity(
      horizontal: theme.visualDensity.horizontal,
      vertical: theme.visualDensity.vertical,
    ),
    primaryColor: primaryColor ?? theme.primaryColor,
    scaffoldBackgroundColor: theme.scaffoldBackgroundColor,
    canvasColor: theme.canvasColor,
    cardColor: theme.cardColor,
    dividerColor: theme.dividerColor,
    textSelectionTheme: legacy.TextSelectionThemeData(
      cursorColor: selection.cursorColor,
      selectionColor: selection.selectionColor,
      selectionHandleColor: selection.selectionHandleColor,
    ),
    colorScheme: legacy.ColorScheme(
      brightness: scheme.brightness,
      primary: scheme.primary,
      onPrimary: scheme.onPrimary,
      primaryContainer: scheme.primaryContainer,
      onPrimaryContainer: scheme.onPrimaryContainer,
      secondary: scheme.secondary,
      onSecondary: scheme.onSecondary,
      secondaryContainer: scheme.secondaryContainer,
      onSecondaryContainer: scheme.onSecondaryContainer,
      tertiary: scheme.tertiary,
      onTertiary: scheme.onTertiary,
      tertiaryContainer: scheme.tertiaryContainer,
      onTertiaryContainer: scheme.onTertiaryContainer,
      error: scheme.error,
      onError: scheme.onError,
      errorContainer: scheme.errorContainer,
      onErrorContainer: scheme.onErrorContainer,
      surface: scheme.surface,
      onSurface: scheme.onSurface,
      surfaceDim: scheme.surfaceDim,
      surfaceBright: scheme.surfaceBright,
      surfaceContainerLowest: scheme.surfaceContainerLowest,
      surfaceContainerLow: scheme.surfaceContainerLow,
      surfaceContainer: scheme.surfaceContainer,
      surfaceContainerHigh: scheme.surfaceContainerHigh,
      surfaceContainerHighest: scheme.surfaceContainerHighest,
      onSurfaceVariant: scheme.onSurfaceVariant,
      outline: scheme.outline,
      outlineVariant: scheme.outlineVariant,
      shadow: scheme.shadow,
      scrim: scheme.scrim,
      inverseSurface: scheme.inverseSurface,
      onInverseSurface: scheme.onInverseSurface,
      inversePrimary: scheme.inversePrimary,
      surfaceTint: scheme.surfaceTint,
    ),
    textTheme: legacy.TextTheme(
      displayLarge: text.displayLarge,
      displayMedium: text.displayMedium,
      displaySmall: text.displaySmall,
      headlineLarge: text.headlineLarge,
      headlineMedium: text.headlineMedium,
      headlineSmall: text.headlineSmall,
      titleLarge: text.titleLarge,
      titleMedium: text.titleMedium,
      titleSmall: text.titleSmall,
      bodyLarge: text.bodyLarge,
      bodyMedium: text.bodyMedium,
      bodySmall: text.bodySmall,
      labelLarge: text.labelLarge,
      labelMedium: text.labelMedium,
      labelSmall: text.labelSmall,
    ),
  );
}
