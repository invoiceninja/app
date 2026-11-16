import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/services.dart';
import 'package:admin/l10n/localization.dart';

/// Slim strip across the top of the authenticated shell. Renders nothing
/// when the device is online; on offline shows a wifi-off pill + an
/// explanation that saves are queued and will sync when the radio returns.
///
/// Subscribes to [Services.connectivity]'s `isOnlineStream`, which seeds
/// with the current state on listen so the banner appears immediately if
/// the app boots offline.
///
/// The pre-authenticated demo build ([Env.isDemoBuild]) shows a "Demo mode"
/// strip here instead, always, and never the offline one: a browser's
/// `navigator.onLine` is the only signal on web and it reports offline on
/// machines that are plainly loading the demo, where "your changes will sync"
/// is the wrong thing to tell a visitor to shared sample data.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.isDemoBuild = Env.isDemoBuild});

  final bool isDemoBuild;

  @override
  Widget build(BuildContext context) {
    if (isDemoBuild) {
      return const _BannerStrip(
        icon: Icons.science_outlined,
        titleKey: 'demo_mode',
        bodyKey: 'demo_mode_banner',
      );
    }
    final services = context.read<Services>();
    return StreamBuilder<bool>(
      stream: services.connectivity.isOnlineStream,
      builder: (context, snapshot) {
        final online = snapshot.data;
        // Hide while we don't know yet — avoids a flash of "offline" during
        // the first frame on a slow platform channel response.
        if (online == null || online) return const SizedBox.shrink();
        return const _BannerStrip(
          icon: Icons.wifi_off,
          titleKey: 'offline',
          bodyKey: 'offline_changes_will_sync',
        );
      },
    );
  }
}

class _BannerStrip extends StatelessWidget {
  const _BannerStrip({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
  });

  final IconData icon;
  final String titleKey;
  final String bodyKey;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Material(
      color: tokens.partialSoft,
      // Honor the top inset so the strip doesn't render behind the status
      // bar / notch on narrow layouts (where the banner sits above the
      // per-screen Scaffold). On desktop / wide layout viewPadding is zero,
      // so this is a no-op there. SafeArea sits inside the colored Material
      // so the inset is tinted along with the rest of the banner.
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: InSpacing.lg(context),
            vertical: InSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: tokens.partial),
              const SizedBox(width: InSpacing.sm),
              Text(
                context.tr(titleKey),
                style: TextStyle(
                  color: tokens.partial,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: InSpacing.sm),
              Expanded(
                child: Text(
                  context.tr(bodyKey),
                  style: TextStyle(color: tokens.ink2, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
