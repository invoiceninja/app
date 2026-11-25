import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/dialogs/confirm_sign_out_dialog.dart';
import 'package:admin/ui/features/auth/view_models/lock_view_model.dart';
import 'package:admin/ui/features/shell/widgets/confirm_pending_outbox.dart';

/// The lock's one design, shared by the cold-launch `/lock` screen
/// (`LockScreen`) and the soft lock (`SoftLockHost`, docs/soft-lock.md): an
/// opaque page with the lock mark, a title, a line of copy, and Sign out next
/// to Unlock. Both buttons follow [LockViewModel.busy].
class LockPanel extends StatelessWidget {
  const LockPanel({
    super.key,
    required this.vm,
    required this.title,
    required this.message,
    required this.onUnlock,
    required this.onSignOut,
    this.unlockFocusNode,
  });

  final LockViewModel vm;
  final String title;
  final String message;
  final VoidCallback onUnlock;
  final VoidCallback onSignOut;

  /// The soft lock parks keyboard focus here, inside its own trap.
  final FocusNode? unlockFocusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: InSpacing.xl,
                  vertical: InSpacing.xxl,
                ),
                child: ListenableBuilder(
                  listenable: vm,
                  builder: (context, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 64,
                          color: tokens.accent,
                        ),
                        SizedBox(height: InSpacing.lg(context)),
                        Semantics(
                          header: true,
                          headingLevel: 1,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: tokens.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: InSpacing.sm),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: tokens.ink2, height: 1.4),
                        ),
                        const SizedBox(height: InSpacing.xxl),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton(
                              key: const ValueKey('lock_sign_out'),
                              onPressed: vm.busy ? null : onSignOut,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(120, 40),
                              ),
                              child: Text(context.tr('sign_out')),
                            ),
                            SizedBox(width: InSpacing.md(context)),
                            FilledButton.icon(
                              key: const ValueKey('lock_unlock'),
                              focusNode: unlockFocusNode,
                              onPressed: vm.busy ? null : onUnlock,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(120, 44),
                              ),
                              icon: vm.busy
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        // On the disabled fill.
                                        color: tokens.ink3,
                                      ),
                                    )
                                  : const Icon(Icons.fingerprint, size: 18),
                              label: Text(context.tr('unlock')),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A lock's Sign out — the cold-launch screen's and the soft lock's alike.
///
/// Signing out here is a FULL logout, which wipes the whole local DB —
/// every company's still-pending outbox rows included — so it goes through
/// the app's sign-out confirmation (never switchable off) and then the same
/// unsynced-work prompt every other sign-out uses, over all companies. Without
/// it the lock would silently destroy the offline edits the idle-timeout
/// preserve path, and the soft lock itself, deliberately kept alive.
/// Credentials are live behind either lock, so the prompt's Sync first works.
///
/// [canOpenOutbox] false for the soft lock, which asks from above the router
/// (see `confirmPendingOutboxIfAny`).
Future<void> signOutFromLock(
  BuildContext context,
  LockViewModel vm, {
  bool canOpenOutbox = true,
}) async {
  // Resolved before the first await so the confirm below doesn't push a
  // `context` read past one (`use_build_context_synchronously`).
  final services = context.read<Services>();
  // Cannot delegate to `SettingsActions.signOut`: `LockViewModel.signOut()`
  // owns the `busy` flag that gates both buttons on the lock.
  if (!await showConfirmSignOutDialog(context)) return;
  if (!context.mounted) return;
  // The button was enabled when tapped, but the dialog is an await, and
  // `LocalAuthBiometricService` prompts with `persistAcrossBackgrounding`,
  // so a resumed app can land back here with `busy` true — and
  // `LockViewModel.signOut()` opens with `if (_busy) return;`, dropping the
  // request. This bails early rather than walking the user through the
  // outbox prompt first and discarding the answer at the end. It does NOT
  // rescue the sign-out: the request is lost either way, and the user's
  // signal is the buttons going disabled behind the biometric prompt.
  if (vm.busy) return;
  final companyId = services.auth.session.value?.currentCompanyId;
  if (companyId != null) {
    final outbox = await confirmPendingOutboxIfAny(
      context,
      companyId: companyId,
      checkAllCompanies: true,
      canOpenOutbox: canOpenOutbox,
    );
    if (outbox == OutboxConfirmResult.cancelled || !context.mounted) return;
  }
  await vm.signOut();
}
