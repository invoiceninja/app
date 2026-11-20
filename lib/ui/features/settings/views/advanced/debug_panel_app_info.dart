import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/app_info.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/fold_geometry.dart';
import 'package:admin/ui/core/widgets/app_selection_area.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';

/// The Debug Panel's App info tab: how this copy of the app is running —
/// build, platform (and on the web, WebAssembly or JavaScript and the
/// renderer), server and display — as selectable label / value rows, with
/// Copy all writing them as plain `label: value` lines.
///
/// The rows come from [appInfoRows] (`lib/app/app_info.dart`); this widget
/// only gathers what needs a `BuildContext` or the session and renders them.
class DebugAppInfoTab extends StatefulWidget {
  const DebugAppInfoTab({super.key});

  @override
  State<DebugAppInfoTab> createState() => _DebugAppInfoTabState();
}

class _DebugAppInfoTabState extends State<DebugAppInfoTab> {
  String? _buildNumber;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBuildNumber());
  }

  Future<void> _loadBuildNumber() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _buildNumber = info.buildNumber);
    } catch (_) {
      // No build number to show; the row stays out.
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = context.read<Services?>();
    if (services == null) return _body(context, null);
    return ListenableBuilder(
      listenable: Listenable.merge([
        services.auth.session,
        services.serverVersion,
      ]),
      builder: (context, _) => _body(context, services),
    );
  }

  Widget _body(BuildContext context, Services? services) {
    final session = services?.auth.session.value;
    final serverVersion = (services?.serverVersion.value ?? '').trim();
    final rows = appInfoRows(
      AppInfoInputs.running(
        buildNumber: _buildNumber,
        serverUrl: session?.baseUrl,
        isHosted: session?.isHosted ?? false,
        // The `x-app-version` the feature gates read, else what the session
        // reported at sign-in.
        serverVersion: serverVersion.isNotEmpty
            ? serverVersion
            : session?.serverCurrentVersion ?? '',
        plan: session?.plan ?? '',
        reportErrors: session?.reportErrors ?? false,
        screenSize: MediaQuery.sizeOf(context),
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
        textScale: MediaQuery.textScalerOf(context).scale(100) / 100,
        locale: Localizations.localeOf(context),
        textDirection: Directionality.of(context),
        brightness: Theme.of(context).brightness,
        foldFeatures: describeDisplayFeatures(context),
        bookPosture: FoldPostureScope.bookPostureOf(context),
      ),
      context.tr,
    );
    // One card, so a plain scroll view: nothing here is lazy.
    return SingleChildScrollView(
      padding: EdgeInsets.all(InSpacing.lg(context)),
      child: FormSection(
        title: context.tr('app_info'),
        trailing: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: Text(context.tr('app_info_copy_all')),
          onPressed: () => copyToClipboard(
            context,
            appInfoText(rows),
            label: context.tr('app_info'),
          ),
        ),
        spacing: InSpacing.sm,
        children: [
          AppSelectionArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = !Breakpoints.isWide(constraints);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in rows)
                      _AppInfoRowView(row: row, stacked: stacked),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One label / value pair: side by side when there is room, the label above
/// the value when there is not.
class _AppInfoRowView extends StatelessWidget {
  const _AppInfoRowView({required this.row, required this.stacked});

  final AppInfoRow row;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final label = Text(
      row.label,
      style: TextStyle(color: tokens.ink3, fontSize: 13),
    );
    // A user agent, a URL, a version — LTR in every language; a translated
    // yes / no keeps its own script's direction.
    final value = LtrText(
      row.value,
      keepRtlScript: true,
      style: TextStyle(color: tokens.ink, fontSize: 13),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: InSpacing.xs),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, value],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 180, child: label),
                SizedBox(width: InSpacing.md(context)),
                Expanded(child: value),
              ],
            ),
    );
  }
}
