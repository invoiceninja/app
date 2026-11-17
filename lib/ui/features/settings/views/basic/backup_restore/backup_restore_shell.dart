import 'package:material_ui/material_ui.dart';

import 'package:admin/ui/features/settings/views/basic/backup_restore/widgets/backup_tab.dart';
import 'package:admin/ui/features/settings/views/basic/backup_restore/widgets/restore_tab.dart';
import 'package:admin/ui/features/settings/widgets/settings_form_shell.dart';
import 'package:admin/ui/features/settings/widgets/settings_screen_scaffold.dart';

/// Every label on the page — the Backup card's, then the Restore card's.
const kBackupRestoreSearchKeys = <String>[
  ...kBackupTabSearchKeys,
  ...kRestoreTabSearchKeys,
];

/// Settings → Backup | Restore. One page, two cards:
///
/// * Backup — the server emails the user a download link for the current
///   company's export.
/// * Restore — chunked .zip upload into `/api/v1/import_json`.
///
/// They used to be two tabs, each holding one short card, so the page was
/// mostly empty and the restore options were a tab away from the backup they
/// pair with. `/settings/backup_restore/restore` still resolves (a restored
/// route or an old link lands on it) and scrolls the Restore card into view.
///
/// No VM and no Save — neither card has a settings draft.
class BackupRestoreShell extends StatefulWidget {
  const BackupRestoreShell({super.key, this.initialTab});

  /// The `:tab` path-parameter from the route — `'restore'` on the old Restore
  /// tab's URL, null on the bare one.
  final String? initialTab;

  @override
  State<BackupRestoreShell> createState() => _BackupRestoreShellState();
}

class _BackupRestoreShellState extends State<BackupRestoreShell> {
  final GlobalKey _restoreKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.initialTab == 'restore') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _restoreKey.currentContext;
        if (target == null || !target.mounted) return;
        Scrollable.ensureVisible(target, duration: Duration.zero);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScreenScaffold(
      titleKey: 'backup_restore',
      body: SettingsFormShell(
        sections: [
          const BackupSection(),
          KeyedSubtree(key: _restoreKey, child: const RestoreSection()),
        ],
      ),
    );
  }
}
