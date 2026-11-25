import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/after_saving_controller.dart';
import 'package:admin/app/print_after_saving_controller.dart';
import 'package:admin/ui/core/adaptive.dart';

/// Whether Save keeps an edit screen open by default on the device showing
/// [context] — the one definition of *automatic* for "After Saving"
/// (docs/after-saving.md): everywhere but a phone. It reads the window, not
/// the pane, so an editor in a slide-over and the Device Settings row agree.
bool staysInEditorByDefault(BuildContext context) =>
    !Breakpoints.isPhone(context);

/// The UI's way into [AfterSavingController]: every reader and writer
/// resolves *automatic* through [staysInEditorByDefault].
extension AfterSavingInContext on AfterSavingController {
  /// Whether Save keeps the editor open on this device right now.
  bool staysIn(BuildContext context) =>
      staysFor(isPhone: !staysInEditorByDefault(context));

  /// Store [stay] — as automatic when it is what this device would pick.
  Future<void> setIn(BuildContext context, bool stay) =>
      set(stay, isPhone: !staysInEditorByDefault(context));
}

/// Whether a plain Save on the editor at [context] keeps it open. Without the
/// controller (a test with no provider) it is false: Save goes to the record,
/// as it did before the setting existed.
bool staysInEditorAfterSave(BuildContext context) =>
    context.read<AfterSavingController?>()?.staysIn(context) ?? false;

/// Whether a plain Save on the editor at [context] also prints the record —
/// Device Settings → Print After Saving, for an editor that has a print
/// action (`EntityEditScaffold.printAction`). Without the controller (a test
/// with no provider) it is false.
bool printsAfterSave(BuildContext context) =>
    context.read<PrintAfterSavingController?>()?.value ?? false;
