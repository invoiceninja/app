import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/lock_after_inactivity_controller.dart';
import 'package:admin/app/services.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/settings/widgets/setting_row.dart';

/// Settings → Device Settings → Security → "Lock after inactivity"
/// (docs/soft-lock.md): Never, or 1 / 5 / 15 / 30 / 60 minutes.
///
/// Mounted by the Security tab only where the device can verify its owner
/// (`BiometricService.canAuthenticateOwner` — biometrics or the device
/// passcode), which the subtitle says: the lock is passed with the device's own
/// sign-in, never the Invoice Ninja password. Turning it on from Never asks
/// for that sign-in first, so nobody sets a lock they can't pass; changing the
/// span or turning it off doesn't.
class LockAfterInactivityTile extends StatefulWidget {
  const LockAfterInactivityTile({super.key});

  @override
  State<LockAfterInactivityTile> createState() =>
      _LockAfterInactivityTileState();
}

class _LockAfterInactivityTileState extends State<LockAfterInactivityTile> {
  bool _busy = false;

  Future<void> _onChanged(
    LockAfterInactivityController controller,
    int minutes,
  ) async {
    if (_busy || minutes == controller.minutes) return;
    if (controller.minutes == 0 && minutes > 0) {
      final biometric = context.read<Services>().biometric;
      final reason = context.tr('please_authenticate');
      setState(() => _busy = true);
      try {
        if (!await biometric.authenticateOwner(reason: reason)) return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    await controller.setMinutes(minutes);
  }

  String _label(BuildContext context, int minutes) => switch (minutes) {
    0 => context.tr('never'),
    1 => context.tr('1_minute'),
    _ => context.tr('count_minutes', {'count': '$minutes'}),
  };

  @override
  Widget build(BuildContext context) {
    final controller = context.read<LockAfterInactivityController?>();
    if (controller == null) return const SizedBox.shrink();
    final tokens = context.inTheme;
    return ValueListenableBuilder<double>(
      valueListenable: controller,
      builder: (context, _, _) => SettingRow(
        icon: const Icon(Icons.lock_clock_outlined),
        title: context.tr('lock_after_inactivity'),
        subtitle: context.tr('lock_after_inactivity_help'),
        control: DropdownButtonHideUnderline(
          child: Container(
            key: const ValueKey('lock_after_inactivity'),
            constraints: BoxConstraints(
              minHeight: Env.isTouchPrimary ? InSizes.touchTarget : 36,
            ),
            padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
            decoration: BoxDecoration(
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(InRadii.r1),
            ),
            alignment: AlignmentDirectional.centerStart,
            child: DropdownButton<int>(
              value: controller.minutes,
              isDense: true,
              borderRadius: BorderRadius.circular(InRadii.r2),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: tokens.ink),
              items: [
                for (final m in kLockAfterInactivityMinutes)
                  DropdownMenuItem<int>(
                    value: m,
                    child: Text(_label(context, m)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (m) {
                      if (m != null) _onChanged(controller, m);
                    },
            ),
          ),
        ),
      ),
    );
  }
}
