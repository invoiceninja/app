import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/auth/view_models/lock_view_model.dart';
import 'package:admin/ui/features/auth/widgets/lock_panel.dart';

/// Cold-launch biometric gate. Shown by the router when
/// `AuthRepository.requiresBiometricUnlock` is true. Auto-prompts on mount
/// (matching admin-portal `main_app.dart:228-229`); the user can retry via
/// the Unlock button or fall back to Sign out ([signOutFromLock], which
/// confirms and asks about unsynced work). The soft lock (docs/soft-lock.md)
/// draws the same [LockPanel].
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  late final LockViewModel _vm;

  @override
  void initState() {
    super.initState();
    final services = context.read<Services>();
    _vm = LockViewModel(auth: services.auth, biometric: services.biometric);
    // Auto-trigger on mount, but defer past the first frame so the
    // Localization delegate has resolved.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _vm.unlock(context.tr('please_authenticate'));
    });
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _onUnlock() async {
    await _vm.unlock(context.tr('please_authenticate'));
  }

  Future<void> _onSignOut() => signOutFromLock(context, _vm);

  @override
  Widget build(BuildContext context) {
    return LockPanel(
      vm: _vm,
      title: context.tr('biometric_authentication'),
      message: context.tr('please_authenticate'),
      onUnlock: _onUnlock,
      onSignOut: _onSignOut,
    );
  }
}
