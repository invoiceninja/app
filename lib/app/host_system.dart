/// What the app runs on, as the host describes itself: the browser's user
/// agent on the web, the OS version string on native.
///
/// Conditional-import seam in the house style (default file = web, the
/// `dart.library.io` override = native — see CLAUDE.md § Web). Read only by
/// the Debug Panel's App info tab (`app_info.dart`).
library;

export 'package:admin/app/host_system_web.dart'
    if (dart.library.io) 'package:admin/app/host_system_io.dart';
